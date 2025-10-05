`timescale 1ns/1ps

// Pixel-wise filter module
// Each pixel is processed independently, based only on its value and external params.

module pixel_wise_filter 
#(
    parameter int NUM_STATES   = 4,
    parameter int BITS         = 8,   // pixel bit depth
    parameter int DEPTHVAL     = 256, // 2^BITS
    parameter int STEP_SIZE    = (256 * (1<<8)) / 200, // scale so BPM=200 gives brightness ≈ 255
    parameter int NUM_FILTERS  = 2,
    parameter int MIN_BPM      = 40,
    parameter int MAX_BPM      = 200
)
(
    input  logic                  clk,
    input  logic                  reset,

    input  logic [BITS-1:0]       pix_in,       
    input  logic                  valid_in,
    output logic                  module_ready,

    input  logic                  filter_enable,
    input  logic                  filter_mode,  // 0 = threshold, 1 = additive
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
	pix_out              = '0;
   pix_bright_addition  = '0;


    if (module_ready && valid_in && filter_enable) begin
        if (filter_mode) begin
            // additive / averaging
            pix_bright_addition = (pix_in + brightness) >> 1;
            pix_out = pix_bright_addition;
        end else begin
            // threshold
            if (pix_in <= brightness)
                pix_out = 0;
            else
                pix_out = pix_in;
        end
    end else begin
        pix_out = pix_in;
    end
end

assign valid_out = module_ready && valid_in;

endmodule
