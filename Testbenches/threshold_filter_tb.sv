`timescale 1ns/1ps

module threshold_filter_tb;

    // Parameters
    parameter int BITS = 8;
    parameter int MAX_BPM = 200;
    parameter int CLK_PERIOD = 10;

    // Testbench signals
    logic                           clk;
    logic                           reset;
    logic [BITS-1:0]                pix_in;
    logic                           valid_in;
    logic                           module_ready;
    logic                           output_ready;
    logic                           filter_enable;
    logic [$clog2(MAX_BPM+1)-1:0]   BPM_estimate;
    logic [BITS-1:0]                pix_out;
    logic                           valid_out;
    logic [BITS-1:0]                brightness;

    // Instantiate DUT
    threshold_filter #(
        .BITS(BITS),
        .MAX_BPM(MAX_BPM)
    ) dut (
        .clk(clk),
        .reset(reset),
        .pix_in(pix_in),
        .valid_in(valid_in),
        .module_ready(module_ready),
        .output_ready(output_ready),
        .filter_enable(filter_enable),
        .BPM_estimate(BPM_estimate),
        .pix_out(pix_out),
        .valid_out(valid_out),
        .brightness(brightness)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test stimulus - OPTIMIZED FOR SCREENSHOTS
    initial begin
        $dumpfile("threshold_filter_screenshot.vcd");
        $dumpvars(0, threshold_filter_tb);

        $display("=== Threshold Filter - Screenshot Testbench ===\n");

        // Initialize
        reset = 1;
        pix_in = 0;
        valid_in = 0;
        module_ready = 1;
        filter_enable = 0;
        BPM_estimate = 0;

        repeat(3) @(posedge clk);
        reset = 0;
        $display("[%0t] Reset released", $time);

        // ===== SEQUENCE 1: Transparent mode =====
        $display("\n[%0t] === Sequence 1: Transparent Mode (filter OFF) ===", $time);
        filter_enable = 0;
        BPM_estimate = 100; // threshold = ~127, but filter is off
        
        @(posedge clk);
        @(posedge clk);
        
        // All pixels pass through unchanged
        send_pixel(0);
        send_pixel(50);
        send_pixel(127);
        send_pixel(150);
        send_pixel(200);
        send_pixel(255);

        // ===== SEQUENCE 2: Filter with threshold=127 =====
        $display("\n[%0t] === Sequence 2: Filter ON, BPM=100 (threshold~127) ===", $time);
        filter_enable = 1;
        BPM_estimate = 100;
        
        @(posedge clk);
        @(posedge clk);
        
        // Pixels below/at threshold → 0, above → pass through
        send_pixel(0);      // 0 <= 127 → output 0
        send_pixel(50);     // 50 <= 127 → output 0
        send_pixel(100);    // 100 <= 127 → output 0
        send_pixel(127);    // 127 <= 127 → output 0
        send_pixel(128);    // 128 > 127 → output 128
        send_pixel(150);    // 150 > 127 → output 150
        send_pixel(200);    // 200 > 127 → output 200
        send_pixel(255);    // 255 > 127 → output 255

        // ===== SEQUENCE 3: Low threshold =====
        $display("\n[%0t] === Sequence 3: Filter ON, BPM=25 (threshold~31) ===", $time);
        BPM_estimate = 25;
        
        @(posedge clk);
        @(posedge clk);
        
        send_pixel(0);      // 0 <= 31 → output 0
        send_pixel(31);     // 31 <= 31 → output 0
        send_pixel(32);     // 32 > 31 → output 32
        send_pixel(50);     // 50 > 31 → output 50
        send_pixel(100);    // 100 > 31 → output 100
        send_pixel(200);    // 200 > 31 → output 200

        // ===== SEQUENCE 4: High threshold =====
        $display("\n[%0t] === Sequence 4: Filter ON, BPM=175 (threshold~223) ===", $time);
        BPM_estimate = 175;
        
        @(posedge clk);
        @(posedge clk);
        
        send_pixel(0);      // 0 <= 223 → output 0
        send_pixel(100);    // 100 <= 223 → output 0
        send_pixel(200);    // 200 <= 223 → output 0
        send_pixel(223);    // 223 <= 223 → output 0
        send_pixel(224);    // 224 > 223 → output 224
        send_pixel(230);    // 230 > 223 → output 230
        send_pixel(255);    // 255 > 223 → output 255

        // ===== SEQUENCE 5: Toggle filter enable =====
        $display("\n[%0t] === Sequence 5: Toggle filter enable ===", $time);
        BPM_estimate = 100;
        
        filter_enable = 1;
        @(posedge clk);
        send_pixel(50);     // Filter ON: 50 <= 127 → output 0
        
        filter_enable = 0;
        @(posedge clk);
        send_pixel(50);     // Filter OFF → output 50
        
        filter_enable = 1;
        @(posedge clk);
        send_pixel(150);    // Filter ON: 150 > 127 → output 150
        
        filter_enable = 0;
        @(posedge clk);
        send_pixel(150);    // Filter OFF → output 150

        // ===== SEQUENCE 6: Backpressure demo =====
        $display("\n[%0t] === Sequence 6: Backpressure (module_ready=0) ===", $time);
        filter_enable = 1;
        BPM_estimate = 100;
        
        @(posedge clk);
        module_ready = 1;
        send_pixel(150);    // Should output
        
        @(posedge clk);
        module_ready = 0;   // Downstream not ready
        pix_in = 200;
        valid_in = 1;
        repeat(3) @(posedge clk);  // Hold for 3 cycles
        
        module_ready = 1;   // Release
        @(posedge clk);
        valid_in = 0;

        // ===== SEQUENCE 7: Continuous stream showing threshold effect =====
        $display("\n[%0t] === Sequence 7: Continuous stream (threshold=127) ===", $time);
        filter_enable = 1;
        BPM_estimate = 100;
        module_ready = 1;
        
        @(posedge clk);
        @(posedge clk);
        
        // Send gradient from dark to bright
        for (int i = 0; i <= 10; i++) begin
            send_pixel(i * 25);  // 0, 25, 50, 75, 100, 125, 150, 175, 200, 225, 250
        end

        // ===== SEQUENCE 8: Boundary testing =====
        $display("\n[%0t] === Sequence 8: Threshold boundary testing ===", $time);
        BPM_estimate = 100;  // threshold = 127
        
        @(posedge clk);
        
        send_pixel(125);    // Just below: 125 <= 127 → 0
        send_pixel(126);    // Just below: 126 <= 127 → 0
        send_pixel(127);    // At threshold: 127 <= 127 → 0
        send_pixel(128);    // Just above: 128 > 127 → 128
        send_pixel(129);    // Just above: 129 > 127 → 129

        $display("\n[%0t] === Testbench Complete ===", $time);
        $display("\nSCREENSHOT RECOMMENDATIONS:");
        $display("1. Sequence 1 (100-250ns) - Shows transparent mode");
        $display("2. Sequence 2 (300-550ns) - Shows threshold filtering clearly");
        $display("3. Sequence 5 (1050-1200ns) - Shows filter enable toggling");
        $display("4. Sequence 7 (1400-1650ns) - Shows continuous gradient thresholding");

        repeat(5) @(posedge clk);
        $finish;
    end

    // Helper task
    task send_pixel(input logic [7:0] value);
        @(posedge clk);
        pix_in = value;
        valid_in = 1;
        @(posedge clk);
        valid_in = 0;
    endtask

endmodule