`timescale 1ns/1ps
// ============================================================
// ADSR Brightness Filter
// Time-variant spatial brightness modulation using ADSR envelope.
// Compatible handshake:
//   input  output_ready  (downstream ready)
//   output module_ready  (upstream ready)
// ============================================================

module adsr_filter #(
  parameter int ATTACK         = 2,
  parameter int DECAY          = 2,
  parameter int SUSTAIN        = 2,
  parameter int RELEASE        = 2,
  parameter int MIN_BPM        = 40,
  parameter int MAX_BPM        = 200,
  parameter int BITS           = 8,
  parameter int IMAGE_WIDTH    = 640,
  parameter int IMAGE_HEIGHT   = 480,
  parameter int STEP_SIZE      = (256 * (1 << 8)) / MAX_BPM
)(
  input  logic                              clk,
  input  logic                              reset,

  // Input pixel stream (one pixel per cycle)
  input  logic [BITS-1:0]                   pix_in,
  input  logic                              valid_in,
  input  logic                              output_ready,   // from downstream
  output logic                              module_ready,   // to upstream
  output logic [BITS-1:0]                   pix_out,
  output logic                              valid_out,

  // Control
  input  logic                              filter_enable,
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
    end else if (valid_in) begin
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
  assign module_ready = output_ready;

  // ============================================================
  // Spatial distance computation
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
  logic [31:0] diff;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      dx <= 0;
      dy <= 0;
      dist_sq <= 0;
    end else if (valid_in && filter_enable) begin
      dx <= $signed(pixel_x) - $signed(cx);
      dy <= $signed(pixel_y) - $signed(cy);
      dist_sq <= dx * dx + dy * dy;
    end
  end

  // ============================================================
  // BPM-based and envelope brightness scaling
  // ============================================================
  // assign bpm_brightness_mult = (STEP_SIZE * BPM_estimate) >> 8;
  // assign bpm_brightness_gain = (bpm_brightness_mult > 255) ? 8'd255 : bpm_brightness_mult[7:0];
  // assign env_brightness_gain = (env_gain * bpm_brightness_gain) >> 8;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      bpm_brightness_mult <= 0;
      bpm_brightness_gain <= 0;
      env_brightness_gain <= 0;
    end else if (valid_in && filter_enable) begin
      bpm_brightness_mult <= (STEP_SIZE * BPM_estimate) >> 8;
      bpm_brightness_gain <= (bpm_brightness_mult > 255) ? 8'd255 : bpm_brightness_mult[7:0];
      env_brightness_gain <= (env_gain * bpm_brightness_gain) >> 8;
    end
  end

  // ============================================================
  // Brightness gain logic
  // ============================================================
  logic [BITS-1:0] brightness_gain_temp;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      brightness_gain_temp <= 0;
    end else if (valid_in && filter_enable) begin
      if (dist_sq >= radius_sq) begin
        brightness_gain_temp <= 0;
        diff <= 0;
      end else begin
        diff <= radius_sq - dist_sq;
        brightness_gain_temp <= (diff * env_brightness_gain) / radius_sq;
      end
    end
  end

  // ============================================================
  // Output pixel and handshake logic
  // ============================================================
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pix_out         <= 0;
      brightness_gain <= 0;
      valid_out       <= 0;
    end else begin
      if (valid_in && output_ready) begin
        brightness_gain <= brightness_gain_temp;

        if (filter_enable && brightness_gain_temp != 0)
          pix_out <= (pix_in + brightness_gain_temp) >> 1; // brightened pixel
        else
          pix_out <= pix_in; // transparent passthrough

        valid_out <= 1'b1;
      end else begin
        valid_out <= 1'b0;
      end
    end
  end

  // ============================================================
  // ADSR Envelope Generator
  // ============================================================
  typedef enum logic [2:0] {S_IDLE, S_ATTACK, S_DECAY, S_SUSTAIN, S_RELEASE} adsr_state_t;
  adsr_state_t state, next_state;

  logic [15:0] adsr_counter;
  logic [15:0] env_gain;
  logic [BITS-1:0] decay_target;

  // Tick generator: every 4 ms (200 000 @ 50 MHz)
  localparam int TICK_DIV = 200_000;
  logic [17:0] tick_cnt;
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

  // Next-state logic
  always_comb begin
    next_state = state;
    case (state)
      S_IDLE:    if (valid_in && filter_enable) next_state = S_ATTACK;
      S_ATTACK:  if (adsr_counter == ATTACK)    next_state = S_DECAY;
      S_DECAY:   if (adsr_counter == DECAY)     next_state = S_SUSTAIN;
      S_SUSTAIN: if (adsr_counter == SUSTAIN)   next_state = S_RELEASE;
      S_RELEASE: if (adsr_counter == RELEASE)   next_state = S_IDLE;
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
          adsr_counter <= adsr_counter + 1;
          env_gain <= (adsr_counter * 8'd255) / ATTACK;
          if (adsr_counter == ATTACK) begin
            adsr_counter <= 0;
            decay_target <= env_gain - DECAY;
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

endmodule
