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
					rising = !rising;
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
`define time(i) (timings[(i+1) * timingSizes -1-:timingSizes])
`define val(i) (requestedOutputValues[(i+1) * nofOutputs -1-:nofOutputs])

reg [timingSizes + 1 -1:0] counter;
reg [nofOutputs -1:0] rising, falling;
reg toggle_rising, toggle_falling;
reg toggle_rising_delayed, toggle_falling_delayed, preDelayed_toggle_falling;
reg [nofOutputs -1:0] preDelayed_falling;
reg [$clog2(nOfTimings+2) -1:0] currentIndex;
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
		toggle_rising <= 0;
		toggle_rising_delayed <= 0;
	end else begin
		running_delayed <= running;
		toggle_rising_delayed <= toggle_rising;
		if(!running)begin
			if(trigger) begin
				running <= 1;
				counter <= `time(0) - 2;
				currentIndex <= 1;
				rising <= `val(0);
				toggle_rising <= !toggle_rising;
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
				if(counter == 0)begin
					rising <= `val(currentIndex);
					toggle_rising <= !toggle_rising;
				end
				if(currentIndex == nOfTimings)begin
					currentIndex <= 0;
					running <= 0;
					if(counter == 0)begin
						rising <= defaultOutputValue;
					end
				end else begin
					counter <= counter + `time(currentIndex) - 2;
					currentIndex <= currentIndex + 1;
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
		toggle_falling <= 0;
		toggle_falling_delayed <= 0;
		preDelayed_toggle_falling <= 0;
		prevCounterParity_neg <= 0;
		prevCounterParity_neg_delayed <= 0;
	end else begin
		toggle_falling_delayed <= toggle_falling;
		toggle_falling <= preDelayed_toggle_falling;
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
				if(currentIndex == nOfTimings)begin
					preDelayed_falling <= defaultOutputValue;
				end else begin
					preDelayed_falling <= `val(currentIndex);
				end
				preDelayed_toggle_falling <= !preDelayed_toggle_falling;
			end
			falling <= preDelayed_falling;
		end
	end
end
assign outputs = (prevCounterParity_pos && prevCounterParity_neg_delayed) ? falling : rising;
// always @(negedge clk or posedge clk) begin
// 	if(reset || !(running || running_delayed))begin
// 		outputs <= rising;		
// 	end else begin
// 		if (toggle_rising != toggle_rising_delayed) begin
// 			outputs <= rising;
// 		end else if (toggle_falling != toggle_falling_delayed) begin
// 			outputs <= falling;
// 		end
// 	end
// end

endmodule

