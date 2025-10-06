module quad_zoom #(
    parameter integer IMG_WIDTH  = 640,
    parameter integer IMG_HEIGHT = 480,
    parameter integer ZOOM       = 2,    // Integer greater than 1

    parameter integer MID_X      = 319, // This is the left of the centre two pixels
    parameter integer MID_Y      = 239  // This is the upper of the centre two pixels
) (
    input  logic         clk,
    input  logic         reset,

    input  logic [7:0]   pixel_in,
    input  logic         pixel_in_valid,

    output logic [7:0]   pixel_out,
    output logic         pixel_out_valid,

    output logic         busy
);

    localparam integer TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;

    // Note: For FPGA maybe use BRAM?
    logic [7:0] frame_mem [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic [7:0] frame_out [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];

    // Write
    integer write_x;
    integer write_y;
    integer write_count;

    // Read
    integer read_x;
    integer read_y;
    integer read_count;

    // Internal States
    typedef enum logic [1:0] {
        IDLE,
        WRITE_FRAME,
        SHIFT,
        FILL,
        DONE
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
        end 
        else begin
            state <= next_state;
        end
    end

    // Next-state logic and main behavior
    always_ff @(posedge clk) begin
        if (reset) begin
            write_x         <= 0;
            write_y         <= 0;
            write_count     <= 0;
            read_x          <= 0;
            read_y          <= 0;
            read_count      <= 0;
            dx              <= IMG_WIDTH - 1;
            dy              <= IMG_HEIGHT - 1;
            pixel_out       <= 8'd0;
            pixel_out_valid <= 1'b0;
            busy            <= 1'b1;
        end
        else begin
            pixel_out_valid <= 1'b0;
            case (state)
                IDLE: begin
                    if (pixel_in_valid) next_state <= WRITE_FRAME;
                    else next_state <= IDLE;
                end

                WRITE_FRAME: begin
                    busy <= 1'b1;
                    if (pixel_in_valid) begin
                        frame_mem[write_y][write_x] <= pixel_in;
                        // Advance counters
                        if (write_x == IMG_WIDTH - 1) begin
                            write_x <= 0;
                            if (write_y == IMG_HEIGHT - 1) begin
                                write_y <= 0;
                            end 
                            else begin
                                write_y <= write_y + 1;
                            end
                        end 
                        else begin
                            write_x <= write_x + 1;
                        end

                        write_count <= write_count + 1;
                    end

                    // When full frame is written, start modifying
                    if (write_count >= TOTAL_PIXELS) begin
                        write_count <= 0;
                        read_x  <= 0;
                        read_y  <= 0;
                        read_count <= 0;
                        next_state <= SHIFT;
                    end 
                    else begin
                        next_state <= WRITE_FRAME;
                    end
                end

                SHIFT: begin
                    busy <= 1'b1;
                    if (pixel_in_valid) begin
                        // Shift pixels by zoom amount
                        if (read_x <= MID_X && read_y <= MID_Y)     frame_out[read_y][read_x] <= frame_mem[read_y + ZOOM][read_x + ZOOM] // top-left
                        if (read_x > MID_X && read_y <= MID_Y)      frame_out[read_y][read_x] <= frame_mem[read_y + ZOOM][read_x - ZOOM] // top-right
                        if (read_x <= MID_X && read_y > MID_Y)      frame_out[read_y][read_x] <= frame_mem[read_y - ZOOM][read_x + ZOOM] // bottom-left
                        if (read_x > MID_X && read_y > MID_Y)       frame_out[read_y][read_x] <= frame_mem[read_y - ZOOM][read_x - ZOOM] // bottom-right

                        if (read_x == IMG_WIDTH - 1) begin
                            read_x <= 0;
                            if (read_y == IMG_HEIGHT - 1) begin
                                read_y <= 0;
                            end 
                            else begin
                                read_y <= read_y + 1;
                            end
                        end 
                        else begin
                            read_x <= read_x + 1;
                        end

                        read_count <= read_count + 1;
                    end
                    if (read_count >= TOTAL_PIXELS) begin
                        read_count <= 0;
                        next_state <= FILL;
                    end 
                    else begin
                        next_state <= SHIFT;
                    end
                end

                // TO-DO: Fill in middle deadzone with approximated pixels
                FILL: begin
                    busy <= 1'b1;
                    if (pixel_in_valid) begin

                    end
                    if () begin
                        next_state <= DONE;
                    end
                    else begin
                        next_state <= FILL;
                    end
                end

                DONE: begin
                    if (pixel_in_valid) begin
                        
                    end
                end

                default: begin
                    next_state <= IDLE;
                end
            endcase
        end
    end

    // Combinational fallback for next_state when state didn't get set in always_ff (safe)
    always_comb begin
        // maintain default unless overwritten by sequential logic
        // (main next_state updates in sequential block to avoid combinational loops)
    end

endmodule