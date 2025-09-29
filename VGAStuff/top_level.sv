module top_level (
    input  logic clk,
    input  logic reset,
    input  logic vga_ready,
    output logic [29:0] vga_data,
    output logic vga_startofpacket,
    output logic vga_endofpacket,
    output logic vga_valid
);

    logic [7:0] pixel;
    logic       valid, sop, eop;
    logic       ready;

    // =====================================================
    // Grayscale producer (ROM-based, no SDRAM)
    // =====================================================
    grayscale_producer producer (
        .clk(clk),
        .reset(reset),
        .ready(ready),
        .pixel_out(pixel),
        .valid(valid),
        .startofpacket(sop),
        .endofpacket(eop)
    );

    // =====================================================
    // VGA consumer (expects Avalon-ST style interface)
    // If your consumer wants RGB, expand grayscale → RGB
    // =====================================================
    vga_consumer consumer (
        .clk(clk),
        .reset(reset),

        .pixel_in(pixel),              // 8-bit grayscale
        .valid_in(valid),
        .startofpacket_in(sop),
        .endofpacket_in(eop),
        .ready_out(ready),

        .data(vga_data),               // 30-bit RGB stream
        .startofpacket(vga_startofpacket),
        .endofpacket(vga_endofpacket),
        .valid(vga_valid),
        .ready(vga_ready)
    );

endmodule
