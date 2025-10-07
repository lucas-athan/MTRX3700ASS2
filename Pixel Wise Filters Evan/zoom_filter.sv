module zoom #(
    parameter integer IMG_WIDTH  = 640,
    parameter integer IMG_HEIGHT = 480,

    parameter integer MID_X      = 319, // This is the left of the centre two rows
    parameter integer MID_Y      = 239  // This is the upper of the centre two rows
) (
    input  logic         clk,
    input  logic         reset,

    input  logic [7:0]   pixel_in,
    input  logic         pixel_in_valid,

    input  logic         zoom_value

    output logic [7:0]   pixel_out,
    output logic         pixel_out_valid,
    output logic         busy
);

    localparam integer TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;

    // Note: For FPGA maybe use BRAM?
    logic [7:0] frame_mem [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic [7:0] frame_out [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];

    // Read, Write and Fill Counters 
    integer write_x, write_y, write_count;
    integer read_x, read_y, read_count;
    integer fx, fy;

    // Internal States
    typedef enum logic [1:0] {
        IDLE,
        WRITE,
        SHIFT,
        FILL,
        OUTPUT
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
            read_x          <= 0;
            read_y          <= 0;
            write_count     <= 0;
            read_count      <= 0;
            fx              <= 0;
            fy              <= 0;
            pixel_out       <= 8'd0;
            pixel_out_valid <= 0;
            busy            <= 0;
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
                        read_x  <= 0;
                        read_y  <= 0;
                        read_count <= 0;
                        next_state <= SHIFT;
                    end 
                    else begin
                        next_state <= WRITE;
                    end
                end

                // Output the warped (pushed) frame
                SHIFT: begin
                    busy <= 1;

                    // Compute source coordinates for this output pixel
                    integer sx, sy;
                    sx = read_x;
                    sy = read_y;

                    // Top-left
                    if (read_x <= MID_X && read_y <= MID_Y) begin
                        sx = read_x + ZOOM;
                        sy = read_y + ZOOM;
                    end
                    // Top-right
                    else if (read_x > MID_X && read_y <= MID_Y) begin
                        sx = read_x - ZOOM;
                        sy = read_y + ZOOM;
                    end
                    // Bottom-left
                    else if (read_x <= MID_X && read_y > MID_Y) begin
                        sx = read_x + ZOOM;
                        sy = read_y - ZOOM;
                    end
                    // Bottom-right
                    else begin
                        sx = read_x - ZOOM;
                        sy = read_y - ZOOM;
                    end

                    // Clamp to image boundaries
                    if (sx < 0) sx = 0;
                    if (sy < 0) sy = 0;
                    if (sx > IMG_WIDTH  - 1) sx = IMG_WIDTH  - 1;
                    if (sy > IMG_HEIGHT - 1) sy = IMG_HEIGHT - 1;

                    // Write shifted pixel and mark as valid
                    frame_out[read_y][read_x] <= frame_mem[sy][sx]

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
                        read_count <= 0;
                        next_state <= FILL;
                    end 
                    else begin
                        next_state <= SHIFT;
                    end
                end

                FILL: begin
                    busy <= 1;

                    // Fill the vertical gaps
                    for (int y = 0; y < IMG_HEIGHT; y++) begin
                        logic [7:0] left, right, avg;
                        left  = frame_out[y][MID_X - ZOOM];
                        right = frame_out[y][MID_X + ZOOM];
                        avg   = (left + right) >> 1;

                        for (int x = MID_X - ZOOM + 1; x <= MID_X + ZOOM; x++) begin
                            frame_out[y][x] <= avg;
                        end
                    end

                    // Fill the horizontal gaps
                    for (int x = 0; x < IMG_WIDTH; x++) begin
                        logic [7:0] top, bottom, avg;
                        top    = frame_out[MID_Y - ZOOM][x];
                        bottom = frame_out[MID_Y + ZOOM][x];
                        avg    = (top + bottom) >> 1;

                        for (int y = MID_Y - ZOOM + 1; y <= MID_Y + ZOOM; y++) begin
                            frame_out[y][x] <= avg;
                        end
                    end

                    // Fill the centre square
                    logic [7:0] tl, tr, bl, br;
                    tl = frame_out[MID_Y - ZOOM][MID_X - ZOOM];
                    tr = frame_out[MID_Y - ZOOM][MID_X + ZOOM];
                    bl = frame_out[MID_Y + ZOOM][MID_X - ZOOM];
                    br = frame_out[MID_Y + ZOOM][MID_X + ZOOM];

                    logic [7:0] centre_avg;
                    centre_avg = (tl + tr + bl + br) >> 2;

                    for (int y = MID_Y - ZOOM + 1; y <= MID_Y + ZOOM; y++) begin
                        for (int x = MID_X - ZOOM + 1; x <= MID_X + ZOOM; x++) begin
                            frame_out[y][x] <= centre_avg;
                        end
                    end

                    next_state <= DONE;
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