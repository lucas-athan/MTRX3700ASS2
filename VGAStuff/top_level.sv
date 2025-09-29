module top_level (
    input        CLOCK_50,        // DE2-115 50 MHz onboard clock
    input  [3:0] KEY,             // Pushbuttons (KEY[0] used for reset)

    // VGA outputs
    output [7:0] VGA_R,
    output [7:0] VGA_G,
    output [7:0] VGA_B,
    output       VGA_HS,
    output       VGA_VS,
    output       VGA_CLK,
    output       VGA_BLANK_N,
    output       VGA_SYNC_N
);

    // ============================================================
    // Pixel clock
    // ============================================================
    wire pix_clk;

    pll25 pll_inst (
        .inclk0 (CLOCK_50),
        .c0     (pix_clk)
    );

    assign VGA_CLK = pix_clk;

    // ============================================================
    // VGA sync generator
    // ============================================================
    wire [9:0] hcount, vcount;
    wire       visible;

    vga_sync sync_inst (
        .clk     (pix_clk),
        .reset   (~KEY[0]), // still keep KEY[0] reset if you want
        .hcount  (hcount),
        .vcount  (vcount),
        .visible (visible),
        .hsync   (VGA_HS),
        .vsync   (VGA_VS),
        .blank_n (VGA_BLANK_N)
    );

    assign VGA_SYNC_N = 1'b0;

    // ============================================================
    // Producer
    // ============================================================
    wire [7:0] pixel;
    wire       valid;

    grayscale_producer producer (
        .clk       (pix_clk),
        .reset     (~KEY[0]),
        .hcount    (hcount),
        .vcount    (vcount),
        .visible   (visible),
        .pixel_out (pixel),
        .valid     (valid)
    );

    // ============================================================
    // Filter stage (brighten with KEY[1])
    // ============================================================
    wire [7:0] filtered_pixel;

    filter_stage filter (
        .pixel_in    (pixel),
        .brighten_en (~KEY[1]), 
        .pixel_out   (filtered_pixel)
    );

    // ============================================================
    // Pixel → VGA RGB
    // ============================================================
    assign VGA_R = (visible && valid) ? filtered_pixel : 8'd0;
    assign VGA_G = (visible && valid) ? filtered_pixel : 8'd0;
    assign VGA_B = (visible && valid) ? filtered_pixel : 8'd0;

endmodule
