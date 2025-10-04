module adsr_filter #(
    parameter int attack = 256,
    parameter int decay = 256,
    parameter int sustain = 256,
    parameter int release = 256,
    parameter int MIN_BPM      = 40,
    parameter int MAX_BPM      = 200,
    parameter int BITS    = 8
) (
    input logic                   clk,
    input logic                   reset,

    input logic [BITS-1:0]        pix_in,
    input logic                   valid_in,
    output logic                  module_ready,

    input logic                   filter_enable  ,   
    input logic [$clog2(MAX_BPM+1)-1:0] BPM_estimate, 
    input logic [BITS-1:0]        pulse_amplitude,

    output logic [BITS-1:0]       pix_out,
    input logic                   output_ready,
    output logic                  valid_out,
    
    input logic                   filter_enable,
    input logic                   filter_mode,
);

assign module_ready = output_ready;

logic filter_pixel_radius;
assign filter_pixel_radius = pulse_amplitude >> 1;




