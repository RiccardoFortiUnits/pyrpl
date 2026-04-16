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
	
//if you start from the ramp paramters startValue, endValue and rampTime, 
								//you can obtain the following values as:
reg [data_size-1:0] startPoint	[nOfRamps-1:0];		// = startPoint
reg [time_size-1:0] timeStep	  [nOfRamps-1:0];	// = rampTime / nOfSteps
reg [data_size-1:0] stepIncrease  [nOfRamps-1:0];	// = (endValue - startValue) / nOfSteps
reg [data_size-1:0] nOfSteps	  [nOfRamps-1:0];	// chosen so that the obtained ramp is 
				//as similar as possible to the requested one (due to quantization, you might 
				//need to try different values of the parameters)
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

/*
vsim work.ramp
add wave -position insertpoint sim:/ramp/*
add wave -position insertpoint sim:/ramp/startPoint_r
add wave -position insertpoint sim:/ramp/timeStep_r
add wave -position insertpoint sim:/ramp/stepIncrease_r
add wave -position insertpoint sim:/ramp/nOfSteps_r
force -freeze sim:/ramp/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/ramp/reset z1 0
force -freeze sim:/ramp/trigger z0 0


*/




module ramp_withDivisionsAndExponential#(
	parameter nOfRamps = 4,
	parameter data_size = 8,
	parameter time_size = 4,
	parameter inhibitionTimeForTrigger = 2//500//4e-6s
)(
	input clk,
	input reset,
	input trigger,
	
	output reg [data_size-1:0] out,
    // System bus
    // input      [ 32-1:0] addr   ,  // bus address
    // input      [ 32-1:0] wdata  ,  // bus write data
    // input                wen    ,  // bus write enable
    // input                ren    ,  // bus read enable
    // output reg [ 32-1:0] rdata  ,  // bus read data
    // output reg           err    ,  // bus error indicator
    // output reg           ack       // bus acknowledge signal

	input [(data_size+1)*nOfRamps -1:0] DVs,//needs an extra bit, because you can have a ramp that does the entire range, and it can also be negative
	input [time_size*nOfRamps -1:0] DTs,
	input [data_size -1:0] startValue,
	input [$clog2(nOfRamps):0] usedRamps,
	input [data_size-1:0] defaultValue,
	input [1:0] idleConfig,
	input [nOfRamps -1:0] doesNextRampWaitForTriggers
);

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

//configuration of idle state: on which value do we stay while the module is waiting for a trigger?
localparam  c_defaultValue = 0,	 
			c_start = 1,
			c_current = 2,
			c_inverseRamp = 3;
// reg [1:0] idleConfig;
// reg [data_size-1:0] defaultValue;

// reg [nOfRamps -1:0] doesNextRampWaitForTrigger;//you can have the sequence to stop at the end of any ramp to wait for a new trigger, 
	// or to start the next ramp even before the current ramp is done. The last bit might seem useless, since there's no more ramps after 
	// the last. It's only purpose is to stop the last ramp prematurely if a trigger is recieved
reg isRunning;//will be 0 when waiting for a trigger, even if we're in the middle of the sequence (if the current bit in doesNextRampWaitForTrigger is 1)

reg [$clog2(nOfRamps):0] currentRamp;
wire [time_size -1:0] DT = DTs[(currentRamp+1)*time_size -1-:time_size];
wire [data_size+1 -1:0] DV = DVs[(currentRamp+1)*(data_size+1) -1-:(data_size+1)];
wire [data_size+1 -1:0] DV_next = DVs[(currentRamp+2)*(data_size+1) -1-:(data_size+1)];
wire doesNextRampWaitForTrigger = doesNextRampWaitForTriggers[currentRamp];//this bit tells us if the next ramp wants a trigger, not the current one 

reg [time_size -1:0] n;//main counter. We'll go to the next ramp when n == DT
reg [time_size+data_size+1 -1:0] nDV;//will store n*DV
reg [data_size-1:0] V0;

wire isLastRamp = currentRamp == usedRamps - 1;

wire [time_size+data_size+1 -1:0] nDV_DT;
wire [data_size+1 -1:0] mt;
//divisor...
wire [time_size+data_size -1:0] abs_nDV = nDV[time_size+data_size+1-1] ? -nDV : nDV;
wire [time_size+data_size -1:0] abs_nDV_DT;
assign abs_nDV_DT = abs_nDV / DT;
assign nDV_DT = nDV[time_size+data_size+1-1] ? -{1'b0, abs_nDV_DT} : {1'b0, abs_nDV_DT};

fixedPointShifter#(
	.inputBitSize	(time_size+data_size+1),
	.inputFracSize	(data_size),
	.outputBitSize	(data_size+1),
	.outputFracSize	(data_size),
	.isSigned		(1),
	.saturateOutput (1)
)create_mt(
	.in				(nDV_DT),
	.out			(mt)
);

