// Controls blur and zoom filters

module animate_controller #(
    parameter CLK_FREQ_HZ   = 50_000_000,
    parameter ANIM_TIME_MS  = 100,
    parameter ZOOM_MIN      = 1,
    parameter ZOOM_MAX      = 3,
    parameter BLUR_MIN      = 1,
    parameter BLUR_MAX      = 4
)(
    input  logic clk,
    input  logic reset,

    input  logic beat_trigger,

    input  logic pixel_in
    input  logic pixel_in_valid

    output logic pixel_out
    output logic pixel_out_valid
    output logic busy
);

    logic zoom_pixel
    logic zoom_pixel_valid;

    localparam integer ANIM_TICKS = (CLK_FREQ_HZ / 1000) * ANIM_TIME_MS;

    typedef enum logic [1:0] {
        IDLE,
        EXPAND,
        CONTRACT
    } state_t;
    state_t state, next_state;

    integer tick_count;
    logic zoom_value;
    logic blur_radius;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= IDLE;
            zoom_value  <= ZOOM_MIN;
            blur_radius <= BLUR_MIN;
            tick_count  <= 0;
            anim_active <= 0;
        end
        else begin
            case (state)
                IDLE: begin
                    anim_active <= 0;
                    if (beat_trigger) begin
                        state       <= EXPAND;
                        tick_count  <= 0;
                        anim_active <= 1;
                    end
                    else begin
                        state = IDLE;
                    end
                end

                EXPAND: begin
                    tick_count  <= tick_count + 1;
                    zoom_value  <= ZOOM_MIN + ((ZOOM_MAX - ZOOM_MIN) * tick_count) / (ANIM_TICKS/2);
                    blur_radius <= BLUR_MIN + ((BLUR_MAX - BLUR_MIN) * tick_count) / (ANIM_TICKS/2);

                    if (tick_count >= ANIM_TICKS) begin
                        tick_count <= 0;
                        state      <= CONTRACT;
                    end
                end

                CONTRACT: begin
                    tick_count <= tick_count + 1;
                    zoom_value <= ZOOM_MAX - ((ZOOM_MAX - ZOOM_MIN) * tick_count) / (ANIM_TICKS/2);
                    blur_radius <= BLUR_MAX - ((BLUR_MAX - BLUR_MIN) * tick_count) / (ANIM_TICKS/2);

                    if (tick_count >= ANIM_TICKS) begin
                        state <= IDLE;
                        zoom_value <= ZOOM_MIN;
                        blur_radius <= BLUR_MIN;
                        anim_active <= 0;
                    end
                end
            endcase
        end
    end

    blur blur_inst (
        .clk(clk),
        .reset(reset),
        .pixel_in(pixel_in),
        .pixel_in_valid(pixel_in_valid),
        .blur_radius(blur_radius),
        .pixel_out(zoom_pixel),
        .pixel_out_valid(zoom_pixel_valid),
        .busy(busy)
    );

    zoom zoom_inst (
        .clk(clk),
        .reset(reset),
        .pixel_in(zoom_pixel),
        .pixel_in_valid(zoom_pixel_valid),
        .zoom_value(zoom_value)
        .pixel_out(pixel_out),
        .pixel_out_valid(pixel_out_valid)
        .busy(busy)
    );

endmodule