`timescale 1ns/1ps

// Top-level wrapper that instantiates brightness_filter and threshold_filter
// Both filters run in parallel. Outputs and ready signals are exposed separately.

module top_level_filters (
    input  logic        clk,
    input  logic        reset,
    input  logic [7:0]  pix_in,
    input  logic        valid_in,
    input  logic        filter_enable,
    input  logic [7:0]  BPM_estimate,
    input  logic        output_ready,

    // Outputs from threshold filter
    output logic [7:0]  pix_out_thresh,
    output logic        valid_out_thresh,
    output logic [7:0]  brightness_thresh,
    output logic        module_ready_thresh,

    // Outputs from brightness filter
    output logic [7:0]  pix_out_bright,
    output logic        valid_out_bright,
    output logic [7:0]  brightness_bright,
    output logic        module_ready_bright
);

  logic [23:0] brightness_mult_thresh;
  logic [23:0] brightness_mult_bright;

  // --- Threshold filter instance ---
  threshold_filter #(
    .BITS(8),
    .MAX_BPM(200)
  ) u_threshold_filter (
    .clk(clk),
    .reset(reset),
    .pix_in(pix_in),
    .valid_in(valid_in),
    .module_ready(module_ready_thresh),
    .filter_enable(filter_enable),
    .BPM_estimate(BPM_estimate),
    .pix_out(pix_out_thresh),
    .output_ready(output_ready),
    .valid_out(valid_out_thresh),
    .brightness(brightness_thresh),
    .brightness_mult(brightness_mult_thresh)
  );

  // --- Brightness filter instance ---
  brightness_filter #(
    .BITS(8),
    .MAX_BPM(200)
  ) u_brightness_filter (
    .clk(clk),
    .reset(reset),
    .pix_in(pix_in),
    .valid_in(valid_in),
    .module_ready(module_ready_bright),
    .filter_enable(filter_enable),
    .BPM_estimate(BPM_estimate),
    .pix_out(pix_out_bright),
    .output_ready(output_ready),
    .valid_out(valid_out_bright),
    .brightness(brightness_bright),
    .brightness_mult(brightness_mult_bright)
  );

endmodule
