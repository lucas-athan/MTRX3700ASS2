`timescale 1ns/1ns
module window_function #(parameter W = 16, NSamples = 1024) (
    input clk,
    input reset,

    input  logic x_valid,
    output logic x_ready,
    input  logic [W-1:0] x_data,

    output logic y_valid,
    input  logic y_ready,
    output logic [W-1:0] y_data
);

    // WINDOW FUNCTION SELECTION
    // Currently using rectangle (passthrough) window for simplicity.
    //
    // WHY USE WINDOWING?
    // The FFT assumes the input is periodic. When we take a finite chunk of a continuous
    // signal, we create artificial discontinuities at the boundaries. These cause spectral
    // leakage - energy spreads to adjacent frequency bins, making peaks harder to detect.
    //
    // RECTANGLE WINDOW (current implementation):
    // - Simply passes data through unchanged
    // - Maximum frequency resolution but high spectral leakage
    // - Good when you need precise frequency measurement of stable tones
    //
    // TRIANGLE WINDOW (possible change):
    // - Tapers signal to zero at boundaries
    // - Reduces spectral leakage at cost of frequency resolution
    // - Better for detecting peaks in noisy signals or multiple tones

    // RECTANGLE WINDOW IMPLEMENTATION (passthrough)
    // For a rectangle window, we simply pass all signals through unchanged
    assign x_ready = y_ready;
    assign y_valid = x_valid;
    assign y_data = x_data;

    // TO IMPLEMENT TRIANGLE WINDOW:
    // 1. Add a sample counter that tracks position within NSamples window
    // 2. Calculate window coefficient based on counter position:
    //    - First half (0 to NSamples/2): ramp up from 0 to 1
    //    - Second half (NSamples/2 to NSamples): ramp down from 1 to 0
    // 3. Multiply input data by window coefficient using fixed-point arithmetic
    // 4. Handle the valid/ready signals appropriately for your windowing needs
    //
    // Note: The counter should wrap around after NSamples to create periodic windowing

endmodule