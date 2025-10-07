module blur #(
    parameter IMAGE_HEIGHT  = 480,
    parameter IMG_WIDTH     = 640,
    parameter MAX_RADIUS    = 4
)(
    input  logic                  clk,
    input  logic                  reset,

    input  logic [DATA_WIDTH-1:0] pixel_in,
    input  logic                  pixel_in_valid,

    input  logic                  blur_radius

    output logic [DATA_WIDTH-1:0] pixel_out,
    output logic                  pixel_out_valid,
    output logic                  busy
);

    localparam integer TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;

    // Frame buffer (temporary — use BRAM in real design)
    logic [7:0] frame_mem [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic [7:0] frame_out [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];

    integer x, y, i, j;
    integer write_x, write_y, write_count;
    integer read_x, read_y, read_count;

    typedef enum logic [1:0] {
        IDLE,
        WRITE,
        BLUR,
        OUTPUT
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            write_x         <= 0; 
            write_y         <= 0;
            read_x          <= 0;  
            read_y          <= 0;
            pixel_out_valid <= 0;
            busy            <= 0;
            state           <= IDLE;
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
                        state       <= WRITE;
                    end
                    else begin
                        state <= IDLE;
                    end
                end

                WRITE: begin
                    busy <= 1;
                    if (pixel_in_valid) begin
                        frame_mem[write_y][write_x] <= pixel_in;

                        // Advance Counters
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

                        write_count = write_count + 1;
                    end

                    if (write_count >= TOTAL_PIXELS) begin
                        read_x      <= 0;
                        read_y      <= 0;
                        write_count <= 0;
                        read_count  <= 0;
                        next_state  <= BLUR;
                    end 
                    else begin
                        next_state  <= WRITE;
                    end
                end

                BLUR: begin
                    busy <= 1;

                    // Apply dynamic box blur
                    integer sum, count;
                    sum = 0;
                    count = 0;

                    for (int i = -blur_radius; i <= blur_radius; i++) begin
                        for (int j = -blur_radius; j <= blur_radius; j++) begin
                            if ((read_x + j) >= 0 && (read_x + j) < IMG_WIDTH && (read_y + i) >= 0 && (read_y + i) < IMG_HEIGHT) begin
                                sum   = sum + frame_mem[read_y + i][read_x + j];
                                count = count + 1;
                            end
                        end
                    end

                    frame_out[read_y][read_x] <= sum / count;

                    // Advance Counters
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

                    read_count = read_count + 1;

                    if (read_count >= TOTAL_PIXELS) begin
                        read_count <= 0;
                        read_x     <= 0;
                        read_y     <= 0;
                        next_state <= OUTPUT;
                    end 
                    else begin
                        next_state <= BLUR;
                    end

                end

                OUTPUT: begin
                    busy <= 1;
                    pixel_out <= frame_out[read_y][read_x];
                    pixel_out_valid <= 1;

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

                    read_count = read_count + 1;

                    if (read_count >= TOTAL_PIXELS) begin
                        read_count <= 0;
                        read_x     <= 0;
                        read_y     <= 0;
                        next_state <= IDLE;
                    end 
                    else begin
                        next_state <= OUTPUT;
                    end
                end
            endcase
        end
    end
endmodule