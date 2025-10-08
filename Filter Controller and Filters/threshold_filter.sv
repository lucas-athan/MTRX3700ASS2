`timescale 1ns/1ps
// ============================================================
// Threshold Filter
// Zeroes pixels below a brightness threshold.
// Behaves transparently when disabled.
//
// Handshake rules (Avalon-ST style):
//   • Input  : pixel_in,  pixel_in_valid,  module_ready  (downstream ready)
//   • Output : pixel_out, pixel_out_valid, output_ready  (this stage ready)
// ============================================================

module threshold_filter #(
    parameter int BITS    = 8,
    parameter int MAX_BPM = 200
)(
    input  logic                            clk,
    input  logic                            reset,
    input  logic [BITS-1:0]                 pixel_in,
    input  logic                            pixel_in_valid,
    input  logic [$clog2(MAX_BPM+1)-1:0]    BPM_estimate,

    output logic [BITS-1:0]                 pixel_out,
    output logic                            pixel_out_valid
);

    logic [BITS-1:0] brightness;

    always_comb begin
        brightness = (BPM_estimate * 8'd255) / MAX_BPM;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pixel_out       <= '0;
            pixel_out_valid <= 1'b0;
        end
        else begin
            if (pixel_in_valid) begin
                pixel_out <= (pixel_in <= brightness) ? '0 : pixel_in;
                pixel_out_valid <= 1'b1;
            end 
            else begin
                pixel_out_valid <= 1'b0;
            end
        end
    end
endmodule
