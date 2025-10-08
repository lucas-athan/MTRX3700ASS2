`timescale 1ns/1ps

module tb_adsr_filter;

  // Parameters
  localparam CLK_PERIOD = 20; // 50 MHz
  localparam BITS       = 8;
  localparam IMG_W      = 640;
  localparam IMG_H      = 480;

  // DUT I/O
  logic clk, reset;
  logic valid_in, output_ready;
  logic filter_enable, filter_mode;
  logic freeze;

  logic [BITS-1:0] pix_in;
  logic [$clog2(IMG_W)-1:0] pixel_x;
  logic [$clog2(IMG_H)-1:0] pixel_y;
  logic [$clog2(200+1)-1:0] BPM_estimate;
  logic [BITS-1:0] pulse_amplitude;

  logic [BITS-1:0] pix_out;
  logic module_ready, valid_out;

  logic [BITS-1:0] bpm_brightness_gain;
  logic [BITS-1:0] env_brightness_gain;
  logic [23:0]     bpm_brightness_mult;
  logic [BITS-1:0] brightness_gain;

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
    .filter_enable(filter_enable),
    .BPM_estimate(BPM_estimate),
    .pulse_amplitude(pulse_amplitude),
    .bpm_brightness_gain(bpm_brightness_gain),
    .env_brightness_gain(env_brightness_gain),
    .bpm_brightness_mult(bpm_brightness_mult),
    .brightness_gain(brightness_gain)
  );

  // Clock generation
  always #(CLK_PERIOD/2) clk = ~clk;

  // ADSR states
  localparam S_IDLE    = 3'd0;
  localparam S_ATTACK  = 3'd1;
  localparam S_DECAY   = 3'd2;
  localparam S_SUSTAIN = 3'd3;
  localparam S_RELEASE = 3'd4;

  logic [2:0] next_state;

  integer tick_count;
  integer max_cycles;
  integer pgm_file;

  // === Debug Print Task ===
  task print_state_debug(input logic [2:0] state_label);
    $display("\n[DEBUG] ADSR State %0d", state_label);
    $display("  state                : %0d", dut.state);
    $display("  adsr_counter         : %0d", dut.adsr_counter);
    $display("  env_gain             : %0d", dut.env_gain);
    $display("  bpm_brightness_mult  : %0d", dut.bpm_brightness_mult);
    $display("  bpm_brightness_gain  : %0d", dut.bpm_brightness_gain);
    $display("  env_brightness_gain  : %0d", dut.env_brightness_gain);
    $display("  brightness_gain_temp : %0d", dut.brightness_gain_temp);
    $display("  brightness_gain      : %0d", dut.brightness_gain);
    $display("  diff                 : %0d", dut.diff);
    $display("  cx                   : %0d", dut.cx);
    $display("  cy                   : %0d", dut.cy);
    $display("  radius               : %0d", dut.radius);
    $display("  radius_sq            : %0d", dut.radius_sq);
  endtask

  // === PGM Image Writer ===
  task write_adsr_image_pgm(input logic [2:0] state_label);
    string filename;
    int x, y;

    case (state_label)
      S_ATTACK:  filename = "adsr_attack.pgm";
      S_DECAY:   filename = "adsr_decay.pgm";
      S_SUSTAIN: filename = "adsr_sustain.pgm";
      S_RELEASE: filename = "adsr_release.pgm";
      default:   filename = "adsr_unknown.pgm";
    endcase

    $display("[PGM] Writing %s", filename);
    pgm_file = $fopen(filename, "w");

    $fdisplay(pgm_file, "P2");
    $fdisplay(pgm_file, "# ADSR image for state %0d", state_label);
    $fdisplay(pgm_file, "%0d %0d", IMG_W, IMG_H);
    $fdisplay(pgm_file, "255");

    for (y = 0; y < IMG_H; y++) begin
      for (x = 0; x < IMG_W; x++) begin
        pix_in  = 0;
        valid_in = 1;
        @(posedge clk);
        #1;
        $fwrite(pgm_file, "%0d ", pix_out);
      end
      $fwrite(pgm_file, "\n");
    end

    $fclose(pgm_file);
  endtask

  // === Predict Next State ===
  function logic [2:0] compute_next_state(
    input logic [2:0] state,
    input logic [15:0] counter,
    input logic valid_in,
    input logic filter_en
  );
    case (state)
      S_IDLE:    compute_next_state = (valid_in && filter_en) ? S_ATTACK : S_IDLE;
      S_ATTACK:  compute_next_state = (counter == 2) ? S_DECAY   : S_ATTACK;
      S_DECAY:   compute_next_state = (counter == 2) ? S_SUSTAIN : S_DECAY;
      S_SUSTAIN: compute_next_state = (counter == 2) ? S_RELEASE : S_SUSTAIN;
      S_RELEASE: compute_next_state = (counter == 2) ? S_IDLE    : S_RELEASE;
      default:   compute_next_state = S_IDLE;
    endcase
  endfunction

  // === Main Stimulus ===
  initial begin
    $display("=== Starting Full ADSR PGM Dump Test ===");

    // Initialize
    clk = 0;
    reset = 1;
    valid_in = 0;
    output_ready = 1;
    filter_enable = 0;
    BPM_estimate = 100;
    pulse_amplitude = 128;
    pix_in  = 0;

    #100 reset = 0;
    repeat (10) @(posedge clk);

    // Start ADSR
    filter_enable = 1;
    valid_in = 1;

    // Prime it with some activity
    for (int i = 0; i < 3000; i++) begin
      pix_in  = (i * 7) % 256;
      @(posedge clk);
    end

    tick_count = 0;
    max_cycles = 3_000_000;

    repeat (max_cycles) begin
      @(posedge clk);

      // Constant input stream
      pix_in  = 127;
      valid_in = 1;

      if (dut.tick_4ms) begin
        tick_count++;

        next_state = compute_next_state(
          dut.state,
          dut.adsr_counter,
          valid_in,
          filter_enable
        );

        if (next_state != dut.state) begin

          case (dut.state)
            S_ATTACK, S_DECAY, S_SUSTAIN, S_RELEASE: begin
              print_state_debug(dut.state);
              write_adsr_image_pgm(dut.state);
            end
          endcase

        end
      end
    end

    $display("\n=== Simulation Complete ===");
    $finish;
  end

  // === VCD Dump ===
  initial begin
    $dumpfile("adsr_filter_tb.vcd");
    $dumpvars(0, tb_adsr_filter);
  end

endmodule
