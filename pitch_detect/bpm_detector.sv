`timescale 1ns/1ns
module bpm_detector #(
    parameter SNR_WIDTH = 16,
    parameter CLK_FREQ  = 50_000_000, // Hz
    parameter AUDIO_RATE = 30720,     // Hz, for envelope scaling
    parameter ALPHA = 16'd3277       // smoothing factor (Q15 ≈ 0.1)
) (
    input  logic                  clk,
    input  logic                  reset,
    input  logic [SNR_WIDTH-1:0]  snr_db,     // 0-84
    input  logic                  snr_valid,
    output logic                  onset_detected
);

    // Envelope filter (low-pass)
    logic [SNR_WIDTH-1:0] envelope;
    logic [SNR_WIDTH-1:0] prev_envelope;
    logic signed [SNR_WIDTH:0] delta; // allow negative

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            envelope <= 0;
            prev_envelope <= 0;
        end else if (snr_valid) begin
            // Simple exponential moving average: envelope[n] = alpha*snr + (1-alpha)*envelope[n-1]
            envelope <= ((ALPHA * snr_db) + ((16'd32768 - ALPHA) * envelope)) >>> 15;
            prev_envelope <= envelope;
        end
    end

    // Derivative
    always_comb delta = envelope - prev_envelope;

    // Threshold & refractory
    localparam MIN_ONSET_CYCLES = CLK_FREQ / 10; // 100ms at 50 MHz
    logic [31:0] onset_timer;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            onset_detected <= 0;
            onset_timer <= 0;
        end else if (snr_valid) begin
            onset_detected <= 0; // default
            if (onset_timer > 0)
                onset_timer <= onset_timer - 1;

            // Compare derivative against threshold
            if ((delta > 2) && (onset_timer == 0)) begin
                onset_detected <= 1'b1;
                onset_timer <= MIN_ONSET_CYCLES;
            end
        end
    end

endmodule
