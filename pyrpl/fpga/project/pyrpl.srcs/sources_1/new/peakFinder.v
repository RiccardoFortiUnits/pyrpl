`timescale 1ns / 1ps
module peakFinder #(
	parameter dataSize = 8,
	parameter indexSize = 32,
	parameter areSignalsSigned = 1
)(
	input clk,
	input reset,

    input window_valid,
	input [dataSize -1:0] in,
	input in_valid,

	input [indexSize -1:0] indexRange_min,
	input [indexSize -1:0] indexRange_max,

	output reg [dataSize -1:0] max,
	output reg [indexSize -1:0] maxIndex,
	output reg max_valid
);
	reg [indexSize -1:0] counter;
	wire inIndexRange = $unsigned(counter) >= $unsigned(indexRange_min) && $unsigned(counter) < $unsigned(indexRange_max);
	wire [dataSize -1:0] minValue = areSignalsSigned ? (1 << (dataSize-1)) : 0;
	reg [dataSize -1:0] currentMax;
	reg [indexSize -1:0] currentMaxIndex;
	reg windowWasValid;
	always @(posedge clk) begin
		windowWasValid <= window_valid;
		max_valid <= windowWasValid && (!window_valid) && (!reset);//output is valid only when the window just finished
		if (reset) begin
			max <= minValue;
			maxIndex <= 0;
			currentMax <= minValue;
			currentMaxIndex <= 0;
			counter <= 0;
		end else if(windowWasValid && !window_valid)begin// did we just finish a window?
			//change output and reset
		    max <= currentMax;
		    maxIndex <= currentMaxIndex;
			currentMax <= minValue;
			currentMaxIndex <= 0;
			counter <= 0;
		end else if(window_valid && in_valid) begin// new value to test?
			if(inIndexRange && (
                   (areSignalsSigned && $signed(in) > $signed(currentMax)) ||
                   ((!areSignalsSigned) && $unsigned(in) > $unsigned(currentMax))
               )) begin
				currentMax <= in;
				currentMaxIndex <= counter;
			end
			counter <= counter + 1;
		end
	end

endmodule
