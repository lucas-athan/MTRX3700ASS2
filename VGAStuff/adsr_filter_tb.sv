`timescale 1ns/1ps

module tb_adsr_filter;

  // ============================================================
  // Parameters
  // ============================================================
  localparam CLK_PERIOD = 20; // 50 MHz
  localparam BITS       = 8;
  localparam IMG_W      = 640;
  localparam IMG_H      = 480;

  // ============================================================
  // DUT I/O
  // ============================================================
  logic clk, reset;
  logic valid_in, output_ready;
  logic filter_enable;
  logic [$clog2(200+1)-1:0] BPM_estimate;
  logic [BITS-1:0] pulse_amplitude;
  logic [BITS-1:0] pix_in;
  logic [BITS-1:0] pix_out;
  logic module_ready, valid_out;
  logic [BITS-1:0] bpm_brightness_gain;
  logic [BITS-1:0] env_brightness_gain;
  logic [23:0]     bpm_brightness_mult;
  logic [BITS-1:0] brightness_gain;

  // ============================================================
  // DUT Instantiation
  // ============================================================
  adsr_filter dut (
    .clk(clk),
    .reset(reset),
    .pix_in(pix_in),
    .valid_in(valid_in),
    .output_ready(output_ready),
    .module_ready(module_ready),
    .pix_out(pix_out),
    .valid_out(valid_out),
    .filter_enable(filter_enable),
    .BPM_estimate(BPM_estimate),
    .pulse_amplitude(pulse_amplitude),
    .bpm_brightness_gain(bpm_brightness_gain),
    .env_brightness_gain(env_brightness_gain),
    .bpm_brightness_mult(bpm_brightness_mult),
    .brightness_gain(brightness_gain)
  );

  // ============================================================
  // Clock generation
  // ============================================================
  always #(CLK_PERIOD/2) clk = ~clk;

  // ============================================================
  // ADSR States
  // ============================================================
  localparam S_IDLE    = 3'd0;
  localparam S_ATTACK  = 3'd1;
  localparam S_DECAY   = 3'd2;
  localparam S_SUSTAIN = 3'd3;
  localparam S_RELEASE = 3'd4;

  // ============================================================
  // Integer variables
  // ============================================================
  integer i, frame, pixel_samples, max_cycles, tick_count, cycle;
  integer pgm_file, x, y;

  // ============================================================
  // Debug Task (Original Multi-line Layout)
  // ============================================================
  task print_state_debug(input logic [2:0] s);
    $display("\n[DEBUG] ADSR State %0d", s);
    $display("  state                : %0d", dut.state);
    $display("  adsr_counter         : %0d", dut.adsr_counter);
    $display("  env_gain             : %0d", dut.env_gain);
    $display("  bpm_brightness_mult  : %0d", dut.bpm_brightness_mult);
    $display("  bpm_brightness_gain  : %0d", dut.bpm_brightness_gain);
    $display("  env_brightness_gain  : %0d", dut.env_brightness_gain);
    $display("  brightness_gain_temp : %0d", dut.brightness_gain_temp);
    $display("  brightness_gain      : %0d", dut.brightness_gain);
    $display("  pix_in               : %0d", pix_in);
    $display("  pix_out              : %0d", pix_out);
    $display("  pixel_x              : %0d", dut.pixel_x);
    $display("  pixel_y              : %0d", dut.pixel_y);
    $display("  dist_sq              : %0d", dut.dist_sq);
    $display("  diff                 : %0d", dut.diff);
    $display("  radius_sq            : %0d", dut.radius_sq);
    $display("  cx                   : %0d", dut.cx);
    $display("  cy                   : %0d", dut.cy);
  endtask

  // ============================================================
  // PGM Writer Task (one file per ADSR state)
  // ============================================================
  task write_adsr_image_pgm(input string filename);
    pgm_file = $fopen(filename, "w");
    $fdisplay(pgm_file, "P2");
    $fdisplay(pgm_file, "# Image for %s", filename);
    $fdisplay(pgm_file, "%0d %0d", IMG_W, IMG_H);
    $fdisplay(pgm_file, "255");

    for (y = 0; y < IMG_H; y = y + 1) begin
      for (x = 0; x < IMG_W; x = x + 1) begin
        pix_in    = 100;
        valid_in  = 1;
        output_ready = 1;
        @(posedge clk);
        #1;
        $fwrite(pgm_file, "%0d ", pix_out);
      end
      $fwrite(pgm_file, "\n");
    end

    $fclose(pgm_file);
    $display("[PGM] Wrote %s", filename);
  endtask

  // ============================================================
  // Main Stimulus
  // ============================================================
  initial begin
    $display("=== Starting ADSR Filter Testbench ===");

    clk = 0;
    reset = 1;
    valid_in = 0;
    output_ready = 1;
    filter_enable = 0;
    BPM_estimate = 120;
    pulse_amplitude = 128;
    pix_in = 0;

    #100 reset = 0;
    repeat (10) @(posedge clk);

    // ------------------------------------------------------------
    // Test 1 – Pass-through
    // ------------------------------------------------------------
    $display("\n=== TEST 1: Pass-through (filter_enable=0) ===");
    for (i = 0; i < 50; i = i + 1) begin
      pix_in = i;
      valid_in = 1;
      @(posedge clk);
      $display("pix_in=%0d  pix_out=%0d  valid_out=%0b", pix_in, pix_out, valid_out);
    end
    valid_in = 0;
    #100;

    // ------------------------------------------------------------
    // Test 2 – Pixel X/Y Counter Verification
    // ------------------------------------------------------------
    $display("\n=== TEST 2: Pixel X/Y Counter Verification ===");
    reset = 1; @(posedge clk); reset = 0;
    filter_enable = 0;
    valid_in = 1;
    output_ready = 1;
    pix_in = 42;
    pixel_samples = 0;

    for (frame = 0; frame < (IMG_H * IMG_W); frame = frame + 1) begin
      @(posedge clk);
      if (frame % ((IMG_W*IMG_H)/6) == 0 && pixel_samples < 6) begin
        $display("[PIXEL SAMPLE %0d] pixel_x=%0d  pixel_y=%0d  pix_out=%0d",
                 pixel_samples, dut.pixel_x, dut.pixel_y, pix_out);
        pixel_samples = pixel_samples + 1;
      end
    end
    valid_in = 0;
    #100;

    // ------------------------------------------------------------
    // Test 3 – Pixel Output (60 ms, 4 ms ticks, center pixel)
    // ------------------------------------------------------------
    $display("\n=== TEST 3: Pixel Output Test (60 ms, 4 ms ticks, center pixel) ===");
    reset = 1; @(posedge clk); reset = 0;
    filter_enable = 1;
    valid_in = 1;
    output_ready = 1;
    pix_in = 100; // constant pixel value
    tick_count = 0;
    max_cycles = 3_000_000; // 60 ms @ 50 MHz

    // Center pixel
    dut.pixel_x = 320;
    dut.pixel_y = 240;

    for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
      @(posedge clk);
      if (dut.tick_4ms) begin
        tick_count = tick_count + 1;
        print_state_debug(dut.state);

        case (dut.state)
          S_ATTACK:  write_adsr_image_pgm("adsr_attack.pgm");
          S_DECAY:   write_adsr_image_pgm("adsr_decay.pgm");
          S_SUSTAIN: write_adsr_image_pgm("adsr_sustain.pgm");
          S_RELEASE: write_adsr_image_pgm("adsr_release.pgm");
          default: ;
        endcase
      end
    end

    valid_in = 0;
    filter_enable = 0;

    $display("\n=== Simulation Complete ===");
    $finish;
  end

  // ============================================================
  // VCD Dump
  // ============================================================
  initial begin
    $dumpfile("adsr_filter_tb.vcd");
    $dumpvars(0, tb_adsr_filter);
  end

endmodule
