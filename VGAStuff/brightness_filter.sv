`timescale 1ns/1ps

// Brightness filter module
// Adds scaled brightness to pixel and averages.

module brightness_filter 
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

logic [BITS:0] pix_bright_addition;

// Scale brightness based on BPM
assign brightness_mult = (STEP_SIZE * BPM_estimate) >> 8;
assign brightness      = (brightness_mult > 255) ? 8'd255 : brightness_mult[7:0];

always_comb begin
    // ✅ Default assignments
    pix_bright_addition = '0;
    pix_out             = pix_in;

    if (module_ready && valid_in && filter_enable) begin
        // additive / averaging
        pix_bright_addition = (pix_in + brightness) >> 1;
        pix_out = pix_bright_addition;
    end
end

assign valid_out = module_ready && valid_in && filter_enable;

endmodule
