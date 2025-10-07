module blur_filter #(
    parameter DATA_WIDTH = 8,   // Greyscale pixel (0–255)
    parameter IMG_WIDTH  = 640
)(
    input  logic                  clk,
    input  logic                  reset,

    input  logic [DATA_WIDTH-1:0] pixel_in,
    input  logic                  pixel_in_valid,
    output logic                  pixel_in_ready,

    output logic [DATA_WIDTH-1:0] pixel_out,
    output logic                  pixel_out_valid
);

    // 3-line buffer for 3x3 blur kernel
    logic [DATA_WIDTH-1:0] line0 [0:IMG_WIDTH-1];
    logic [DATA_WIDTH-1:0] line1 [0:IMG_WIDTH-1];
    logic [DATA_WIDTH-1:0] line2 [0:IMG_WIDTH-1];

    // Average calculation buffers
    logic S1, S2, S3, S4;

    integer i;
    logic [$clog2(IMG_WIDTH)-1:0] x;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            x <= 0;
            pixel_out_valid <= 0;
        end 
        else if (pixel_in_valid) begin
            // Shift line buffers vertically
            line0[x] <= line1[x];
            line1[x] <= line2[x];
            line2[x] <= pixel_in;

            // Increment horizontal position
            if (x == IMG_WIDTH - 1) begin
                x <= 0;
            end
            else begin
                x <= x + 1;
            end

            // Compute blur
            if (x > 1 && x < IMG_WIDTH - 1) begin
                pixel_out_valid <= 1;
                S1 <= line0[x-1] + line0[x] + line0[x+1];
                S2 <= line1[x-1] + line1[x] + line1[x+1];
                S3 <= line2[x-1] + line2[x] + line2[x+1];
                S4 <= S1 + S2 + S3;
                pixel_out <= S4 / 9;
            end
            else begin
                pixel_out_valid <= 0;
            end
        end
    end

    assign pixel_in_ready = 1;

endmodule