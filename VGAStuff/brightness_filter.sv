`timescale 1ns/1ps
// ============================================================
// Brightness Filter
// Adds scaled brightness with saturation.
// Transparent when disabled.
// ============================================================

module brightness_filter #(
    parameter int BITS    = 8,
    parameter int MAX_BPM = 200
)(
    input  logic                  clk,
    input  logic                  reset,

    // Stream input
    input  logic [BITS-1:0]       pix_in,
    input  logic                  valid_in,

    // Handshake
    input  logic                  module_ready,   // downstream ready
    output logic                  output_ready,   // upstream ready

    // Control
    input  logic                  filter_enable,
    input  logic [$clog2(MAX_BPM+1)-1:0] BPM_estimate,

    // Stream output
    output logic [BITS-1:0]       pix_out,
    output logic                  valid_out,

    // Debug
    output logic [BITS-1:0]       brightness
);

    // ============================================================
    // Derived brightness value (scaled linearly with BPM)
    // ============================================================
    always_comb begin
        brightness = ((BPM_estimate * 8'd255) + (MAX_BPM/2)) / MAX_BPM;
    end

    // ============================================================
    // Sequential pixel pipeline
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pix_out      <= '0;
            valid_out    <= 1'b0;
            output_ready <= 1'b1;
        end else begin
            // propagate handshake readiness
            output_ready <= module_ready;

            if (valid_in && module_ready) begin
                if (filter_enable) begin
                    // Add brightness with saturation
                    logic [BITS:0] sum;
                    sum = pix_in + brightness;
                    if (sum > 8'd255)
                        pix_out <= 8'd255;
                    else
                        pix_out <= sum[7:0];
                end else begin
                    // Transparent when disabled
                    pix_out <= pix_in;
                end

                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule
