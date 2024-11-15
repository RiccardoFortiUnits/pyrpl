`timescale 1ns / 1ps
module peakFinder #(
	parameter dataSize = 8,
	parameter indexSize = 32,
	parameter areSignalsSigned = 1
)(
	input clk,
	input reset,

    input trigger,
	input [dataSize -1:0] in,
	input in_valid,

	input [dataSize -1:0] dataRange_min,//the peak is valid only if it is between these 2 values (the signal passes through dataRange_min before and after the peak, without exceeding dataRange_max)
	input [dataSize -1:0] dataRange_max,

	input [indexSize -1:0] indexRange_min,//the peak is valid only if its index is between these 2 values
	input [indexSize -1:0] indexRange_max,

	output reg [dataSize -1:0] max,
	output reg [indexSize -1:0] maxIndex,
	output reg max_valid
);
	reg [indexSize -1:0] counter;
	wire inIndexRange = $unsigned(counter) >= $unsigned(indexRange_min);
	wire exceededIndexRange = $unsigned(counter) >= $unsigned(indexRange_max);
	wire [dataSize -1:0] minValue = areSignalsSigned ? (1 << (dataSize-1)) : 0;

	reg [dataSize -1:0] currentMax;
	reg [indexSize -1:0] currentMaxIndex;
	
	reg [dataSize -1:0] currentPeak;
	reg [indexSize -1:0] currentPeakIndex;

	localparam  s_notRunning = 0,
				s_underRange = 1,
				s_inRange = 2,
				s_overRange = 3;
	reg [1:0] state;

	wire underDataRange, inDataRange, overDataRange;
	generate
		if(areSignalsSigned)begin
			assign underDataRange = $signed(in) < $signed(dataRange_min);
			assign overDataRange = $signed(in) >= $signed(dataRange_max);
		end else begin
			assign underDataRange = $unsigned(in) < $unsigned(dataRange_min);
			assign overDataRange = $unsigned(in) >= $unsigned(dataRange_max);
			
		end
	endgenerate
	assign inDataRange = !(underDataRange | overDataRange);	

	wire isCurrentValueHigherThanMax = (areSignalsSigned && $signed(in) > $signed(currentMax)) ||
	                   			   ((!areSignalsSigned) && $unsigned(in) > $unsigned(currentMax));
	wire isCurrentMaxHigherThanPeak = (areSignalsSigned && $signed(currentMax) > $signed(currentPeak)) ||
	                   			   ((!areSignalsSigned) && $unsigned(currentMax) > $unsigned(currentPeak));

	always @(posedge clk)begin
		max_valid <= exceededIndexRange && (!reset);//output is valid only when the window just finished
		if (reset)begin
			max <= minValue;
			maxIndex <= 0;
			currentPeak <= minValue;
			currentPeakIndex <= 0;
			currentMax <= minValue;
			currentMaxIndex <= 0;
			counter <= 0;
			state <= s_notRunning;
		end else if(exceededIndexRange)begin// did we just finish the index window?
			//set the output and reset
			if(state == s_inRange && isCurrentMaxHigherThanPeak)begin//is the current max valid and higher than the previous max?
			    max <= currentMax;
			    maxIndex <= currentMaxIndex;
			end else begin
				//let's use the previous max
			    max <= currentPeak;
			    maxIndex <= currentPeakIndex;
			end

			currentPeak <= minValue;
			currentPeakIndex <= 0;
			currentMax <= minValue;
			currentMaxIndex <= 0;
			counter <= 0;
			state <= s_notRunning;
		end else if(trigger || state != s_notRunning)begin
			if(state == s_notRunning)begin
				state <= underDataRange;
			end else if(in_valid)begin//new value to test?
				counter <= counter + 1;
				if(~inIndexRange || state == s_underRange)begin
					state <= underDataRange ? s_underRange : overDataRange ? s_overRange : s_inRange;
				end else if(state == s_inRange)begin
					if(underDataRange)begin//Is the current curve finished?
						//let's check if it is higher than the previous max
						if(isCurrentMaxHigherThanPeak)begin
							currentPeak <= currentMax;
							currentPeakIndex <= currentMaxIndex;
						end
						state <= s_underRange;
					end else if(overDataRange)begin//range exceeded? then the peak value is not valid
						state = s_overRange;
						currentMax <= minValue;
						currentMaxIndex <= 0;
					end else 
					if(isCurrentValueHigherThanMax)begin//are we in the max of the current curve?
						currentMax <= in;
						currentMaxIndex <= counter;
					end
				end else if(state == s_overRange)begin
					//let's stay in the overRange state until we go lower than the dataRange
					state <= underDataRange ? s_underRange : s_overRange;
				end
			end
		end
	end

endmodule
