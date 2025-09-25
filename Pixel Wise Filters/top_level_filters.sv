`timescale 1ns/1ps

// Simple top-level wrapper that instantiates pixel_wise_filter
// You can add more filters here if needed.

module top_level_filters (
    input  logic        clk,
    input  logic        reset,
    input  logic [7:0]  pix_in,
    input  logic        valid_in,
    output logic        module_ready,
    input  logic        filter_enable,
    input  logic        filter_mode,
    input  logic [7:0]  BPM_estimate,
    output logic [7:0]  pix_out,
    output logic        valid_out,
    input  logic        output_ready,
    output logic [7:0]  brightness
);

  logic [23:0] brightness_mult;

  pixel_wise_filter #(
    .BITS(8),
    .MAX_BPM(200)
  ) u_pixel_filter (
    .clk(clk),
    .reset(reset),
    .pix_in(pix_in),
    .valid_in(valid_in),
    .module_ready(module_ready),
    .filter_enable(filter_enable),
    .filter_mode(filter_mode),
    .BPM_estimate(BPM_estimate),
    .pix_out(pix_out),
    .output_ready(output_ready),
    .valid_out(valid_out),
    .brightness(brightness),
    .brightness_mult(brightness_mult)
  );

endmodule
