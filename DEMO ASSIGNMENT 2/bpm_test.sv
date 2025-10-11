`timescale 1ns/1ns
module bpm_test #(
	 parameter SNR_WIDTH = 16,
    parameter THRESHOLD = 80
) (
    input  logic [SNR_WIDTH-1:0]  snr_db,     // 0-84
    output logic                  led_on
);

always_comb begin
	if (snr_db >= THRESHOLD) begin
		led_on = 1'b1;
	end
	else begin
		led_on = 1'b0;
	end
end

endmodule
