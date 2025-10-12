`timescale 1ns / 1ps

module grayscale_producer_tb;

    // Parameters matching the DUT
    parameter WIDTH  = 640;
    parameter HEIGHT = 480;
    parameter CLK_PERIOD = 10; // 100 MHz clock

    // Testbench signals
    logic       clk;
    logic       reset;
    logic [9:0] hcount;
    logic [9:0] vcount;
    logic       visible;
    logic [7:0] pixel_out;
    logic       valid;

    // Instantiate the Device Under Test (DUT)
    grayscale_producer #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) dut (
        .clk(clk),
        .reset(reset),
        .hcount(hcount),
        .vcount(vcount),
        .visible(visible),
        .pixel_out(pixel_out),
        .valid(valid)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test stimulus - OPTIMIZED FOR SCREENSHOTS
    initial begin
        // Create VCD file for waveform viewing
        $dumpfile("grayscale_producer_screenshot.vcd");
        $dumpvars(0, grayscale_producer_tb);

        // Initialize signals
        reset = 1;
        hcount = 0;
        vcount = 0;
        visible = 0;

        $display("=== Grayscale Producer - Screenshot Testbench ===");
        $display("This testbench generates clear waveforms for screenshots\n");

        // Apply reset
        repeat(3) @(posedge clk);
        reset = 0;
        $display("[%0t] Reset released", $time);

        // ===== SEQUENCE 1: Show first scanline pixels =====
        $display("\n[%0t] === Sequence 1: First 20 pixels of row 0 ===", $time);
        vcount = 0;
        for (int col = 0; col < 20; col++) begin
            @(posedge clk);
            hcount = col;
            visible = 1;
        end

        // ===== SEQUENCE 2: Toggle visible signal =====
        $display("\n[%0t] === Sequence 2: Visible signal toggling ===", $time);
        for (int i = 0; i < 10; i++) begin
            @(posedge clk);
            hcount = 100 + i;
            vcount = 1;
            visible = (i % 2 == 0); // Toggle visible
        end

        // ===== SEQUENCE 3: Show corner pixels =====
        $display("\n[%0t] === Sequence 3: Corner pixels ===", $time);
        
        // Top-left
        @(posedge clk);
        hcount = 0;
        vcount = 0;
        visible = 1;
        $display("  Top-left (0,0)");
        
        @(posedge clk);
        @(posedge clk);
        
        // Top-right
        @(posedge clk);
        hcount = WIDTH-1;
        vcount = 0;
        visible = 1;
        $display("  Top-right (%0d,0)", WIDTH-1);
        
        @(posedge clk);
        @(posedge clk);
        
        // Bottom-left
        @(posedge clk);
        hcount = 0;
        vcount = HEIGHT-1;
        visible = 1;
        $display("  Bottom-left (0,%0d)", HEIGHT-1);
        
        @(posedge clk);
        @(posedge clk);
        
        // Bottom-right
        @(posedge clk);
        hcount = WIDTH-1;
        vcount = HEIGHT-1;
        visible = 1;
        $display("  Bottom-right (%0d,%0d)", WIDTH-1, HEIGHT-1);

        // ===== SEQUENCE 4: Continuous pixel stream =====
        $display("\n[%0t] === Sequence 4: Continuous 30-pixel stream ===", $time);
        vcount = 10;
        visible = 1;
        for (int col = 0; col < 30; col++) begin
            @(posedge clk);
            hcount = col;
        end

        // ===== SEQUENCE 5: Multiple rows =====
        $display("\n[%0t] === Sequence 5: First 10 pixels of rows 0-4 ===", $time);
        visible = 1;
        for (int row = 0; row < 5; row++) begin
            vcount = row;
            for (int col = 0; col < 10; col++) begin
                @(posedge clk);
                hcount = col;
            end
        end

        // ===== SEQUENCE 6: Non-visible period =====
        $display("\n[%0t] === Sequence 6: Non-visible blanking period ===", $time);
        visible = 0;
        hcount = WIDTH + 10;
        vcount = 100;
        repeat(10) @(posedge clk);

        $display("\n[%0t] === Testbench Complete ===", $time);
        $display("\nSCREENSHOT RECOMMENDATIONS:");
        $display("1. Zoom to show Sequence 1 (0-200ns) - demonstrates pixel reading");
        $display("2. Zoom to show Sequence 2 (200-300ns) - demonstrates valid signal control");
        $display("3. Zoom to show Sequence 4 (500-800ns) - demonstrates continuous operation");
        
        repeat(5) @(posedge clk);
        $finish;
    end

endmodule