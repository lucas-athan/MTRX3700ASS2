`timescale 1ns/1ps
// ============================================================
// ADSR Brightness Filter
// Time-variant spatial brightness modulation using ADSR envelope.
// Compatible handshake:
//   input  module_ready  (downstream ready)
//   output output_ready  (upstream ready)
// ============================================================

module adsr_filter #(
  parameter int ATTACK         = 255,
  parameter int DECAY          = 255,
  parameter int SUSTAIN        = 255,
  parameter int RELEASE        = 255,
  parameter int MIN_BPM        = 40,
  parameter int MAX_BPM        = 200,
  parameter int BITS           = 8,
  parameter int IMAGE_WIDTH    = 640,
  parameter int IMAGE_HEIGHT   = 480,
  parameter int STEP_SIZE      = (256 * (1 << 8)) / MAX_BPM,
  parameter int PIX_CLK_MHZ    = 25  // Pixel clock frequency in MHz
)(
  input  logic                              clk,
  input  logic                              reset,

  // Input pixel stream (one pixel per cycle)
  input  logic [BITS-1:0]                   pix_in,
  input  logic                              valid_in,
  input  logic                              module_ready,   // from downstream
  output logic                              output_ready,   // to upstream
  output logic [BITS-1:0]                   pix_out,
  output logic                              valid_out,

  // Control
  input  logic                              filter_enable,
  input  logic                              beat_trigger,   // Trigger ADSR on beat
  input  logic [$clog2(MAX_BPM+1)-1:0]      BPM_estimate,
  input  logic [BITS-1:0]                   pulse_amplitude,

  // Debug outputs
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

  // Upstream ready follows downstream ready
  assign output_ready = module_ready;

  // ============================================================
  // ADSR Envelope Generator (runs independently of pixel stream)
  // ============================================================
  typedef enum logic [2:0] {S_IDLE, S_ATTACK, S_DECAY, S_SUSTAIN, S_RELEASE} adsr_state_t;
  adsr_state_t state, next_state;

  logic [15:0] adsr_counter;
  logic [15:0] env_gain;
  logic [BITS-1:0] decay_target;

  // Tick generator: every 4 ms
  // For 25 MHz: 4ms * 25MHz = 100,000 cycles
  localparam int TICK_DIV = (PIX_CLK_MHZ * 4_000);  // 4ms in clock cycles
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

  // Next-state logic - can trigger/restart on beat or loop continuously
  always_comb begin
    next_state = state;
    case (state)
      S_IDLE:    if (filter_enable) next_state = S_ATTACK;  // Auto-start when enabled
      S_ATTACK:  if (beat_trigger && filter_enable) next_state = S_ATTACK;  // Restart on beat
                 else if (adsr_counter >= ATTACK && ATTACK > 0) next_state = S_DECAY;
      S_DECAY:   if (beat_trigger && filter_enable) next_state = S_ATTACK;  // Restart on beat
                 else if (adsr_counter >= DECAY && DECAY > 0) next_state = S_SUSTAIN;
      S_SUSTAIN: if (beat_trigger && filter_enable) next_state = S_ATTACK;  // Restart on beat
                 else if (adsr_counter >= SUSTAIN && SUSTAIN > 0) next_state = S_RELEASE;
      S_RELEASE: if (beat_trigger && filter_enable) next_state = S_ATTACK;  // Restart on beat
                 else if (adsr_counter >= RELEASE && RELEASE > 0) next_state = S_ATTACK;  // Loop back
      default:   next_state = S_IDLE;
    endcase
  end

  // State register
  always_ff @(posedge clk or posedge reset) begin
    if (reset)
      state <= S_IDLE;
    else if (tick_4ms)
      state <= next_state;
  end

  // Envelope value generator
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      adsr_counter <= 0;
      env_gain     <= 0;
      decay_target <= 0;
    end else if (tick_4ms) begin
      case (state)
        S_ATTACK: begin
          if (ATTACK > 0) begin
            adsr_counter <= adsr_counter + 1;
            env_gain <= (adsr_counter * 16'd255) / ATTACK;
            if (adsr_counter >= ATTACK) begin
              adsr_counter <= 0;
              decay_target <= (env_gain > DECAY) ? (env_gain - DECAY) : 0;
            end
          end else begin
            env_gain <= 255;
            adsr_counter <= 0;
          end
        end

        S_DECAY: begin
          if (DECAY > 0) begin
            adsr_counter <= adsr_counter + 1;
            if (env_gain > decay_target)
              env_gain <= env_gain - ((env_gain - decay_target) * adsr_counter) / DECAY;
            else
              env_gain <= decay_target;
            if (adsr_counter >= DECAY)
              adsr_counter <= 0;
          end else begin
            env_gain <= decay_target;
            adsr_counter <= 0;
          end
        end

        S_SUSTAIN: begin
          if (SUSTAIN > 0) begin
            adsr_counter <= adsr_counter + 1;
            env_gain <= decay_target;
            if (adsr_counter >= SUSTAIN)
              adsr_counter <= 0;
          end else begin
            env_gain <= decay_target;
            adsr_counter <= 0;
          end
        end

        S_RELEASE: begin
          if (RELEASE > 0) begin
            adsr_counter <= adsr_counter + 1;
            if (env_gain > 0)
              env_gain <= env_gain - (env_gain * adsr_counter) / RELEASE;
            else
              env_gain <= 0;
            if (adsr_counter >= RELEASE)
              adsr_counter <= 0;
          end else begin
            env_gain <= 0;
            adsr_counter <= 0;
          end
        end

        default: begin
          env_gain <= 0;
          adsr_counter <= 0;
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

  // Pulse center (signed)
  logic signed [15:0] cx = IMAGE_WIDTH / 2;
  logic signed [15:0] cy = IMAGE_HEIGHT / 2;

  logic signed [15:0] dx, dy;
  logic [31:0] dist_sq;
  
  // Stage 1 pipeline registers
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
  // Pipeline Stage 2: BPM-based and envelope brightness scaling
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
        // When disabled, zero out the gains
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
  // Pipeline Stage 4: Output pixel application
  // ============================================================
  // Declare temp_sum outside the always block
  logic [BITS:0] temp_sum;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pix_out         <= 0;
      brightness_gain <= 0;
      valid_out       <= 0;
      temp_sum        <= 0;
    end else if (module_ready) begin
      if (valid_stage3) begin
        brightness_gain <= brightness_gain_temp;

        if (filter_enable && brightness_gain_temp != 0) begin
          // Apply brightness - ensure no overflow
          temp_sum = pix_stage3 + brightness_gain_temp;
          pix_out <= (temp_sum > 255) ? 8'd255 : temp_sum[BITS-1:0];
        end else begin
          pix_out <= pix_stage3; // transparent passthrough
        end

        valid_out <= 1'b1;
      end else begin
        valid_out <= 1'b0;
      end
    end
  end

endmodule