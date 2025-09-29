`timescale 1ns/1ps

// ===========================================================
// Testbench for top_level_filters
// Demonstrates: 
//  - Clock + reset generation
//  - DUT instantiation
//  - Stimulus driving (pix_in, BPM, modes)
//  - Output monitoring with $display
//  - VCD dumping for GTKWave (viewing waveforms)
// ===========================================================

module pixel_wise_filters_tb;

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
  logic       module_ready;
  logic       filter_enable;
  logic       filter_mode;
  logic [7:0] BPM_estimate;
  logic [7:0] pix_out;
  logic       valid_out;
  logic       output_ready;
  logic [7:0] brightness;
  logic [23:0] pix_bright_addition;

  // Instantiate the design under test
  top_level_filters dut (
    .clk(clk),
    .reset(reset),
    .pix_in(pix_in),
    .valid_in(valid_in),
    .module_ready(module_ready),
    .filter_enable(filter_enable),
    .filter_mode(filter_mode),
    .BPM_estimate(BPM_estimate),
    .pix_out(pix_out),
    .valid_out(valid_out),
    .output_ready(output_ready),
    .brightness(brightness)
  );

  // ------------------------------
  // Stimulus
  // ------------------------------
  initial begin
    // Default values
    pix_in        = 0;
    valid_in      = 0;
    filter_enable = 1;
    filter_mode   = 0;   // 0 = threshold, 1 = additive
    BPM_estimate  = 200;
    output_ready  = 1;

    // Wait until reset is released
    @(negedge reset);

    // Sweep pixels down and adjust BPM mid-stream
    for (int bpm = 200; bpm >= 56; bpm -= 16) begin
      BPM_estimate = bpm;
      for (int i = 0; i < 10; i++) begin
        @(posedge clk);
        pix_in   = 255 - i*25;
        valid_in = 1;
      end
      valid_in = 0;
      #200;
    end

    // Switch to average mode
    filter_mode = 1;
    BPM_estimate = 200;
    for (int bpm = 200; bpm >= 56; bpm -= 16) begin
      BPM_estimate = bpm;
      for (int i = 0; i < 10; i++) begin
        @(posedge clk);
        pix_in   = 255 - i*25;
        valid_in = 1;
      end
      valid_in = 0;
      #200;
    end

    #200 $finish;
  end

  // ------------------------------
  // Output Monitoring
  // ------------------------------
  always @(posedge clk) begin
    if (valid_out)
      $display("t=%0t | pix_in=%0d | BPM=%0d | brightness=%0d | brightness average=%0d | mode=%0d | pix_out=%0d",
               $time, pix_in, BPM_estimate, brightness, pix_bright_addition, filter_mode, pix_out);
  end

    assign pix_bright_addition = (pix_in + brightness) >> 1;
  // ------------------------------
  // Waveform Dumping
  // ------------------------------
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, pixel_wise_filters_tb);
  end

endmodule
