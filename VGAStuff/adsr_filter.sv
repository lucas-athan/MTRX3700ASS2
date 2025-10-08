`timescale 1ns/1ps
// ============================================================
// ADSR Brightness Filter - FIXED VERSION
// Changes:
// 1. Added SUSTAIN_LEVEL parameter (0-255) for proper ADSR
// 2. Fixed decay_target calculation
// 3. Simplified envelope generation logic
// 4. Changed brightness application to use multiplication instead of addition
// ============================================================

module adsr_filter #(
  parameter int ATTACK         = 150,
  parameter int DECAY          = 100,
  parameter int SUSTAIN_TIME   = 100,  // Renamed for clarity
  parameter int SUSTAIN_LEVEL  = 128,  // NEW: Target level for sustain (0-255)
  parameter int RELEASE        = 40,
  parameter int MIN_BPM        = 40,
  parameter int MAX_BPM        = 200,
  parameter int BITS           = 8,
  parameter int IMAGE_WIDTH    = 640,
  parameter int IMAGE_HEIGHT   = 480,
  parameter int STEP_SIZE      = (256 * (1 << 8)) / MAX_BPM,
  parameter int PIX_CLK_MHZ    = 25
)(
  input  logic                              clk,
  input  logic                              reset,

  input  logic [BITS-1:0]                   pix_in,
  input  logic                              valid_in,
  input  logic                              module_ready,
  output logic                              output_ready,
  output logic [BITS-1:0]                   pix_out,
  output logic                              valid_out,

  input  logic                              filter_enable,
  input  logic                              beat_trigger,
  input  logic [$clog2(MAX_BPM+1)-1:0]      BPM_estimate,
  input  logic [BITS-1:0]                   pulse_amplitude,

  output logic [BITS-1:0]                   bpm_brightness_gain,
  output logic [BITS-1:0]                   env_brightness_gain,
  output logic [23:0]                       bpm_brightness_mult,
  output logic [BITS-1:0]                   brightness_gain
);

  // ============================================================
  // Pixel coordinates
  // ============================================================
  logic [$clog2(IMAGE_WIDTH)-1:0]  pixel_x;
  logic [$clog2(IMAGE_HEIGHT)-1:0] pixel_y;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pixel_x <= 0;
      pixel_y <= 0;
    end else if (valid_in && module_ready) begin
      if (pixel_x == IMAGE_WIDTH - 1) begin
        pixel_x <= 0;
        if (pixel_y == IMAGE_HEIGHT - 1)
          pixel_y <= 0;
        else
          pixel_y <= pixel_y + 1;
      end else begin
        pixel_x <= pixel_x + 1;
      end
    end
  end

  assign output_ready = module_ready;

  // ============================================================
  // ADSR Envelope Generator - FIXED
  // ============================================================
  typedef enum logic [2:0] {S_IDLE, S_ATTACK, S_DECAY, S_SUSTAIN, S_RELEASE} adsr_state_t;
  adsr_state_t state, next_state;

  logic [15:0] adsr_counter;
  logic [15:0] env_gain;

  // Tick generator: every 4 ms
  localparam int TICK_DIV = (PIX_CLK_MHZ * 4_000);
  localparam int TICK_WIDTH = $clog2(TICK_DIV);
  logic [TICK_WIDTH-1:0] tick_cnt;
  logic        tick_4ms;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      tick_cnt <= 0;
      tick_4ms <= 0;
    end else if (tick_cnt == TICK_DIV - 1) begin
      tick_cnt <= 0;
      tick_4ms <= 1;
    end else begin
      tick_cnt <= tick_cnt + 1;
      tick_4ms <= 0;
    end
  end

  // Next-state logic - FIXED: Only transition on counter completion
  always_comb begin
    next_state = state;
    case (state)
      S_IDLE:    if (filter_enable || beat_trigger) next_state = S_ATTACK;
      S_ATTACK:  if (beat_trigger && filter_enable) next_state = S_ATTACK;  // Restart
                 else if (adsr_counter >= ATTACK) next_state = S_DECAY;
      S_DECAY:   if (beat_trigger && filter_enable) next_state = S_ATTACK;
                 else if (adsr_counter >= DECAY) next_state = S_SUSTAIN;
      S_SUSTAIN: if (beat_trigger && filter_enable) next_state = S_ATTACK;
                 else if (adsr_counter >= SUSTAIN_TIME) next_state = S_RELEASE;
      S_RELEASE: if (beat_trigger && filter_enable) next_state = S_ATTACK;
                 else if (adsr_counter >= RELEASE) next_state = S_ATTACK;  // Loop
      default:   next_state = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset)
      state <= S_IDLE;
    else if (tick_4ms)
      state <= next_state;
  end

  // Envelope value generator - FIXED
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      adsr_counter <= 0;
      env_gain     <= 0;
    end else if (tick_4ms) begin
      // Reset counter on state change
      if (state != next_state) begin
        adsr_counter <= 0;
      end else begin
        adsr_counter <= adsr_counter + 1;
      end

      case (next_state)
        S_ATTACK: begin
          // Rise from 0 to 255
          if (ATTACK > 0)
            env_gain <= (adsr_counter * 16'd255) / ATTACK;
          else
            env_gain <= 255;
        end

        S_DECAY: begin
          // Fall from 255 to SUSTAIN_LEVEL
          if (DECAY > 0) begin
            logic [15:0] decay_amount;
            decay_amount = 255 - SUSTAIN_LEVEL;
            env_gain <= 255 - ((decay_amount * adsr_counter) / DECAY);
          end else begin
            env_gain <= SUSTAIN_LEVEL;
          end
        end

        S_SUSTAIN: begin
          // Hold at SUSTAIN_LEVEL
          env_gain <= SUSTAIN_LEVEL;
        end

        S_RELEASE: begin
          // Fall from SUSTAIN_LEVEL to 0
          if (RELEASE > 0)
            env_gain <= SUSTAIN_LEVEL - ((SUSTAIN_LEVEL * adsr_counter) / RELEASE);
          else
            env_gain <= 0;
        end

        default: begin
          env_gain <= 0;
        end
      endcase
    end
  end

  // ============================================================
  // Pipeline Stage 1: Spatial distance computation
  // ============================================================
  logic [BITS-1:0] radius;
  assign radius = pulse_amplitude >> 1;

  logic [31:0] radius_sq;
  assign radius_sq = radius * radius;

  logic signed [15:0] cx = IMAGE_WIDTH / 2;
  logic signed [15:0] cy = IMAGE_HEIGHT / 2;

  logic signed [15:0] dx, dy;
  logic [31:0] dist_sq;
  
  logic [BITS-1:0] pix_stage1;
  logic valid_stage1;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      dx <= 0;
      dy <= 0;
      dist_sq <= 0;
      pix_stage1 <= 0;
      valid_stage1 <= 0;
    end else if (module_ready) begin
      if (valid_in) begin
        dx <= $signed(pixel_x) - $signed(cx);
        dy <= $signed(pixel_y) - $signed(cy);
        dist_sq <= dx * dx + dy * dy;
        pix_stage1 <= pix_in;
        valid_stage1 <= 1'b1;
      end else begin
        valid_stage1 <= 1'b0;
      end
    end
  end

  // ============================================================
  // Pipeline Stage 2: BPM and envelope brightness scaling
  // ============================================================
  logic [BITS-1:0] pix_stage2;
  logic valid_stage2;
  logic [31:0] dist_sq_stage2;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      bpm_brightness_mult <= 0;
      bpm_brightness_gain <= 0;
      env_brightness_gain <= 0;
      pix_stage2 <= 0;
      valid_stage2 <= 0;
      dist_sq_stage2 <= 0;
    end else if (module_ready) begin
      if (valid_stage1 && filter_enable) begin
        bpm_brightness_mult <= (STEP_SIZE * BPM_estimate) >> 8;
        bpm_brightness_gain <= (bpm_brightness_mult > 255) ? 8'd255 : bpm_brightness_mult[7:0];
        env_brightness_gain <= (env_gain * bpm_brightness_gain) >> 8;
      end else begin
        bpm_brightness_mult <= 0;
        bpm_brightness_gain <= 0;
        env_brightness_gain <= 0;
      end
      pix_stage2 <= pix_stage1;
      dist_sq_stage2 <= dist_sq;
      valid_stage2 <= valid_stage1;
    end
  end

  // ============================================================
  // Pipeline Stage 3: Brightness gain calculation
  // ============================================================
  logic [31:0] diff;
  logic [BITS-1:0] brightness_gain_temp;
  logic [BITS-1:0] pix_stage3;
  logic valid_stage3;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      brightness_gain_temp <= 0;
      diff <= 0;
      pix_stage3 <= 0;
      valid_stage3 <= 0;
    end else if (module_ready) begin
      if (valid_stage2 && filter_enable) begin
        if (dist_sq_stage2 >= radius_sq) begin
          brightness_gain_temp <= 0;
          diff <= 0;
        end else begin
          diff <= radius_sq - dist_sq_stage2;
          if (radius_sq > 0)
            brightness_gain_temp <= (diff * env_brightness_gain) / radius_sq;
          else
            brightness_gain_temp <= 0;
        end
      end else begin
        brightness_gain_temp <= 0;
        diff <= 0;
      end
      pix_stage3 <= pix_stage2;
      valid_stage3 <= valid_stage2;
    end
  end

  // ============================================================
  // Pipeline Stage 4: Output pixel - FIXED to use multiplication
  // ============================================================
  logic [15:0] temp_mult;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pix_out         <= 0;
      brightness_gain <= 0;
      valid_out       <= 0;
      temp_mult       <= 0;
    end else if (module_ready) begin
      if (valid_stage3) begin
        brightness_gain <= brightness_gain_temp;

        if (filter_enable && brightness_gain_temp != 0) begin
          // Multiply pixel by brightness gain (0-255 scale)
          temp_mult = (pix_stage3 * brightness_gain_temp) >> 8;
          pix_out <= (temp_mult > 255) ? 8'd255 : temp_mult[BITS-1:0];
        end else begin
          pix_out <= pix_stage3; // Passthrough
        end

        valid_out <= 1'b1;
      end else begin
        valid_out <= 1'b0;
      end
    end
  end

endmodule