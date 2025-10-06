module adsr_filter #(
    parameter int ATTACK = 2, DECAY = 2, SUSTAIN = 2, RELEASE = 2,
    parameter int MIN_BPM = 40, MAX_BPM = 200,
    parameter int BITS = 8,
    parameter int IMAGE_WIDTH = 640, IMAGE_HEIGHT = 480,
    parameter int N_PIX = 8, // number of parallel pixels per clock
    parameter int STEP_SIZE    = (256 * (1<<8)) / MAX_BPM
) (
    input  logic                               clk,
    input  logic                               reset,
    input  logic [BITS-1:0]                    pix_in [N_PIX],
    input  logic                               valid_in,
    input  logic                               output_ready,
    output logic                               module_ready,
    output logic [BITS-1:0]                    pix_out [N_PIX],
    output logic                               valid_out,

    // new spatial inputs
    input  logic [$clog2(IMAGE_WIDTH)-1:0]     pixel_x [N_PIX],
    input  logic [$clog2(IMAGE_HEIGHT)-1:0]    pixel_y,

    // control
    input  logic                               filter_enable,
    input  logic                               filter_mode,
    input  logic [$clog2(MAX_BPM+1)-1:0]       BPM_estimate,
    input  logic [BITS-1:0]                    pulse_amplitude,

    // brightness debugging
    output logic [BITS-1:0]       bpm_brightness_gain,
    output logic [BITS-1:0]       env_brightness_gain,
    output logic [23:0]           bpm_brightness_mult,
    output logic [BITS-1:0]       brightness_gain [N_PIX]

);

assign module_ready = output_ready;
assign valid_out = module_ready && valid_in && filter_enable;

logic [BITS-1:0] radius;
assign radius = pulse_amplitude >> 1;

// Internal registers for the pulse center
logic [$clog2(IMAGE_WIDTH)-1:0] cx;
logic [$clog2(IMAGE_HEIGHT)-1:0] cy;

// Set Pulse center location
initial begin
    cx = IMAGE_WIDTH/2;
    cy = IMAGE_HEIGHT/2;
end

// Find edge of Pulse distance
logic [31:0] dist_sq [N_PIX];
logic [31:0] radius_sq;
assign radius_sq = radius * radius;

logic signed [15:0] dx, dy;

// Calculate distance squared of current pixel to center of pulse
always_comb begin
    for (int i = 0; i < N_PIX; i++) begin
        dx = $signed(pixel_x[i]) - $signed(cx);
        dy = $signed(pixel_y) - $signed(cy);
        dist_sq[i] = dx * dx + dy * dy;
    end
end

// // Determine whether a pixel is within the pulse range
// logic inside_pulse [N_PIX];
// always_comb begin
//     for (int i = 0; l < N_PIX; i++) begin
//         inside_pulse[i] = (dist_sq[i] <= radius_sq);
//     end
// end

// Brightness Calculations

// Scale brightness based on BPM
assign bpm_brightness_mult = (STEP_SIZE * BPM_estimate) >> 8;
assign bpm_brightness_gain      = (bpm_brightness_mult > 255) ? 8'd255 : bpm_brightness_mult[7:0];
assign env_brightness_gain = (env_gain * bpm_brightness_gain) >> 8;

logic [31:0] diff [N_PIX];

// always_comb begin
//     for (int i=0; i < N_PIX; i++) begin
//         // Determine whether a pixel within the pulse range, if no then 0 brightness
//         if (dist_sq[i] >= radius_sq) begin
//             brightness_gain[i] = 0;
//         end
//         else begin
//             diff = (radius_sq - dist_sq[i]) >> 8;
//             brightness_gain[i] = ((bpm_brightness_gain));// / radius_sq;
//         end
//     end
// end

logic [BITS-1:0] brightness_gain_temp [N_PIX];

always_ff @(posedge clk) begin
  for (int i = 0; i < N_PIX; i++) begin
    if (dist_sq[i] >= radius_sq) begin
      brightness_gain_temp[i] <= 0;
    end
    else begin
      diff[i] <= (radius_sq - dist_sq[i]);
      brightness_gain_temp[i] <= (diff[i] * env_brightness_gain) / radius_sq;
    end
  end
end



// Apply filter to pixels
logic [BITS:0] pix_bright_addition;
logic [BITS-1:0]  temp_pix_out [N_PIX]; 

