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

	input [indexSize -1:0] indexRange_min,
	input [indexSize -1:0] indexRange_max,

	input [dataSize -1:0] minValue,

	output reg [dataSize -1:0] max,
	output reg [indexSize -1:0] maxIndex,
	output max_valid
);
	reg [indexSize -1:0] counter;
	wire inIndexRange = $unsigned(counter) >= $unsigned(indexRange_min);
	// wire [dataSize -1:0] minValue = areSignalsSigned ? (1 << (dataSize-1)) : 0;
	reg [dataSize -1:0] currentMax;
	reg [indexSize -1:0] currentMaxIndex;
	reg running;
	reg isPeakValid;

	reg peakFound;
	reg [indexSize+1 -1:0] peakValid_counter;//the peak will be considered valid for 2^indexSize cycles
	always @(posedge clk) begin
		// max_valid <= ($unsigned(counter) >= $unsigned(indexRange_max)) && (!reset);//output is valid only when the window just finished
		if (reset) begin
			max <= minValue;
			maxIndex <= 0;
			currentMax <= minValue;
			currentMaxIndex <= 0;
			counter <= 0;
			running <= 0;
			isPeakValid <= 0;
			peakFound <= 0;
			peakValid_counter <= 0;
		end else if($unsigned(counter) >= $unsigned(indexRange_max))begin// did we just finish a window?
			//change output and reset
		    max <= currentMax;
		    maxIndex <= currentMaxIndex;
			currentMax <= minValue;
			currentMaxIndex <= 0;
			counter <= 0;
			running <= 0;
			peakFound <= isPeakValid;
			peakValid_counter <= -1;
			isPeakValid <= 0;
		end else if(trigger || running) begin// new value to test?
			running <= 1;
			if(in_valid)begin
				if(inIndexRange && (
	                   (areSignalsSigned && $signed(in) > $signed(currentMax)) ||
	                   ((!areSignalsSigned) && $unsigned(in) > $unsigned(currentMax))
	               )) begin
					currentMax <= in;
					currentMaxIndex <= counter;
					isPeakValid <= 1;
				end
				counter <= counter + 1;
				if(peakValid_counter)begin
					peakValid_counter <= peakValid_counter - 1;
				end
			end
		end else begin
			if(in_valid && peakValid_counter)begin
				peakValid_counter <= peakValid_counter - 1;
			end
		end
	end

	assign max_valid = peakValid_counter && peakFound;
	
endmodule


module flippedPeakFinder #(
	parameter dataSize = 8,
	parameter indexSize = 32,
	parameter areSignalsSigned = 1
)(
	input clk,
	input reset,

    input trigger,
	input [dataSize -1:0] in,
	input in_valid,

	input [indexSize -1:0] indexRange_min,
	input [indexSize -1:0] indexRange_max,
	input [indexSize -1:0] flipIndex,

	input [dataSize -1:0] minValue,

	output reg [dataSize -1:0] max,
	output [indexSize -1:0] maxIndex,
	output max_valid
);
	reg isFlipped;
	reg [indexSize -1:0] counter;

	wire [indexSize -1:0] flipped_idx_min = isFlipped ? flipIndex - indexRange_max : indexRange_min;
	wire [indexSize -1:0] flipped_idx_max = isFlipped ? flipIndex - indexRange_min : indexRange_max;
	wire inIndexRange = ($unsigned(counter) >= $unsigned(flipped_idx_min)) && ($unsigned(counter) <= $unsigned(flipped_idx_max));
	
	reg [indexSize -1:0] unflipped_maxIndex;
	assign maxIndex = isFlipped ? unflipped_maxIndex : flipIndex - unflipped_maxIndex;//we show maxIndex when isFlipped is already toggled, so it is not maxIndex = isFlipped ? flipIndex - unflipped_maxIndex : unflipped_maxIndex

	reg [dataSize -1:0] currentMax;
	reg [indexSize -1:0] currentMaxIndex;
	reg running;
	reg isPeakValid;

	reg peakFound;
	reg [indexSize+1 -1:0] peakValid_counter;//the peak will be considered valid for 2^indexSize cycles
	always @(posedge clk) begin
		if (reset) begin
			max <= minValue;
			unflipped_maxIndex <= 0;
			currentMax <= minValue;
			currentMaxIndex <= 0;
			counter <= 0;
			running <= 0;
			isPeakValid <= 0;
			peakFound <= 0;
			peakValid_counter <= 0;
			isFlipped <= 0;
		end else if($unsigned(counter) >= $unsigned(flipIndex))begin// did we just finish a window?
			//change output and reset
		    max <= currentMax;
		    unflipped_maxIndex <= currentMaxIndex;
			currentMax <= minValue;
			currentMaxIndex <= 0;
			counter <= 0;
			peakFound <= isPeakValid;
			peakValid_counter <= -1;
			isPeakValid <= 0;
			//stop if we have done a normal window and a flipped window
			if(isFlipped)begin
				running <= 0;
			end
			isFlipped <= !isFlipped;

		end else if(trigger || running) begin// new value to test?
			running <= 1;
			if(in_valid)begin
				if(inIndexRange && (
	                   (areSignalsSigned && $signed(in) > $signed(currentMax)) ||
	                   ((!areSignalsSigned) && $unsigned(in) > $unsigned(currentMax))
	            ))begin
					currentMax <= in;
					currentMaxIndex <= counter;
					isPeakValid <= 1;
				end
				counter <= counter + 1;
				if(peakValid_counter)begin
					peakValid_counter <= peakValid_counter - 1;
				end
			end
		end else begin
			if(in_valid && peakValid_counter)begin
				peakValid_counter <= peakValid_counter - 1;
			end
		end
	end

	assign max_valid = peakValid_counter && peakFound;
	
endmodule
