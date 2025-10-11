`timescale 1ns/1ns
module beat_pulse #(
	 parameter SNR_WIDTH = 16,
    parameter THRESHOLD = 40
) (
    input  logic [SNR_WIDTH-1:0]  snr_db,     
    output logic                  beat_pulse
);

always_comb begin
	if (snr_db >= THRESHOLD) begin
		beat_pulse = 1'b1;
	end
	else begin
		beat_pulse = 1'b0;
	end
end

endmodule