always_comb begin 
    for (int i = 0; i < N_PIX; i++) begin
        if (module_ready && valid_in && filter_enable) begin
            if (brightness_gain_temp[i] != 0) begin
                pix_bright_addition = (pix_in[i] + brightness_gain_temp[i]) >> 1;
                temp_pix_out[i] = pix_bright_addition;
            end
            else
                temp_pix_out[i] = pix_in[i];
        end
        else begin
            temp_pix_out[i] = pix_in[i];
        end
    end
end

// ADSR state-machine
typedef enum logic [2:0] {S_IDLE, S_ATTACK, S_DECAY, S_SUSTAIN, S_RELEASE} adsr_state_t;
adsr_state_t state, next_state;
logic [15:0] adsr_counter;
logic [15:0] env_gain;

// ADSR timer
localparam int TICK_DIV = 200_000;
logic [17:0] tick_cnt;
logic tick_4ms;

always_ff @(posedge clk) begin
    if (reset) begin
        tick_cnt <= 0;
        tick_4ms <= 0;
    end 
    else if (tick_cnt == TICK_DIV-1) begin
        tick_cnt <= 0;
        tick_4ms <= 1;
    end 
    else begin
        tick_cnt <= tick_cnt + 1;
        tick_4ms <= 0;
    end
end

// Next State Logic
always_comb begin
  next_state = state;
  case (state)
    S_IDLE: begin
      if (valid_in && filter_enable)
        next_state = S_ATTACK;
      else
        next_state = S_IDLE;
    end

    S_ATTACK: begin
      if (adsr_counter == ATTACK)
        next_state = S_DECAY;
      else
        next_state = S_ATTACK;
    end

    S_DECAY: begin
      if (adsr_counter == DECAY)
        next_state = S_SUSTAIN;
      else
        next_state = S_DECAY;
    end

    S_SUSTAIN: begin
      if (adsr_counter == SUSTAIN)
        next_state = S_RELEASE;
      else
        next_state = S_SUSTAIN;
    end

    S_RELEASE: begin
      if (adsr_counter == RELEASE)
        next_state = S_IDLE;
      else
        next_state = S_RELEASE;
    end

    default: next_state = S_IDLE;
  endcase
end




// Update temp_pix_out depending on state --> state register
logic [BITS-1:0] decay_target;

// --- State register ---
always_ff @(posedge clk) begin
  if (reset)
    state <= S_IDLE;
  else if (tick_4ms)
    state <= next_state;
end

// --- Envelope evolution ---
always_ff @(posedge clk) begin
  if (reset) begin
    adsr_counter <= 0;
    env_gain     <= 0;
    decay_target <= 0;
  end
  else if (tick_4ms) begin
    case (state)
      S_ATTACK: begin
        adsr_counter <= adsr_counter + 1;
        env_gain <= (adsr_counter * 8'd255) / ATTACK;
        if (adsr_counter == ATTACK) begin
          adsr_counter <= 0;
          decay_target <= env_gain - DECAY; // Set decay target at end of attack
        end
      end

      S_DECAY: begin
        adsr_counter <= adsr_counter + 1;
        env_gain <= env_gain - ((env_gain - decay_target) * adsr_counter) / DECAY;
        if (adsr_counter == DECAY)
          adsr_counter <= 0;
      end

      S_SUSTAIN: begin
        adsr_counter <= adsr_counter + 1;
        env_gain <= decay_target;
        if (adsr_counter == SUSTAIN)
          adsr_counter <= 0;
      end

      S_RELEASE: begin
        adsr_counter <= adsr_counter + 1;
        env_gain <= env_gain - (env_gain * adsr_counter) / RELEASE;
        if (adsr_counter == RELEASE)
          adsr_counter <= 0;
      end

      default: begin
        env_gain <= 0;
        adsr_counter <= 0;
      end
    endcase
  end
end



always_ff @(posedge clk or posedge reset) begin
  if (reset) begin
    for (int i = 0; i < N_PIX; i++) begin
      pix_out[i] <= 0;
      brightness_gain[i] <= 0;
    end
  end
  else if (valid_out) begin
    for (int i = 0; i < N_PIX; i++) begin
      pix_out[i] <= temp_pix_out[i];
      brightness_gain[i] <= brightness_gain_temp[i];
    end
  end
end




endmodule