always @(posedge clk)begin
	if(reset)begin
		isRunning <= 0;
		nDV <= 0;
		V0 <= 0;
		n <= 0;
		currentRamp <= 0;
		out <= 0;
	end else begin
		out <= {V0[data_size-1], V0} + mt;

		if(!isRunning)begin//waiting for a trigger?
			if(cleanTrigger && usedRamps)begin//trigger recieved?
				isRunning <= 1;
				n <= 1;
				nDV <= {{time_size{DV[data_size+1-1]}},DV};
			end else if(currentRamp == 0)begin//are we waiting to start the sequence?
				//add exception for inverseRamp, and save start value
				V0 <= startValue;
			end
		end else begin
			if(	(doesNextRampWaitForTrigger && cleanTrigger	) ||//should we start prematurely the next ramp?
				(					n==DT					))begin//current ramp ended?
				V0 <= {V0[data_size-1],V0} + DV;//can't set it equal to the current output, because we might be ending prematurely a ramp
				
				if(isLastRamp)begin//last ramp?
					currentRamp <= 0;
					isRunning <= 0;
					nDV <= 0;//set to 0, so that in the next clock cycle the output won't move
					n <= 0;
				end else begin
					currentRamp <= currentRamp + 1;
					if(doesNextRampWaitForTrigger || isLastRamp)begin//do we have to wait for a new trigger?
						isRunning <= 0;
						nDV <= 0;//set to 0, so that in the next clock cycle the output won't move
						n <= 0;
					end else begin
						isRunning <= 1;
						nDV <= {{time_size{DV_next[data_size+1-1]}},DV_next};
						n <= 1;
					end
				end
			end else begin
				//let's continue the ramp
				n <= n + 1;
				nDV <= nDV + {{time_size{DV[data_size+1-1]}},DV};
			end
		end
	end
end




//---------------------------------------------------------------------------------
//
//  System bus connection

// always @(posedge clk)
// if (reset) begin
// 	usedRamps <= 0;
// 	idleConfig <= 0;
// 	defaultValue <= 0;
// 	useMultipleTriggers <= 0;
// 	for(i = 0; i < nOfRamps; i = i + 1) begin
// 		startPoint [i]	<= 0;
// 		timeStep [i]	  <= 0;
// 		nOfSteps [i]	  <= 0;
// 		stepIncrease [i]  <= 0; 
// 	end
// end else if (wen) begin
// 	if (addr[19:0]==20'h100) {usedRamps, defaultValue, useMultipleTriggers, idleConfig} <= wdata;
// 	for(i = 0; i < nOfRamps; i = i + 1) begin
// 		if (addr[19:0]==20'h104 + i * 12) {stepIncrease[i], startPoint[i]} <= wdata;
// 		if (addr[19:0]==20'h108 + i * 12) timeStep[i] <= wdata;
// 		if (addr[19:0]==20'h10C + i * 12) nOfSteps[i] <= wdata;
// 	end
// end

// wire en;
// assign en = wen | ren;

// always @(posedge clk) begin
// 	if (reset) begin
// 	    err <= 1'b0;
// 	    ack <= 1'b0;
// 	end else begin
// 	    err <= 1'b0;
// 	    ack <= en;  
// 	    rdata <=  32'h0;

// 		if (addr[19:0]==20'h100) rdata <= {usedRamps, defaultValue, useMultipleTriggers, idleConfig};
// 		for(i = 0; i < nOfRamps; i = i + 1) begin
// 			if (addr[19:0]==20'h104 + i * 12) rdata <= {stepIncrease[i], startPoint[i]};
// 			if (addr[19:0]==20'h108 + i * 12) rdata <= timeStep[i];
// 			if (addr[19:0]==20'h10C + i * 12) rdata <= nOfSteps[i];
// 		end
// 	end
// end


endmodule



/*

vsim work.ramp_withDivisionsAndExponential
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/*
force -freeze sim:/ramp_withDivisionsAndExponential/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/ramp_withDivisionsAndExponential/reset z1 0
force -freeze sim:/ramp_withDivisionsAndExponential/trigger z0 0
force -freeze sim:/ramp_withDivisionsAndExponential/DVs 36ae823 0
force -freeze sim:/ramp_withDivisionsAndExponential/DTs 637 0
force -freeze sim:/ramp_withDivisionsAndExponential/startValue 0 0
force -freeze sim:/ramp_withDivisionsAndExponential/usedRamps 3 0
force -freeze sim:/ramp_withDivisionsAndExponential/defaultValue 0 0
force -freeze sim:/ramp_withDivisionsAndExponential/idleConfig 0 0
force -freeze sim:/ramp_withDivisionsAndExponential/doesNextRampWaitForTriggers 2 0
run
force -freeze sim:/ramp_withDivisionsAndExponential/reset 10 0
run
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 01 0
run
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 10 0
run 1200ps
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 01 0
run
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 10 0
run 1000ps


*/