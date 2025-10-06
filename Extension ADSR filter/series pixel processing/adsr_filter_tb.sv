`timescale 1ns/1ps

module tb_adsr_filter;

  // Parameters
  localparam CLK_PERIOD = 20; // 50 MHz
  localparam BITS = 8;

  // DUT I/O
  logic clk, reset;
  logic valid_in, output_ready;
  logic filter_enable, filter_mode;

  logic [BITS-1:0] pix_in;
  logic [$clog2(640)-1:0] pixel_x;
  logic [$clog2(480)-1:0] pixel_y;
  logic [$clog2(200+1)-1:0] BPM_estimate;
  logic [BITS-1:0] pulse_amplitude;

  logic [BITS-1:0] pix_out;
  logic module_ready, valid_out;

  logic [BITS-1:0] bpm_brightness_gain;
  logic [BITS-1:0] env_brightness_gain;
  logic [23:0]     bpm_brightness_mult;
  logic [BITS-1:0] brightness_gain;

  // Instantiate DUT (serial version)
  adsr_filter dut (
    .clk(clk),
    .reset(reset),
    .pix_in(pix_in),
    .valid_in(valid_in),
    .output_ready(output_ready),
    .module_ready(module_ready),
    .pix_out(pix_out),
    .valid_out(valid_out),
    .pixel_x(pixel_x),
    .pixel_y(pixel_y),
    .filter_enable(filter_enable),
    .filter_mode(filter_mode),
    .BPM_estimate(BPM_estimate),
    .pulse_amplitude(pulse_amplitude),
    .bpm_brightness_gain(bpm_brightness_gain),
    .env_brightness_gain(env_brightness_gain),
    .bpm_brightness_mult(bpm_brightness_mult),
    .brightness_gain(brightness_gain)
  );

  // Clock generation
  always #(CLK_PERIOD/2) clk = ~clk;

  // --- Helper Task: Print full debug info on 4ms tick ---
  task print_debug;
    $display("\n[T=%0t ns] 4ms tick #%0d", $time, tick_count);
    $display("  STATE             : %0d", dut.state);
    $display("  ADSR env_gain     : %0d", dut.env_gain);
    $display("  ADSR counter      : %0d", dut.adsr_counter);
    $display("  BPM estimate      : %0d", BPM_estimate);
    $display("  Pulse amplitude   : %0d", pulse_amplitude);
    $display("  bpm_brightness_gain: %0d", bpm_brightness_gain);
    $display("  env_brightness_gain: %0d", env_brightness_gain);
    $display("  bpm_brightness_mult: %0d", bpm_brightness_mult);
    $display("  pixel_x           : %0d", pixel_x);
    $display("  pixel_y           : %0d", pixel_y);
    $display("  pix_in            : %0d", pix_in);
    $display("  pix_out           : %0d", pix_out);
    $display("  brightness_gain   : %0d", brightness_gain);
    $display("  brightness_gain_temp: %0d", dut.brightness_gain_temp);
    $display("  diff              : %0d", dut.diff);
    $display("  temp_pix_out      : %0d", dut.temp_pix_out);
  endtask

  int tick_count;
  int pixel_counter;
  int max_pixels;
  int max_cycles;

  // --- Stimulus ---
  initial begin
    $display("=== Starting ADSR Filter Serial Test ===");

    // Initial conditions
    clk = 0;
    reset = 1;
    valid_in = 0;
    output_ready = 1;
    filter_enable = 0;
    filter_mode = 0;
    BPM_estimate = 100;
    pulse_amplitude = 128;
    pixel_y = 240;
    pix_in = 0;
    pixel_x = 320;

    #100 reset = 0;
    repeat (10) @(posedge clk);

    // --- Enable filter and send pixels ---
    $display("\n--- Enable Filter and Start Envelope ---");
    filter_enable = 1;
    valid_in = 1;

    // Send pixels one by one
    for (int i = 0; i < 3000; i++) begin
      pixel_x = 250 + (i % 50);         // sweep around center
      pix_in = (i * 7) % 256;           // vary brightness
      @(posedge clk);
      #1;
      if (dut.tick_4ms) begin
        tick_count++;
        print_debug();
      end
    end

// --- PIXEL OUTPUT TEST --- //
$display("\n--- PIXEL OUTPUT TEST (Serial, 60 ms, 4ms intervals) ---");

valid_in      = 1;
output_ready  = 1;
filter_enable = 1;

tick_count = 0;
pixel_counter = 0;
max_cycles = 3_000_000; // 60 ms at 50 MHz

repeat (max_cycles) begin
  @(posedge clk);

  // Stimulate 1 pixel per cycle
  pixel_x = 320 ;   // sweep horizontally
  pix_in  = 127;     // synthetic brightness values
  pixel_counter++;

  if (dut.tick_4ms) begin
    tick_count++;

    $display("[T=%0t ns] Tick=%0d | State=%0d | env_gain=%0d | bpm_gain=%0d | env_bpm_gain=%0d | pixel_x=%0d | pix_in=%0d | pix_out=%0d | gain=%0d",
             $time,
             tick_count,
             dut.state,
             dut.env_gain,
             bpm_brightness_gain,
             env_brightness_gain,
             pixel_x,
             pix_in,
             pix_out,
             brightness_gain
    );
  end
end



    // --- BPM CHANGE TEST ---
    $display("\n--- BPM CHANGE TEST ---");
    BPM_estimate = 180;
    repeat (1000) begin
      @(posedge clk);
      if (dut.tick_4ms) begin
        tick_count++;
        print_debug();
      end
    end

    // --- AMPLITUDE CHANGE TEST ---
    $display("\n--- AMPLITUDE CHANGE TEST ---");
    pulse_amplitude = 255;
    repeat (1000) begin
      @(posedge clk);
      if (dut.tick_4ms) begin
        tick_count++;
        print_debug();
      end
    end

    // --- RESET TEST ---
    $display("\n--- RESET TEST ---");
    reset = 1;
    #50;
    reset = 0;
    repeat (1000) begin
      @(posedge clk);
      if (dut.tick_4ms) begin
        tick_count++;
        print_debug();
      end
    end

    $display("\n=== Test Complete ===");
    $finish;
  end

  // --- VCD Dump ---
  initial begin
    $dumpfile("adsr_filter_tb.vcd");
    $dumpvars(0, tb_adsr_filter);
  end

endmodule
