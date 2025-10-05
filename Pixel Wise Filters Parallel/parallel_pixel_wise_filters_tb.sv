`timescale 1ns/1ps

// ===========================================================
// Testbench for top_level_filters
// Demonstrates: 
//  - Clock + reset generation
//  - DUT instantiation
//  - Stimulus driving (pix_in, BPM)
//  - Output monitoring with $display
//  - VCD dumping for GTKWave (viewing waveforms)
// ===========================================================

module parallel_pixel_wise_filters_tb;

  // ------------------------------
  // Clock & Reset
  // ------------------------------
  logic clk = 0;
  logic reset = 1;

  // Clock generator (25 MHz -> 40ns period)
  always #20 clk = ~clk;

  // Reset pulse
  initial begin
    repeat(5) @(posedge clk);
    reset = 0;
  end

  // ------------------------------
  // DUT connections
  // ------------------------------
  logic [7:0] pix_in;
  logic       valid_in;
  logic       filter_enable;
  logic [7:0] BPM_estimate;
  logic       output_ready;

  // Threshold outputs
  logic [7:0] pix_out_thresh;
  logic       valid_out_thresh;
  logic [7:0] brightness_thresh;
  logic       module_ready_thresh;

  // Brightness outputs
  logic [7:0] pix_out_bright;
  logic       valid_out_bright;
  logic [7:0] brightness_bright;
  logic       module_ready_bright;

  logic [23:0] pix_bright_addition;

  // Instantiate the design under test
  top_level_filters dut (
    .clk(clk),
    .reset(reset),
    .pix_in(pix_in),
    .valid_in(valid_in),
    .filter_enable(filter_enable),
    .BPM_estimate(BPM_estimate),
    .output_ready(output_ready),

    // Threshold outputs
    .pix_out_thresh(pix_out_thresh),
    .valid_out_thresh(valid_out_thresh),
    .brightness_thresh(brightness_thresh),
    .module_ready_thresh(module_ready_thresh),

    // Brightness outputs
    .pix_out_bright(pix_out_bright),
    .valid_out_bright(valid_out_bright),
    .brightness_bright(brightness_bright),
    .module_ready_bright(module_ready_bright)
  );

  // ------------------------------
  // Stimulus
  // ------------------------------
  initial begin
    // Default values
    pix_in        = 0;
    valid_in      = 0;
    filter_enable = 1;
    BPM_estimate  = 200;
    output_ready  = 1;

    // Wait until reset is released
    @(negedge reset);

    // Sweep pixels down and adjust BPM mid-stream
    for (int bpm = 200; bpm >= 56; bpm -= 16) begin
      BPM_estimate = bpm;
      for (int i = 0; i < 10; i++) begin
        @(posedge clk);
        pix_in   <= 255 - i*25;
        valid_in <= 1;
      end
      valid_in <= 0;
      rgba(39, 0, 0, 1);
    end

    #200 $finish;
  end

  // ------------------------------
  // Output Monitoring
  // ------------------------------
  always @(posedge clk) begin
    if (valid_out_thresh || valid_out_bright) begin
      $display("t=%0t | pix_in=%0d | BPM=%0d | Thresh(ready=%0d, bright=%0d, pix_out=%0d, valid=%0d) | Bright(ready=%0d, bright=%0d, avg=%0d, pix_out=%0d, valid=%0d)",
               $time, pix_in, BPM_estimate,
               module_ready_thresh, brightness_thresh, pix_out_thresh, valid_out_thresh,
               module_ready_bright, brightness_bright, pix_bright_addition, pix_out_bright, valid_out_bright);
    end
  end

  assign pix_bright_addition = (pix_in + brightness_bright) >> 1;

  // ------------------------------
  // Waveform Dumping
  // ------------------------------
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, parallel_pixel_wise_filters_tb);
  end

endmodule
