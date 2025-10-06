`timescale 1ns/1ps

// --- BRIEF ---
// This top level FSM controls the flow of the pixels through multiple filters. It decides 
// what filters should be be appiled given some inputs (beat detect etc). It's designed
// so that the filter stack can be modular.
//
// This way based on BPM_estimate different filters can be stacked

module top_level_fsm (
    input  logic         clk,
    input  logic         reset,
    input  logic [7:0]   pixel_in,        // grayscale or RGB channel input
    input  logic         pixel_valid_in,
    output logic [7:0]   pixel_out,       // processed output
    output logic         pixel_valid_out,
    input  logic [15:0]  BPM_estimate,    // beats per minute input
    input  logic         beat_detected    // 1 if beat pulse detected
);

    // FSM states
    typedef enum logic [2:0] {
        IDLE,
        EDGE,
        LOW_BPM,     // Filter A
        MID_BPM,     // Filter A + Filter B
        HIGH_BPM     // Filter A + Filter B + Filter C
    } state_t;

    state_t current_state, next_state;

    // State register
    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // Next-state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (pixel_valid_in)
                    next_state = EDGE;
            end
            EDGE: begin
                if (BPM_estimate < 100) begin
                    next_state = LOW_BPM;
                end
                else if (BPM_estimate < 140) begin
                    next_state = MID_BPM;
                end
                else begin
                    next_state = HIGH_BPM;
                end
            end
            LOW_BPM:  next_state = IDLE;
            MID_BPM:  next_state = IDLE;
            HIGH_BPM: next_state = IDLE;
        endcase
    end

    // Signals between filters
    logic [7:0] edge_pixel;
    logic       edge_valid;

    logic [7:0] blur_pixel;
    logic       blur_valid;

    logic [7:0] colour_pixel;
    logic       colour_valid;

    logic [7:0] placeholder_pixel;
    logic       placeholder_valid;

    // Edge detector is always active
    edge_detect edge_inst (
        .clk(clk),
        .reset(reset),
        .pixel_in(pixel_in),
        .pixel_valid_in(pixel_valid_in),
        .pixel_out(edge_pixel),
        .pixel_valid_out(edge_valid)
    );

    // Blur + zoom (on beat)
    blur_zoom blur_inst (
        .clk(clk),
        .reset(reset),
        .pixel_in(edge_pixel),
        .pixel_valid_in(edge_valid),
        .beat_detected(beat_detected),
        .pixel_out(blur_pixel),
        .pixel_valid_out(blur_valid)
    );

    // Colour change (based on BPM)
    colour_change colour_inst (
        .clk(clk),
        .reset(reset),
        .pixel_in(blur_pixel),
        .pixel_valid_in(blur_valid),
        .BPM_estimate(BPM_estimate),
        .pixel_out(colour_pixel),
        .pixel_valid_out(colour_valid)
    );

    // Placeholder filter (can be replaced later)
    placeholder_filter placeholder_inst (
        .clk(clk),
        .reset(reset),
        .pixel_in(colour_pixel),
        .pixel_valid_in(colour_valid),
        .pixel_out(placeholder_pixel),
        .pixel_valid_out(placeholder_valid)
    );

    // FSM Controlled Data Routing
    // Desc: This fsm controls what filters the pixels go through based on the BPM

    assign pixel_out = 8'd0;
    assign pixel_valid_out = 1'b0;

    // This assignes where the pipeline stops
    // All the filters are conected into one another and pixels will flow through until pixel_valid_out is triggered
    // This assigns which filter triggers the pixel_valid_out 
    always_comb begin
        pixel_out       = 8'd0;
        pixel_valid_out = 1'b0;
        case (current_state)
            IDLE: begin
                pixel_out = pixel_in;
                pixel_valid_out = pixel_valid_in
            end
            EDGE: begin
                pixel_out = edge_pixel;
                pixel_valid_out = edge_valid;
            end
            LOW_BPM: begin
                pixel_out       = blur_pixel;
                pixel_valid_out = blur_valid;
            end
            MID_BPM: begin
                pixel_out       = colour_pixel;
                pixel_valid_out = colour_valid;
            end
            HIGH_BPM: begin
                pixel_out       = placeholder_pixel;
                pixel_valid_out = placeholder_valid;
            end
            default: begin
                pixel_out       = edge_pixel;
                pixel_valid_out = edge_valid;
            end
        endcase
    end

endmodule