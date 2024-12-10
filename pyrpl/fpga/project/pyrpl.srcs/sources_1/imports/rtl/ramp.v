`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.03.2024 16:13:05
// Design Name: 
// Module Name: ramp
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



module ramp#(
	parameter nOfRamps = 8,
	parameter data_size = 16,
	parameter time_size = 16,
	parameter inhibitionTimeForTrigger = 500//4e-6s
)(
	input clk,
	input reset,
	input trigger,
	
	output reg [data_size-1:0] out,
    // System bus
    input      [ 32-1:0] addr   ,  // bus address
    input      [ 32-1:0] wdata  ,  // bus write data
    input                wen    ,  // bus write enable
    input                ren    ,  // bus read enable
    output reg [ 32-1:0] rdata  ,  // bus read data
    output reg           err    ,  // bus error indicator
    output reg           ack       // bus acknowledge signal
);
// generates a ramp. When a trigger is detected, it sets the output to the value of startPoint, and 
	//it starts a counter. Every time the counter reaches the value of timeStep, the output gets increased
	//by the value of stepIncrease. When nOfSteps cycles have been executed, the ramp stops
	
//if you start from the ramp paramters startValue, endValue and rampTime, yo

reg [data_size-1:0] startPoint	[nOfRamps-1:0];
reg [time_size-1:0] timeStep	  [nOfRamps-1:0];
reg [data_size-1:0] nOfSteps	  [nOfRamps-1:0];
reg [data_size-1:0] stepIncrease  [nOfRamps-1:0];
reg [1:0] idleConfig;
reg [data_size-1:0] defaultValue;
reg useMultipleTriggers;

//let's save some of the parameters in another batch of registers, so that the state machine can change them during the procedure
reg [data_size-1:0] startPoint_r	[nOfRamps-1:0];
reg [data_size-1:0] stepIncrease_r  [nOfRamps-1:0];
reg [1:0] idleConfig_r;



//states
localparam  s_idle = 0,
			s_inStep = 1,
			s_newStep = 2,
			s_newRamp = 3,
			s_waitingForIntermediateTrigger = 4;
reg [2:0] state;

//configuration of idle state: on which value do we stay while the module is waiting for a trigger?
localparam  c_defaultValue = 0,	 
			c_start = 1,
			c_current = 2,
			c_inverseRamp = 3;

//counters
reg [time_size-1:0] stepCounter;
reg [data_size-1:0] cycleCounter;
reg [$clog2(nOfRamps):0] currentRamp;
reg [$clog2(nOfRamps):0] usedRamps;

//trigger cleaner
wire cleanTrigger;
triggerCleaner#(
	.nOfInhibitionCycles(inhibitionTimeForTrigger)
)tc(
	.clk	(clk),
	.reset  (reset),
	.in	 (trigger),
	.out	(cleanTrigger)
);

integer i;
reg rampIncreaser;//0: increase currentRamp, 1: decrease currentRamp (used for doing inverse ramp)
wire isStepFinished = $unsigned(stepCounter) < 3;
wire isRampFinished = $unsigned(cycleCounter) < 2;
wire isLastRamp = (!rampIncreaser & ($unsigned(currentRamp) >= $unsigned(usedRamps - 1))) || (rampIncreaser & (currentRamp == 0));
always @(posedge clk)begin
	if(reset)begin
		state <= s_idle;
		stepCounter <= 0;
		cycleCounter <= 0;
		currentRamp <= 0;
		idleConfig_r <= 0;
		rampIncreaser <= 0;	  
		for(i = 0; i < nOfRamps; i = i + 1) begin
			startPoint_r [i]	<= 0;
			stepIncrease_r [i]  <= 0; 
		end
	end else begin
		if(state == s_idle)begin
			if(cleanTrigger && usedRamps)begin
				state <= s_inStep;

				//let's start the counters
				stepCounter <= timeStep[0];
				cycleCounter <= nOfSteps[0];
				currentRamp <= 0;
				rampIncreaser <= 0;

				//fix the values of the input parameters
				for(i = 0; i < nOfRamps; i = i + 1) begin
					startPoint_r[i] <= startPoint[i];
					stepIncrease_r[i] <= stepIncrease[i];
				end
				idleConfig_r <= idleConfig;

				//set the first value of the output
				out <= startPoint[0];
			end
		end else if(state == s_waitingForIntermediateTrigger)begin
			if(cleanTrigger)begin
				state <= s_newRamp;
			end
		end else if(state == s_newRamp)begin		
            if(idleConfig_r == c_inverseRamp)begin
               startPoint_r[currentRamp] <= out + stepIncrease_r[currentRamp];
               stepIncrease_r[currentRamp] <= - stepIncrease_r[currentRamp];
            end
			if(isLastRamp)begin
				if(idleConfig_r == c_inverseRamp)begin
					state <= s_inStep;
                    idleConfig_r <= c_current;//remove the inverseRamp configuration, so that we won't repeat it again
                    rampIncreaser <= 1;                    
                    stepCounter <= timeStep[currentRamp];
                    cycleCounter <= nOfSteps[currentRamp];
                end else begin
					state <= s_idle;
                	currentRamp <= 0;
                    case(idleConfig_r)
                        c_defaultValue: begin		out <= defaultValue;end
                        c_start:        begin		out <= startPoint_r[0];end
                        //c_current:    begin	    out <= out; 		end
                        default: begin end
                    endcase
                end
			end else begin
				state <= s_inStep;
				currentRamp <= currentRamp + (rampIncreaser ? -1 : 1);
				stepCounter <= timeStep[currentRamp + (rampIncreaser ? -1 : 1)] - 1;
				cycleCounter <= nOfSteps[currentRamp + (rampIncreaser ? -1 : 1)];
				out <= startPoint_r[currentRamp + (rampIncreaser ? -1 : 1)];
			end
		end else begin
			if(cleanTrigger && useMultipleTriggers)begin
				state <= s_newRamp;
			end else begin
				if(state == s_inStep)begin
					if(isStepFinished)begin
						state <= s_newStep;
					end else begin
						//state <= s_inStep;
						stepCounter = stepCounter - 1;
					end
				end else if(state == s_newStep)begin
					out <= out + stepIncrease_r[currentRamp];//go to the next ramp value
					if(isRampFinished)begin
						state <= useMultipleTriggers ? s_waitingForIntermediateTrigger : s_newRamp;
					end else begin
						state <= s_inStep;
						cycleCounter = cycleCounter - 1;
						stepCounter <= timeStep[currentRamp];
					end
				end
			end
		end
	end
end


//---------------------------------------------------------------------------------
//
//  System bus connection

always @(posedge clk)
if (reset) begin
	usedRamps <= 0;
	idleConfig <= 0;
	defaultValue <= 0;
	useMultipleTriggers <= 0;
	for(i = 0; i < nOfRamps; i = i + 1) begin
		startPoint [i]	<= 0;
		timeStep [i]	  <= 0;
		nOfSteps [i]	  <= 0;
		stepIncrease [i]  <= 0; 
	end
end else if (wen) begin
	if (addr[19:0]==20'h100) {usedRamps, defaultValue, useMultipleTriggers, idleConfig} <= wdata;
	for(i = 0; i < nOfRamps; i = i + 1) begin
		if (addr[19:0]==20'h104 + i * 12) {stepIncrease[i], startPoint[i]} <= wdata;
		if (addr[19:0]==20'h108 + i * 12) timeStep[i] <= wdata;
		if (addr[19:0]==20'h10C + i * 12) nOfSteps[i] <= wdata;
	end
end

wire en;
assign en = wen | ren;

always @(posedge clk) begin
	if (reset) begin
	    err <= 1'b0;
	    ack <= 1'b0;
	end else begin
	    err <= 1'b0;
	    ack <= en;  
	    rdata <=  32'h0;

		if (addr[19:0]==20'h100) rdata <= {usedRamps, defaultValue, useMultipleTriggers, idleConfig};
		for(i = 0; i < nOfRamps; i = i + 1) begin
			if (addr[19:0]==20'h104 + i * 12) rdata <= {stepIncrease[i], startPoint[i]};
			if (addr[19:0]==20'h108 + i * 12) rdata <= timeStep[i];
			if (addr[19:0]==20'h10C + i * 12) rdata <= nOfSteps[i];
		end
	end
end


endmodule
