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
    input  logic         pixel_in_valid,

    input  logic [15:0]  BPM_estimate,    // beats per minute input
    input  logic         beat_detected    // 1 if beat pulse detected
    input  logic         filter_enable

    output logic [7:0]   pixel_out,       // processed output
    output logic         pixel_out_valid,
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
        if (reset) begin
            current_state <= IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    // Next-state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (pixel_in_valid)
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

    // !!! RENAME LATER !!!
    // Signals between filters 
    logic [7:0] pixel_wire_1,   pixel_wire_2,   pixel_wire_3,   pixel_wire_4;
    logic       pixel_valid_1,  pixel_valid_2,  pixel_valid_3,  pixel_valid_4;
    logic       busy


    // Edge detector is always active
    edge_detect edge_inst (
        .clk(clk),
        .reset(reset),
        .pixel_in(pixel_in),
        .pixel_in_valid(pixel_in_valid),
        .pixel_out(pixel_wire_1),
        .pixel_out_valid(pixel_valid_1)
    );

    // Blur + zoom (on beat)
    animate_controller anim_inst (
        .clk(clk),
        .reset(reset),
        .beat_trigger(),
        .pixel_in(pixel_wire_1),
        .pixel_in_valid(pixel_valid_1),
        .pixel_out(pixel_wire_2),
        .pixel_out_valid(pixel_valid_2),
        .busy(busy)
    );

    // Placeholder filter (can be replaced later)
    placeholder_filter placeholder_inst (
        .clk(clk),
        .reset(reset),
        .pixel_in(pixel_wire_2),
        .pixel_in_valid(pixel_valid_2),
        .pixel_out(pixel_wire_3),
        .pixel_out_valid(pixel_valid_3)
    );

    // Placeholder filter (can be replaced later)
    placeholder_filter placeholder_inst (
        .clk(clk),
        .reset(reset),
        .pixel_in(pixel_wire_3),
        .pixel_in_valid(pixel_valid_3),
        .pixel_out(pixel_wire_4),
        .pixel_out_valid(pixel_valid_4)
    );

    // FSM Controlled Data Routing
    // Desc: This fsm controls what filters the pixels go through based on the BPM

    assign pixel_out = 8'd0;
    assign pixel_out_valid = 0;

    // This assignes where the pipeline stops
    // All the filters are conected into one another and pixels will flow through until pixel_out_valid is triggered
    // This assigns which filter triggers the pixel_out_valid 
    always_comb begin
        pixel_out       = 8'd0;
        pixel_out_valid = 0;
        case (current_state)
            IDLE: begin
                pixel_out       = pixel_in;
                pixel_out_valid = pixel_in_valid;
            end
            EDGE: begin
                pixel_out       = pixel_wire_2;
                pixel_out_valid = pixel_valid_2;
            end
            LOW_BPM: begin
                pixel_out       = pixel_wire_2;
                pixel_out_valid = pixel_valid_2;
            end
            MID_BPM: begin
                pixel_out       = pixel_wire_3;
                pixel_out_valid = pixel_valid_3;
            end
            HIGH_BPM: begin
                pixel_out       = pixel_wire_4;
                pixel_out_valid = pixel_valid_4;
            end
            default: begin
                pixel_out       = pixel_in;
                pixel_out_valid = pixel_in_valid;
            end
        endcase
    end

endmodule