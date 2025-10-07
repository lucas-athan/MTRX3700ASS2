module fft_input_buffer #(
    parameter W = 16,
    parameter NSamples = 1024
) (
     input                clk,
     input                reset,
     input                audio_clk,
     
     input  logic         audio_input_valid,
     output logic         audio_input_ready,
     input  logic [W:0]   audio_input_data,

     output logic [W-1:0] fft_input,
     output logic         fft_input_valid
);
    logic fft_read;
    logic full, wr_full;
    async_fifo u_fifo (.aclr(reset),
                        .data(audio_input_data),.wrclk(audio_clk),.wrreq(audio_input_valid),.wrfull(wr_full),
                        .q(fft_input),          .rdclk(clk),      .rdreq(fft_read),         .rdfull(full)    );
    assign audio_input_ready = !wr_full;

    assign fft_input_valid = fft_read; // The Async FIFO is set such that valid data is read out whenever the rdreq flag is high.
    
    //TODO implement a counter n to set fft_read to 1 when the FIFO becomes full (use full, not wr_full).
    // Then, keep fft_read set to 1 until 1024 (NSamples) samples in total have been read out from the FIFO.

    logic [NSamples:0] counter; 

    always_ff @(posedge clk) begin : fifo_flush
        if (reset) begin
            counter <= 0;
            fft_read <= 0;
        end
        else if (fft_read) begin
            if (counter == NSamples - 1) begin
                counter <= 0;
                fft_read <= 0;
            end
            else begin
                counter <= counter + 1;
            end
        end
        else if (full) begin
            counter <= 0;
            fft_read <= 1;
        end
    end

endmodule
