`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09.02.2026 15:25:44
// Design Name: 
// Module Name: doubleFreqCounter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module doubleFreqCounter#(
	parameter timingSizes = 8
)(
    input clk,
    input reset,
	input enable,
	input [timingSizes -1:0] nextSwitchingTime,
	output out
    );

reg [timingSizes + 1 -1:0] counter;
reg rising, falling;
always @(posedge clk) begin
	if (reset) begin
		counter <= 0;
		rising <= 0;
	end else begin
		if(enable)begin
			if (counter <= 1) begin
				counter <= counter + nextSwitchingTime - 2;
				if(counter == 0)begin
					rising <= !rising;
				end
			end else begin
				counter <= counter - 2;
			end
		end else begin
			counter <= nextSwitchingTime - 2;
		end
	end
end
reg preDelayed_falling;
always @(negedge clk) begin
	if (reset) begin
		falling <= 0;
		preDelayed_falling <= 0;
	end else begin
		if(enable)begin
			if(counter == 1)begin
				preDelayed_falling <= !preDelayed_falling;
			end
			falling <= preDelayed_falling;
		end
	end
end

assign out = rising ^ falling;

endmodule


module multiTimingDoubleFreqCounter#(
	parameter nOfTimings = 5,
	parameter nofOutputs = 2,
	parameter timingSizes = 8
)(
    input clk,
    input reset,
	input trigger,
	input [timingSizes * nOfTimings -1:0] timings,
	input [nofOutputs * nOfTimings -1:0] requestedOutputValues,
	input [nofOutputs -1:0] defaultOutputValue,
	output [nofOutputs -1:0] outputs
);
/*
	module that sets a certain amount of output pins to specified values at some specified time intervals. 
	The time intervals are precise to half a clock cycle, and the number of timings and corresponding output 
	values are modifiable.
	Use this module if you want to control the output digital pins with a sequence of values with very precise 
	timings. But, make sure that the output never passes through a register, or you would lose the half-clock 
	precision. It should only be handled with asynchronous components, until it reaches the output pins

	When the module recieves a trigger, outputs will be set to the first value specified in requestedOutputValues. 
	Then, after waiting the number of half-clock cycles specified in the first value of timings, outputs will be updated 
	to the second value contained in requestedOutputValues. And so on...

	Before the trigger, and after all the timings are done, outputs will be set to defaultOutputValue. So, the 
	initial and final values will have to be the same if you want to use this module

	If the trigger is high when the sequence finishes, the sequence will be repeated immediately
*/
`define time(i) (timings[(i+1) * timingSizes -1-:timingSizes])
`define val(i) (requestedOutputValues[(i+1) * nofOutputs -1-:nofOutputs])

/*
	we have two always statement, one on the positive edge of the clock, and the other on the negative one. The positive 
	block is the main one, and it handles the trigger detection, and updating the counter. The counter is decreased of 2 
	at each clock cycle (1 equals a half cycle), and if it reaches 0, the rising edge block will update the output, while 
	if it reaches 1, the falling edge block will update it. Actually, the effects of the falling block are delayed of one 
	clock cycle, since it sees the counter a step before the main block.
	The actual output is chosen in an asynchronous way, depending on which of the blocks should be considered
*/

reg [timingSizes + 1 -1:0] counter;
reg [nofOutputs -1:0] rising, falling;
reg [nofOutputs -1:0] preDelayed_falling;
reg [$clog2(nOfTimings+1) -1:0] currentIndex;
reg running, running_delayed;
reg prevCounterParity_pos, prevCounterParity_neg, prevCounterParity_neg_delayed;

always @(posedge clk) begin
	if (reset) begin
		counter <= 0;
		prevCounterParity_pos <= 0;
		rising <= 0;
		currentIndex <= 0;
		running <= 0;
		running_delayed <= 0;
		rising <= defaultOutputValue;
	end else begin
		running_delayed <= running;
		if(!running)begin
			if(trigger) begin
				running <= 1;
				counter <= `time(0) - 2;
				currentIndex <= 1;
				rising <= `val(0);
			end else begin
				counter <= 0;
				prevCounterParity_pos <= 0;
			end
			if(running_delayed)begin
				rising <= defaultOutputValue;
			end
		end else begin
			if(counter <= 1) begin
				prevCounterParity_pos <= counter;
				if(currentIndex == nOfTimings && !trigger)begin
					currentIndex <= 0;
					running <= 0;
					if(counter == 0)begin
						rising <= defaultOutputValue;
					end
				end else begin
					if(counter == 0)begin
						rising <= currentIndex == nOfTimings ? `val(0) : `val(currentIndex);
					end
					if(currentIndex == nOfTimings)begin
						counter <= counter + `time(0) - 2;
						currentIndex <= 1;
					end else begin
						counter <= counter + `time(currentIndex) - 2;
						currentIndex <= currentIndex + 1;						
					end
				end
			end else begin
				counter <= counter - 2;
			end
		end
	end
end
always @(negedge clk) begin
	if (reset) begin
		preDelayed_falling <= defaultOutputValue;
		falling <= defaultOutputValue;
		prevCounterParity_neg <= 0;
		prevCounterParity_neg_delayed <= 0;
	end else begin
		prevCounterParity_neg_delayed <= prevCounterParity_neg;
		if (!running_delayed && !running) begin
			preDelayed_falling <= defaultOutputValue;
			falling <= defaultOutputValue;
			prevCounterParity_neg <= 0;
		end else begin
			if(counter <= 1)begin
				prevCounterParity_neg <= counter;
			end
			if(counter == 1)begin				
				if(currentIndex == nOfTimings && !trigger)begin
					preDelayed_falling <= defaultOutputValue;
				end else begin
					preDelayed_falling <= currentIndex == nOfTimings ? `val(0) : `val(currentIndex);
				end
			end
			falling <= preDelayed_falling;
		end
	end
end
assign outputs = (prevCounterParity_pos && prevCounterParity_neg_delayed) ? falling : rising;
endmodule

module multiTimingDoubleFreqCounter_beginAndEndSequences#(
	parameter nOfBeginningTimings = 2,
	parameter nOfLoopingTimings = 3,
	parameter nOfEndingTimings = 2,
	parameter nofOutputs = 3,
	parameter timingSizes = 8
)(
    input clk,
    input reset,
	input trigger,
	input [timingSizes * nOfBeginningTimings -1:0] timings_begin,
	input [timingSizes * nOfLoopingTimings -1:0] timings_loop,
	input [timingSizes * nOfEndingTimings -1:0] timings_end,
	input [nofOutputs * nOfBeginningTimings -1:0] requestedOutputValues_begin,
	input [nofOutputs * nOfLoopingTimings -1:0] requestedOutputValues_loop,
	input [nofOutputs * nOfEndingTimings -1:0] requestedOutputValues_end,
	input [nofOutputs -1:0] defaultOutputValue,
	output [nofOutputs -1:0] outputs
);
/*
	Similar to multiTimingDoubleFreqCounter, but it's meant for repeating sequences that 
	have some initial and final steps (to be repeated only once)
	The looping section will be repeated until the trigger is kept high. When the trigger 
	is lowered, the sequence will finish the current loop, execute the end steps and go 
	back to the default value.

	The begin, loop and end sequences can be empty (set nOfBeginningTimings, nOfLoopingTimings or nOfEndingTimings to 0)
*/
localparam loopStartIndex = nOfBeginningTimings;
localparam loopEndIndex = nOfBeginningTimings + nOfLoopingTimings;
localparam allSteps = nOfBeginningTimings + nOfLoopingTimings + nOfEndingTimings;
wire [allSteps * timingSizes -1:0] allTimings;
wire [allSteps * nofOutputs -1:0] allValues;
generate
	if(nOfBeginningTimings)begin
		assign allTimings[loopStartIndex * timingSizes -1:0] = timings_begin;
		assign allValues[loopStartIndex * nofOutputs -1:0] = requestedOutputValues_begin;
	end
	if(nOfLoopingTimings)begin
		assign allTimings[loopEndIndex * timingSizes -1:loopStartIndex * timingSizes] = timings_loop;
		assign allValues[loopEndIndex * nofOutputs -1:loopStartIndex * nofOutputs] = requestedOutputValues_loop;
	end
	if(nOfEndingTimings)begin
		assign allTimings[allSteps * timingSizes -1:loopEndIndex * timingSizes] = timings_end;
		assign allValues[allSteps * nofOutputs -1:loopEndIndex * nofOutputs] = requestedOutputValues_end;
	end
endgenerate
`define mtime(i) (allTimings[(i+1) * timingSizes -1-:timingSizes])
`define mval(i) (allValues[(i+1) * nofOutputs -1-:nofOutputs])

reg [timingSizes + 1 -1:0] counter;
reg [nofOutputs -1:0] rising, falling;
reg [nofOutputs -1:0] preDelayed_falling;
reg [$clog2(allSteps+1) -1:0] currentIndex;
reg running, running_delayed;
reg prevCounterParity_pos, prevCounterParity_neg, prevCounterParity_neg_delayed;

wire shouldWeLoop;
generate
	if(nOfLoopingTimings)begin
		assign shouldWeLoop = trigger && (currentIndex == loopEndIndex);
	end else begin
		assign shouldWeLoop = 0;
	end
endgenerate
wire [$clog2(allSteps+1) -1:0] nextIndex = shouldWeLoop ? 
												loopStartIndex : 
												(currentIndex == allSteps ? 
													0 : 
													currentIndex);

always @(posedge clk) begin
	if (reset) begin
		counter <= 0;
		prevCounterParity_pos <= 0;
		rising <= 0;
		currentIndex <= 0;
		running <= 0;
		running_delayed <= 0;
		rising <= defaultOutputValue;
	end else begin
		running_delayed <= running;
		if(!running)begin
			if(trigger) begin
				running <= 1;
				counter <= `mtime(0) - 2;
				currentIndex <= 1;
				rising <= `mval(0);
			end else begin
				counter <= 0;
				prevCounterParity_pos <= 0;
				rising <= defaultOutputValue;
			end
		end else begin
			if(counter <= 1) begin
				prevCounterParity_pos <= counter;
				if(currentIndex == allSteps && !trigger)begin
					currentIndex <= 0;
					running <= 0;
					if(counter == 0)begin
						rising <= defaultOutputValue;
					end
				end else begin
					if(counter == 0)begin
						rising <= `mval(nextIndex);
					end
					counter <= counter + `mtime(nextIndex) - 2;
					currentIndex <= shouldWeLoop ? 
										loopStartIndex + 1 : 
										(currentIndex == allSteps ?
											1 :
											currentIndex + 1);
				end
			end else begin
				counter <= counter - 2;
			end
		end
	end
end
always @(negedge clk) begin
	if (reset) begin
		preDelayed_falling <= defaultOutputValue;
		falling <= defaultOutputValue;
		prevCounterParity_neg <= 0;
		prevCounterParity_neg_delayed <= 0;
	end else begin
		prevCounterParity_neg_delayed <= prevCounterParity_neg;
		if (!running_delayed && !running) begin
			preDelayed_falling <= defaultOutputValue;
			falling <= defaultOutputValue;
			prevCounterParity_neg <= 0;
		end else begin
			if(counter <= 1)begin
				prevCounterParity_neg <= counter;
			end
			if(counter == 1)begin				
				if(currentIndex == allSteps && !trigger)begin
					preDelayed_falling <= defaultOutputValue;
				end else begin
					preDelayed_falling <= `mval(nextIndex);
				end
			end
			falling <= preDelayed_falling;
		end
	end
