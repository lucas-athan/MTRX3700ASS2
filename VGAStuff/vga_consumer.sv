module vga_consumer (
    input  logic       clk,
    input  logic       reset,

    // Input stream (from producer)
    input  logic [7:0] pixel_in,
    input  logic       valid_in,
    input  logic       startofpacket_in,
    input  logic       endofpacket_in,
    output logic       ready_out,

    // VGA Avalon-ST output
    output logic [29:0] data,
    output logic        startofpacket,
    output logic        endofpacket,
    output logic        valid,
    input  logic        ready
);

    // Handshake: ready when VGA is ready
    assign ready_out = ready;

    // Forward packet signals
    assign valid         = valid_in;
    assign startofpacket = startofpacket_in;
    assign endofpacket   = endofpacket_in;

    // Expand grayscale pixel to 30-bit RGB
    assign data = {
        {pixel_in, 2'b00},  // Red
        {pixel_in, 2'b00},  // Green
        {pixel_in, 2'b00}   // Blue
    };

endmodule
