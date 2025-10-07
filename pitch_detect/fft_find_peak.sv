module fft_find_peak #(
    parameter NSamples = 1024, // 1024 N-points
    parameter W        = 33,   // For 16x2 + 1
    parameter NBits    = $clog2(NSamples)

) (
    input                        clk,
    input                        reset,
    input  [W-1:0]               mag,
    input                        mag_valid,
    output logic [W-1:0]         peak = 0,
    output logic [NBits-1:0]     peak_k = 0,
    output logic                 peak_valid
);
    logic [NBits-1:0] i = 0, k;
    // The FFT k-index is represented by bit-reversing i. This has been done for you.
    always_comb for (integer j=0; j<NBits; j=j+1) k[j] = i[NBits-1-j]; // bit-reversed index

    logic [W-1:0]         peak_temp   = 0;
    logic [NBits-1:0]     peak_k_temp = 0;

    always_ff @(posedge clk) begin : find_peak
        //TODO Find the peak (maximum) value out of a window of 1024 streamed samples (512, actually), streamed in one at a time.
        // Store the corresponding k-index representing that value in 'temp_peak_k'.
        // Ensure 'temp_peak_k' is not negative by ignoring the magnitude input when the k-index is negative (MSB==1).
        
        // Reset all registers when 'i == 1023', in preparation for the next FFT window.
        // Also, reset all registers when 'mag_valid' goes low ('mag' should be a continuous data stream).
        // Also, reset in the usual way if 'reset' is high!
        if (reset) begin
            i <= 0;
            peak_temp <= 0;
            peak_k_temp <= 0;
            peak <= 0;
            peak_k <= 0;
            peak_valid <= 0;
        end
        else if (mag_valid) begin
            peak_valid <= 0;

            if (i == 0) begin
                if (k[NBits-1] == 1'b0) begin
                    peak_temp <= mag;
                    peak_k_temp <= k;
                end
            end
            else if (mag > peak_temp) begin
                if (k[NBits-1] == 1'b0) begin
                    peak_temp <= mag;
                    peak_k_temp <= k;
                end
            end
            if (i == NSamples -1) begin
                // Set 'peak_valid' to 1'b1 for a single clock cycle when 'i == 1023'.
                // When setting 'peak_valid'=1, also set 'peak' and 'peak_k' to 'temp_peak' and 'temp_peak_k', respectively, when 'i == 1023' (note: this actually ignores the last value, but it has negative k-index, so we ignore it anyway!).
                peak <= peak_temp;
                peak_k <= peak_k_temp;
                peak_valid <= 1;
                i <= 0;
                peak_temp <= 0;
                peak_k_temp <= 0;
            end
            // Use the counter 'i' to count from 0 to 1023. Then use 'k' as the value to set in 'temp_peak_k'.
            else begin 
                i <= i + 1;
            end
        end
    end
endmodule
