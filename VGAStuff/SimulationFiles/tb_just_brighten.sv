`timescale 1ns/1ps

module tb_just_brighten;

    // ============================================================
    // Clock & Reset
    // ============================================================
    localparam real CLK_PERIOD_NS = 40.0;  // 25 MHz simulated pixel clock

    logic CLOCK_50;
    logic [3:0] KEY;

    // Simulated 25 MHz clock (bypasses PLL in SIMULATION mode)
    initial begin
        CLOCK_50 = 0;
        forever #(CLK_PERIOD_NS/2.0) CLOCK_50 = ~CLOCK_50;
    end

    // Reset and filter enables
    initial begin
        KEY = 4'b1111;
        #200;
        KEY[0] = 1'b0;   // assert reset
        #200;
        KEY[0] = 1'b1;   // release reset
        KEY[1] = 1'b0;   // enable threshold filter
        KEY[2] = 1'b0;   // enable brightness filter
    end

    // ============================================================
    // DUT Instantiation
    // ============================================================
    top_level dut (
        .CLOCK_50    (CLOCK_50),
        .KEY         (KEY),
        .VGA_R       (),
        .VGA_G       (),
        .VGA_B       (),
        .VGA_HS      (),
        .VGA_VS      (),
        .VGA_CLK     (),
        .VGA_BLANK_N (),
        .VGA_SYNC_N  ()
    );

    // ============================================================
    // Simulation Control
    // ============================================================
    localparam int TOTAL_PIXELS = 800 * 525;  // one VGA frame at 640x480@60Hz

    initial begin
        #(TOTAL_PIXELS * CLK_PERIOD_NS);
        $display("✅ Simulation reached end of one VGA frame.");
        $finish;
    end

    // ============================================================
    // VCD dump for waveform viewing
    // ============================================================
    initial begin
        $dumpfile("tb_top_level.vcd");
        $dumpvars(0, tb_just_brighten);
    end

    // ============================================================
    // Frame buffer capture for PPM output
    // ============================================================
    localparam IMG_W = 640;
    localparam IMG_H = 480;

    integer pre_fd, post_fd;
    integer x, y;
    logic [7:0] pre_frame  [0:IMG_W*IMG_H-1];
    logic [7:0] post_frame [0:IMG_W*IMG_H-1];

    // Capture ROM output and final VGA output during visible periods
    always @(posedge dut.VGA_CLK) begin
        if (dut.sync_inst.visible && dut.producer.valid) begin
            int idx;
            idx = dut.sync_inst.vcount * IMG_W + dut.sync_inst.hcount;
            pre_frame[idx]  <= dut.producer.pixel_out;
            post_frame[idx] <= dut.VGA_R;
        end
    end

    // ============================================================
    // Write out PPM images after 1 frame
    // ============================================================
    initial begin
        #(TOTAL_PIXELS * CLK_PERIOD_NS + 1000);
        $display("📝 Writing pre_filter.ppm and post_filter.ppm...");

        automatic int idx;
        automatic byte pix;

        // ---------- PRE FILTER ----------
        pre_fd = $fopen("pre_filter.ppm", "wb");
        if (pre_fd) begin
            $fwrite(pre_fd, "P6\n%d %d\n255\n", IMG_W, IMG_H);
            for (y = 0; y < IMG_H; y++) begin
                for (x = 0; x < IMG_W; x++) begin
                    idx = y * IMG_W + x;
                    pix = pre_frame[idx];
                    $fwrite(pre_fd, "%c%c%c", pix, pix, pix);
                end
            end
            $fclose(pre_fd);
            $display("✅ Wrote pre_filter.ppm");
        end else
            $display("❌ Failed to open pre_filter.ppm for writing.");

        // ---------- POST FILTER ----------
        post_fd = $fopen("post_filter.ppm", "wb");
        if (post_fd) begin
            $fwrite(post_fd, "P6\n%d %d\n255\n", IMG_W, IMG_H);
            for (y = 0; y < IMG_H; y++) begin
                for (x = 0; x < IMG_W; x++) begin
                    idx = y * IMG_W + x;
                    pix = post_frame[idx];
                    $fwrite(post_fd, "%c%c%c", pix, pix, pix);
                end
            end
            $fclose(post_fd);
            $display("✅ Wrote post_filter.ppm");
        end else
            $display("❌ Failed to open post_filter.ppm for writing.");
    end

    // ============================================================
    // Debug Tap for Filter Chain
    // ============================================================
    always @(posedge dut.VGA_CLK) begin
        if (dut.sync_inst.visible &&
            dut.sync_inst.hcount == 100 &&
            dut.sync_inst.vcount == 100) begin
            $display("[%0t] Pixel(100,100): pre=%0d thresh=%0d thresh_valid=%b bright=%0d bright_valid=%b VGA_R=%0d",
                     $time,
                     dut.producer.pixel_out,
                     dut.thresh_stage.pix_out,
                     dut.thresh_stage.valid_out,
                     dut.bright_stage.pix_out,
                     dut.bright_stage.valid_out,
                     dut.VGA_R);
        end
    end

endmodule
