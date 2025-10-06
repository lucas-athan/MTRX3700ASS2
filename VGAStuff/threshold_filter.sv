`timescale 1ns/1ps
// ============================================================
// Threshold Filter
// Zeroes pixels below a brightness threshold.
// Behaves transparently when disabled.
//
// Handshake rules (Avalon-ST style):
//   • Input  : pix_in,  valid_in,  module_ready  (downstream ready)
//   • Output : pix_out, valid_out, output_ready  (this stage ready)
// ============================================================

module threshold_filter #(
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

    // Debug / observability
    output logic [BITS-1:0]       brightness
);

    // ============================================================
    // Derived brightness threshold (linear scaling)
    // ============================================================
    always_comb begin
        brightness = (BPM_estimate * 8'd255) / MAX_BPM;
    end

    // ============================================================
    // Sequential pipeline logic
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pix_out      <= '0;
            valid_out    <= 1'b0;
            output_ready <= 1'b1;   // ready immediately after reset
        end else begin
            output_ready <= module_ready; // propagate downstream readiness

            if (valid_in && module_ready) begin
                // Threshold active → apply filter; otherwise passthrough
                if (filter_enable)
                    pix_out <= (pix_in <= brightness) ? '0 : pix_in;
                else
                    pix_out <= pix_in;

                valid_out <= 1'b1; // always produce valid when data accepted
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule
