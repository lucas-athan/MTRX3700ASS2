  `timescale 1ns/1ps

  module tb_adsr_filter;

    // Parameters
    localparam CLK_PERIOD = 20; // 50 MHz
    localparam N_PIX = 8;
    localparam BITS = 8;

    // DUT I/O
    logic clk, reset;
    logic valid_in, output_ready;
    logic filter_enable, filter_mode;
    logic [BITS-1:0] pix_in [N_PIX];
    logic [$clog2(640)-1:0] pixel_x [N_PIX];
    logic [$clog2(480)-1:0] pixel_y;
    logic [$clog2(200+1)-1:0] BPM_estimate;
    logic [BITS-1:0] pulse_amplitude;

    logic [BITS-1:0] pix_out [N_PIX];
    logic module_ready, valid_out;

    logic [BITS-1:0] bpm_brightness_gain;
    logic [BITS-1:0] env_brightness_gain;
    logic [23:0]     bpm_brightness_mult;
    logic [BITS-1:0] brightness_gain [N_PIX];

    // Instantiate DUT
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

    // --- Helper Task: print internal ADSR state ---
    task print_debug;
      $display("[T=%0t ns] STATE=%0d | env_gain=%0d | adsr_counter=%0d | bpm_brightness_gain=%0d | env_brightness_gain=%0d | bpm_mult=%0d",
              $time, dut.state, dut.env_gain, dut.adsr_counter,
              bpm_brightness_gain, env_brightness_gain, bpm_brightness_mult);
    endtask


    int tick_count;
    // --- Stimulus ---
    initial begin
      $display("=== Starting ADSR Filter Full Test ===");

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

      // Pixel setup
      for (int i = 0; i < N_PIX; i++) begin
        pixel_x[i] = 300 + i;
        pix_in[i] = i * 30;  // distinct brightness levels
      end

      #100 reset = 0;
      repeat (10) @(posedge clk);
      print_debug();

      // Enable filter
      $display("\n--- Enable Filter (Enter Attack) ---");
      filter_enable = 1;
      valid_in = 1;
      repeat (1000) @(posedge clk);
      print_debug();

      // Let ADSR fully run
      $display("\n--- Run ADSR Envelope ---");
      repeat (50000) begin
        @(posedge clk);
        if (dut.tick_4ms) print_debug();
      end

    // --- PIXEL OUTPUT TEST ---
    $display("\n--- PIXEL OUTPUT TEST (Running for 50 ms with 4ms updates) ---");

    // Hold valid signals during the pixel test
    valid_in      = 1;
    output_ready  = 1;
    filter_enable = 1;

    tick_count = 0;

// Run for 50 ms (50 MHz = 2.5 million cycles)
repeat (3_000_000) begin
  @(posedge clk);
  #1; // allow DUT combinational outputs to settle before reading
  if (dut.tick_4ms) begin
    tick_count++;
    $display("\n[T=%0t ns] 4ms tick #%0d | state=%0d | env_gain=%0d | bpm_gain=%0d | pulse_amp=%0d",
             $time, tick_count, dut.state, dut.env_gain, bpm_brightness_gain, pulse_amplitude);

    // --- Print pix_out array ---
    $write("pix_out[]              : ");
    for (int i = 0; i < N_PIX; i++) begin
      $write("%0d ", pix_out[i]);
    end
    $display("");

    // --- Print temp_pix_out array (internal DUT output buffer) ---
    $write("temp_pix_out[]         : ");
    for (int i = 0; i < N_PIX; i++) begin
      $write("%0d ", dut.temp_pix_out[i]);
    end
    $display("");

    // --- Print brightness_gain array ---
    $write("brightness_gain[]      : ");
    for (int i = 0; i < N_PIX; i++) begin
      $write("%0d ", brightness_gain[i]);
    end
    $display("");

    // --- Print brightness_gain_temp array ---
    $write("brightness_gain_temp[] : ");
    for (int i = 0; i < N_PIX; i++) begin
      $write("%0d ", dut.brightness_gain_temp[i]);
    end
    $display("");

    // --- Print diff array ---
    $write("diff[]                 : ");
    for (int i = 0; i < N_PIX; i++) begin
      $write("%0d ", dut.diff[i]);
    end
    $display("");
  end
end



    $display("\n--- PIXEL OUTPUT SUMMARY AFTER 50 ms ---");

    // Context summary (all relevant control and state signals)
    $display("valid_in=%0b | valid_out=%0b | output_ready=%0b | module_ready=%0b | filter_enable=%0b | BPM_estimate=%0d | pulse_amplitude=%0d",
              valid_in, valid_out, output_ready, module_ready, filter_enable, BPM_estimate, pulse_amplitude);

    // Pixel coordinates
    $write("pixel_x[]              : ");
    for (int i = 0; i < N_PIX; i++)
      $write("%0d ", pixel_x[i]);
    $display("");
    $display("pixel_y                : %0d", pixel_y);

    // Input pixels
    $write("pix_in[]               : ");
    for (int i = 0; i < N_PIX; i++)
      $write("%0d ", pix_in[i]);
    $display("");

    // Distance squared and radius
    $write("dist_sq[]              : ");
    for (int i = 0; i < N_PIX; i++)
      $write("%0d ", dut.dist_sq[i]);
    $display("");
    $display("radius_sq              : %0d", dut.radius_sq);

      // --- BPM CHANGE TEST ---
      $display("\n--- BPM CHANGE TEST ---");
      BPM_estimate = 180;
      repeat (8000) @(posedge clk);
      print_debug();

      // --- AMPLITUDE CHANGE TEST ---
      $display("\n--- AMPLITUDE CHANGE TEST ---");
      pulse_amplitude = 255;
      repeat (8000) @(posedge clk);
      print_debug();

      // --- RESET TEST ---
      $display("\n--- RESET TEST ---");
      reset = 1; #50; reset = 0;
      repeat (2000) @(posedge clk);
      print_debug();

      $display("\n=== Test Complete ===");
      $finish;
    end

    // --- VCD Dump ---
    initial begin
      $dumpfile("adsr_filter_tb.vcd");
      $dumpvars(0, tb_adsr_filter);
    end

  endmodule
