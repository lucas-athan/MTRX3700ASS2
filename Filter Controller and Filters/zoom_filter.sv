module zoom_filter #(
    parameter integer IMG_WIDTH  = 640,
    parameter integer IMG_HEIGHT = 480,
    parameter integer DATA_WIDTH = 8,

    parameter integer MID_X      = 319, // This is the left of the centre two rows
    parameter integer MID_Y      = 239  // This is the upper of the centre two rows
)(
    input  logic                    clk,
    input  logic                    reset,

    input  logic [DATA_WIDTH-1:0]   pixel_in,
    input  logic                    pixel_in_valid,

    input  logic [7:0]              zoom_value,

    output logic [DATA_WIDTH-1:0]   pixel_out,
    output logic                    pixel_out_valid,
    output logic                    busy
);

    localparam integer TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;

    // Note: For FPGA maybe use BRAM?
    logic [7:0] frame_mem [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic [7:0] frame_out [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];

    // Read, Write and Fill Counters 
    integer write_x, write_y, write_count;
    integer read_x, read_y, read_count;
    integer sx, sy;

    // Fill variables
    logic [7:0] tl, tr, bl, br, centre_avg;
    integer fill_x, fill_y;

    // Main FSM
    typedef enum logic [2:0] {
        IDLE,
        WRITE,
        SHIFT,
        FILL,
        OUTPUT
    } state_t;
    state_t state, next_state;

    // Fill sub-FSM
    typedef enum logic [1:0] {
        FILL_VERTICAL,
        FILL_HORIZONTAL,
        FILL_CENTER,
        FILL_DONE
    } fill_state_t;
    fill_state_t fill_state;

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
            read_x          <= 0;
            read_y          <= 0;
            write_count     <= 0;
            read_count      <= 0;
            sx              <= 0;
            sy              <= 0;
            pixel_out       <= 8'd0;
            pixel_out_valid <= 0;
            busy            <= 0;
            fill_x          <= 0;
            fill_y          <= 0;
            fill_state      <= FILL_VERTICAL;
            next_state      <= IDLE;
        end
        else begin
            pixel_out_valid <= 0;
            case (state)
                IDLE: begin
                    busy <= 0;
                    if (pixel_in_valid) begin
                        busy        <= 1;
                        write_x     <= 0;
                        write_y     <= 0;
                        write_count <= 0;
                        next_state  <= WRITE;
                    end
                    else begin
                        next_state <= IDLE;
                    end
                end

                WRITE: begin
                    busy <= 1;

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
                        read_x      <= 0;
                        read_y      <= 0;
                        read_count  <= 0;
                        sx          <= 0;
                        sy          <= 0;
                        next_state  <= SHIFT;
                    end 
                    else begin
                        next_state  <= WRITE;
                    end
                end

                // Output the warped (pushed) frame
                SHIFT: begin
                    busy <= 1;

                    // Compute source coordinates for this output pixel
                    sx = read_x;
                    sy = read_y;

                    // Top-left
                    if (read_x <= MID_X && read_y <= MID_Y) begin
                        sx = read_x + zoom_value;
                        sy = read_y + zoom_value;
                    end
                    // Top-right
                    else if (read_x > MID_X && read_y <= MID_Y) begin
                        sx = read_x - zoom_value;
                        sy = read_y + zoom_value;
                    end
                    // Bottom-left
                    else if (read_x <= MID_X && read_y > MID_Y) begin
                        sx = read_x + zoom_value;
                        sy = read_y - zoom_value;
                    end
                    // Bottom-right
                    else begin
                        sx = read_x - zoom_value;
                        sy = read_y - zoom_value;
                    end

                    // Clamp to image boundaries
                    if (sx < 0) sx = 0;
                    if (sy < 0) sy = 0;
                    if (sx > IMG_WIDTH  - 1) sx = IMG_WIDTH  - 1;
                    if (sy > IMG_HEIGHT - 1) sy = IMG_HEIGHT - 1;

                    // Write shifted pixel and mark as valid
                    frame_out[read_y][read_x] <= frame_mem[sy][sx];

                    // Advance counters
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

                    // When full frame done go back to write
                    if (read_count >= TOTAL_PIXELS) begin
                        read_count  <= 0;
                        tl          <= 0;
                        tr          <= 0;
                        bl          <= 0;
                        br          <= 0;
                        centre_avg  <= 0;
                        next_state  <= FILL;
                    end 
                    else begin
                        next_state  <= SHIFT;
                    end
                end

                FILL: begin
                    busy <= 1;

                    case (fill_state)
                        // Fill vertical gap
                        FILL_VERTICAL: begin
                            frame_out[fill_y][MID_X] <= (frame_out[fill_y][MID_X - zoom_value] + frame_out[fill_y][MID_X + zoom_value]) >> 1;
                            if (fill_y == IMG_HEIGHT-1) begin
                                fill_y <= 0;
                                fill_state <= FILL_HORIZONTAL;
                            end 
                            else begin
                                fill_y <= fill_y + 1;
                            end
                        end

                        // Fill horizontal gap
                        FILL_HORIZONTAL: begin
                            frame_out[MID_Y][fill_x] <= (frame_out[MID_Y - zoom_value][fill_x] + frame_out[MID_Y + zoom_value][fill_x]) >> 1;
                            if (fill_x == IMG_WIDTH-1) begin
                                fill_x <= 0;
                                fill_state <= FILL_CENTER;
                            end 
                            else begin 
                                fill_x <= fill_x + 1;
                            end
                        end

                        // Fill center square
                        FILL_CENTER: begin
                            tl <= frame_out[MID_Y - zoom_value][MID_X - zoom_value];
                            tr <= frame_out[MID_Y - zoom_value][MID_X + zoom_value];
                            bl <= frame_out[MID_Y + zoom_value][MID_X - zoom_value];
                            br <= frame_out[MID_Y + zoom_value][MID_X + zoom_value];
                            centre_avg <= (tl + tr + bl + br) >> 2;

                            frame_out[MID_Y - zoom_value + fill_y][MID_X - zoom_value + fill_x] <= centre_avg;

                            if (fill_x == 2*zoom_value) begin
                                fill_x <= 0;
                                if (fill_y == 2*zoom_value) begin
                                    fill_y <= 0;
                                    fill_state <= FILL_DONE;
                                end 
                                else begin 
                                    fill_y <= fill_y + 1;
                                end
                            end 
                            else begin 
                                fill_x <= fill_x + 1;
                            end
                        end

                        FILL_DONE: begin
                            next_state <= OUTPUT;
                        end
                    endcase

                    next_state <= OUTPUT;
                end

                OUTPUT: begin
                    busy <= 1;
                    pixel_out <= frame_out[read_y][read_x];
                    pixel_out_valid <= 1;

                    // Advance counters
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

                    if (read_count >= TOTAL_PIXELS) begin
                        read_count <= 0;
                        next_state <= IDLE;
                    end 
                    else begin
                        next_state <= OUTPUT;
                    end
                end

                default: next_state <= IDLE;
            endcase
        end
    end

endmodule