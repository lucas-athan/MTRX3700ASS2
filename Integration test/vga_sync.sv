module vga_sync #(
    parameter H_VISIBLE = 640,
    parameter H_FRONT   = 16,
    parameter H_SYNC    = 96,
    parameter H_BACK    = 48,
    parameter H_TOTAL   = 800,
    parameter V_VISIBLE = 480,
    parameter V_FRONT   = 10,
    parameter V_SYNC    = 2,
    parameter V_BACK    = 33,
    parameter V_TOTAL   = 525
)(
    input  logic clk,       // pixel clock (25 MHz for 640x480@60Hz)
    input  logic reset,

    output logic [9:0] hcount,
    output logic [9:0] vcount,
    output logic       visible,
    output logic       hsync,
    output logic       vsync,
    output logic       blank_n
);

    // Counters
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            hcount <= 10'd0;
            vcount <= 10'd0;
        end else begin
            if (hcount == H_TOTAL-1) begin
                hcount <= 10'd0;
                if (vcount == V_TOTAL-1)
                    vcount <= 10'd0;
                else
                    vcount <= vcount + 10'd1;
            end else begin
                hcount <= hcount + 10'd1;
            end
        end
    end

    // Sync signals
    assign hsync   = ~((hcount >= H_VISIBLE+H_FRONT) &&
                       (hcount <  H_VISIBLE+H_FRONT+H_SYNC));
    assign vsync   = ~((vcount >= V_VISIBLE+V_FRONT) &&
                       (vcount <  V_VISIBLE+V_FRONT+V_SYNC));
    assign visible = (hcount < H_VISIBLE) && (vcount < V_VISIBLE);
    assign blank_n = visible;

endmodule
