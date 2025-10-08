module edge_detection #(
    parameter IMG_WIDTH  = 640,
    parameter IMG_HEIGHT = 480,
    parameter PIXEL_BITS = 8
)(
    input  logic                  clk,
    input  logic                  reset,

    input  logic [PIXEL_BITS-1:0] pixel_in,
    input  logic                  pixel_in_valid,

    output logic [PIXEL_BITS-1:0] pixel_out,
    output logic                  pixel_out_valid
);

    // FSM
    typedef enum logic [2:0] {
        IDLE,
        READ,
        PROCESS,
        DONE
    } state_t;

    state_t state, next_state;

    // Pixel position
    logic [$clog2(IMG_WIDTH)-1:0]  x;
    logic [$clog2(IMG_HEIGHT)-1:0] y;

    // Buffers to store two previous rows
    logic [(PIXEL_BITS-1):0] linebuf1 [0:(IMG_WIDTH-1)];
    logic [(PIXEL_BITS-1):0] linebuf2 [0:(IMG_WIDTH-1)];

    // 3x3 window registers
    logic [PIXEL_BITS-1:0] w00, w01, w02;
    logic [PIXEL_BITS-1:0] w10, w11, w12;
    logic [PIXEL_BITS-1:0] w20, w21, w22;

    // Gradient values
    integer gx, gy, mag;

    // Output register
    logic [PIXEL_BITS-1:0] pixel_reg;

    // FSM + position counters
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            x <= 0;
            y <= 0;
        end 
        else begin
            state <= next_state;
            if (state == READ && pixel_in_valid) begin
                if (x == IMG_WIDTH-1) begin
                    x <= 0;
                    if (y == IMG_HEIGHT-1)
                        y <= 0;
                    else
                        y <= y + 1;
                end else begin
                    x <= x + 1;
                end
            end
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        pixel_out_valid = 0;

        case(state)
            IDLE: begin
                next_state = READ;
            end

            READ: begin
                if (pixel_in_valid) begin
                    next_state = PROCESS;
                end
            end

            PROCESS: begin
                pixel_out_valid = 1;
                next_state = READ;
            end

            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    // --- Line buffer shifting ---
    always_ff @(posedge clk) begin
        if (state == READ && pixel_in_valid) begin
            // shift window horizontally
            w00 <= w01; w01 <= w02; w02 <= linebuf2[x];
            w10 <= w11; w11 <= w12; w12 <= linebuf1[x];
            w20 <= w21; w21 <= w22; w22 <= pixel_in;

            // update line buffers
            linebuf2[x] <= linebuf1[x];
            linebuf1[x] <= pixel_in;
        end
    end

    // --- Sobel Computation ---
    always_comb begin
        pixel_reg = 0;  // Default black
        // Skip borders
        if (x > 0 && x < IMG_WIDTH-1 && y > 0 && y < IMG_HEIGHT-1) begin
            gx = -w00 - 2*w10 - w20 + w02 + 2*w12 + w22;
            gy = -w00 - 2*w01 - w02 + w20 + 2*w21 + w22;

            mag = (gx < 0 ? -gx : gx) + (gy < 0 ? -gy : gy);

            if (mag > 255) begin
                mag = 255;
            end

            pixel_reg = mag[7:0];
        end
    end

    assign pixel_out = pixel_reg;

endmodule