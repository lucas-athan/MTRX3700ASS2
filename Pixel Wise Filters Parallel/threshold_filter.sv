`timescale 1ns/1ps

// Threshold filter module
// Zeroes pixels below brightness threshold.

module threshold_filter 
#(
    parameter int BITS         = 8,   // pixel bit depth
    parameter int MAX_BPM      = 200,
    parameter int STEP_SIZE    = (256 * (1<<8)) / 200
)
(
    input  logic                  clk,
    input  logic                  reset,

    input  logic [BITS-1:0]       pix_in,       
    input  logic                  valid_in,
    output logic                  module_ready,

    input  logic                  filter_enable,
    input  logic [$clog2(MAX_BPM+1)-1:0] BPM_estimate, 

    output logic [BITS-1:0]       pix_out,
    input  logic                  output_ready,
    output logic                  valid_out,
    output logic [BITS-1:0]       brightness,
    output logic [23:0]           brightness_mult
);

assign module_ready = output_ready;

// Scale brightness based on BPM
assign brightness_mult = (STEP_SIZE * BPM_estimate) >> 8;
assign brightness      = (brightness_mult > 255) ? 8'd255 : brightness_mult[7:0];

always_comb begin
    if (module_ready && valid_in && filter_enable) begin
        // threshold
        if (pix_in <= brightness)
            pix_out = 0;
        else
            pix_out = pix_in;
    end else begin
        pix_out = 0;
    end
end

assign valid_out = module_ready && valid_in && filter_enable;

endmodule