end
assign outputs = (prevCounterParity_pos && prevCounterParity_neg_delayed) ? falling : rising;

endmodule

/*
vsim work.multiTimingDoubleFreqCounter
add wave -position insertpoint sim:/multiTimingDoubleFreqCounter/*
force -freeze sim:/multiTimingDoubleFreqCounter/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/multiTimingDoubleFreqCounter/reset z1 0
force -freeze sim:/multiTimingDoubleFreqCounter/trigger z0 0
force -freeze sim:/multiTimingDoubleFreqCounter/timings 0303030303 0
force -freeze sim:/multiTimingDoubleFreqCounter/requestedOutputValues 39e 0
force -freeze sim:/multiTimingDoubleFreqCounter/defaultOutputValue 0 0
run
force -freeze sim:/multiTimingDoubleFreqCounter/reset 10 0
run
force -freeze sim:/multiTimingDoubleFreqCounter/trigger 01 0
run
run
run
run
run
run


*/

/*
vsim work.multiTimingDoubleFreqCounter_beginAndEndSequences
add wave -position insertpoint sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/*
force -freeze sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/reset z1 0
force -freeze sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/trigger z0 0
force -freeze sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/timings_begin 0403 0
force -freeze sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/timings_loop 040405 0
force -freeze sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/timings_end 0506 0
force -freeze sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/requestedOutputValues_begin 08 0
force -freeze sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/requestedOutputValues_loop 11a 0
force -freeze sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/requestedOutputValues_end 35 0
force -freeze sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/defaultOutputValue 7 0
run
force -freeze sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/reset 10 0
run
run
force -freeze sim:/multiTimingDoubleFreqCounter_beginAndEndSequences/trigger 01 0
run
run
run
run
run
run
run
run
run
run
run
run
run
run
run
run
run
run
run
run
run
run

*/