module grayscale_producer #(
    parameter WIDTH  = 640,
    parameter HEIGHT = 480
)(
    input  logic       clk,
    input  logic       reset,

    // from VGA sync
    input  logic [9:0] hcount,
    input  logic [9:0] vcount,
    input  logic       visible,

    output logic [7:0] pixel_out,
    output logic       valid
);

    localparam int NUMPIXELS = WIDTH * HEIGHT;

    // Compute address from current raster position
    wire [18:0] pixel_index;
    assign pixel_index = vcount * WIDTH + hcount;

    // Instantiate ROM
    ImageRom image_rom_inst (
        .address(pixel_index),
        .clock(clk),
        .q(pixel_out)
    );

    // Pixel valid only during visible region
    assign valid = visible;

endmodule
