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
	input      [ 16-1:0] addr   ,  // bus address
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
	if (addr==20'h100) {usedRamps, defaultValue, useMultipleTriggers, idleConfig} <= wdata;
	for(i = 0; i < nOfRamps; i = i + 1) begin
		if (addr==20'h104 + i * 12) {stepIncrease[i], startPoint[i]} <= wdata;
		if (addr==20'h108 + i * 12) timeStep[i] <= wdata;
		if (addr==20'h10C + i * 12) nOfSteps[i] <= wdata;
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

		if (addr==20'h100) rdata <= {usedRamps, defaultValue, useMultipleTriggers, idleConfig};
		for(i = 0; i < nOfRamps; i = i + 1) begin
			if (addr==20'h104 + i * 12) rdata <= {stepIncrease[i], startPoint[i]};
			if (addr==20'h108 + i * 12) rdata <= timeStep[i];
			if (addr==20'h10C + i * 12) rdata <= nOfSteps[i];
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
	parameter time_size = 8,
	parameter nOfStepsBeforeHalfing = 4,
	parameter inhibitionTimeForTrigger = 2//500//4e-6s
)(
	input clk,
	input reset,
	input trigger,
	
	output reg [data_size-1:0] out,
	// System bus
	input      [ 16-1:0] addr   ,  // bus address
	input      [ 32-1:0] wdata  ,  // bus write data
	input                wen    ,  // bus write enable
	input                ren    ,  // bus read enable
	output reg [ 32-1:0] rdata  ,  // bus read data
	output reg           err    ,  // bus error indicator
	output reg           ack       // bus acknowledge signal
);
/*	
This module generates a sequence of ramps, each of which has its duration and slope specified by the user.
The ramp sequence starts when a trigger is recieved, and each ramp can be requested to wait for a new 
	trigger before starting, otherwise, a ramp will start immediately after the end of the previous one.
	Whether or not the sequence will be halted after the end of a ramp is dictated by the bits of 
	register doesNextRampWaitForTriggers. If the bits of this register are set, the next ramp can be 
	started prematurely (even if the current ramp has not ended yet) if a trigger is received during the 
	execution of the current ramp

The value of the output at the end of the sequence can be selected by setting idleConfig between these options
	defaultValue	= 0: the output value is set to defaultValue
	start			= 1: the output value is set to the start value of the first ramp (startValue)
	current			= 2: the output value is set to the end value of the last ramp
	inverseRamp		= 3: the entire sequence will executed in a reversed order, after which the output will 
							be set to startValue

how does it work

	for each ramp: 
		the user specifies 
			DT (duration of the ramp, in clock cycles)
			DV (difference between the initial value of the ramp and the last)
		at each clock cycle, the output will be 
			o = V0 + n DV / DT
			with n the number of clock cycles from the start of the ramp and V0 the offset value of the ramp
		V0 is either
			startValue, if we're doing the first ramp
			the last value of the previous ramp otherwise



*/


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

reg [(data_size+1)*nOfRamps -1:0] DVs;
reg [time_size*nOfRamps -1:0] DTs;
reg [data_size -1:0] startValue;
reg [$clog2(nOfRamps):0] usedRamps;
reg [data_size-1:0] defaultValue;
reg [1:0] idleConfig;
reg [nOfRamps -1:0] doesNextRampWaitForTriggers;

reg isRunning;//will be 0 when waiting for a trigger, even if we're in the middle of the sequence (if the current bit in doesNextRampWaitForTrigger is 1)

reg [$clog2(nOfRamps):0] currentRamp;
wire [time_size -1:0] DT = DTs[(currentRamp+1)*time_size -1-:time_size];
wire [data_size+1 -1:0] DV = DVs[(currentRamp+1)*(data_size+1) -1-:(data_size+1)];
wire [data_size+1 -1:0] DV_next = DVs[(currentRamp+2)*(data_size+1) -1-:(data_size+1)];
wire doesNextRampWaitForTrigger = doesNextRampWaitForTriggers[currentRamp];//this bit tells us if the next ramp wants a trigger, not the current one 




reg [nOfRamps -1:0] isExponentials;
localparam section_size = time_size;//todo put a smaller register size, time_size is a bit too big
localparam coefficientSize = data_size;//todo corretto?
reg [section_size*nOfRamps -1:0] exp_SectionLengths;

reg [coefficientSize*nOfStepsBeforeHalfing -1:0] halfExponents;
integer i;
real x,c;
initial begin
	c = $pow(0.5, 1.0 / real'(nOfStepsBeforeHalfing));
	for (i = 0; i < nOfStepsBeforeHalfing; i=i+1) begin
		x = $pow(c, i) - 1;// * (c-1);
		halfExponents[(i+1)*coefficientSize -1-:coefficientSize] = $rtoi(-x * (1<<(coefficientSize)) + 0.5);
	end
end
reg [time_size -1:0] exp_internalCounter;
reg [$clog2(nOfStepsBeforeHalfing+1) -1:0] exp_coefficientIndex;
reg [$clog2(data_size+1) -1:0] exp_coefficientShifter;
wire [$clog2(data_size+1) -1:0] exp_coefficientShifter_next = exp_coefficientShifter + (exp_coefficientShifter >= data_size ? 0 : 1);

wire isExponential = isExponentials[currentRamp];
wire isExponential_next = isExponentials[currentRamp+1];
wire [coefficientSize -1:0] exp_coeff = halfExponents[(exp_coefficientIndex+1)*coefficientSize -1-:coefficientSize];
wire [coefficientSize -1:0] exp_nextCoeff = halfExponents[(((exp_coefficientIndex+1)%nOfStepsBeforeHalfing)+1)*coefficientSize -1-:coefficientSize];
wire [coefficientSize -1:0] exp_currentDV = exp_nextCoeff - exp_coeff;
wire [section_size -1:0] exp_SectionLength = exp_SectionLengths[(currentRamp+1)*section_size -1-:section_size];
wire [data_size+1 -1:0] exp_slope_unShifted;
wire [data_size+1 -1:0] exp_slope;
wire [data_size+1 -1:0] exp_slope_delayed;
delayer#(data_size+1, 1) delayExpSlope(clk,reset, exp_slope, exp_slope_delayed);


clocked_FractionalMultiplier #(
  .A_WIDTH			(data_size+1),
  .B_WIDTH			(coefficientSize+1),//exp_coeff is unsigned, let's add a sign bit
  .OUTPUT_WIDTH		(data_size+1),
  .FRAC_BITS_A		(data_size),
  .FRAC_BITS_B		(coefficientSize),
  .FRAC_BITS_OUT	(data_size),
  .areSignalsSigned (1)
) generate_expSlope (
  .clk(clk),
  .a(DV),
  .b({1'b0,exp_coeff}),
  .result(exp_slope_unShifted)
);
assign exp_slope = exp_slope_unShifted >> exp_coefficientShifter;

wire [(data_size+1) -1:0] step = isExponential ? exp_slope : DV;
wire [(data_size+1) -1:0] step_next = isExponential_next ? exp_slope : DV_next;//todo make exp_slope_next


reg [time_size -1:0] n;//main counter. We'll go to the next ramp when n == DT
reg [time_size+data_size+1 -1:0] nDV;//will store n*DV

localparam divisorDelay = 5;
reg [data_size-1:0] V0;
reg [data_size-1:0] V0_atRampStart;
wire [data_size-1:0] V0_delayed;
wire [data_size-1:0] V0_next = {V0_atRampStart[data_size-1],V0_atRampStart} + DV;
delayer#(data_size, divisorDelay) delayV0(clk,reset, V0, V0_delayed);



wire isLastRamp = currentRamp == usedRamps - 1;

wire [data_size+1 -1:0] mt;
fractionalDivider #(//dividers take 5 clock cycles to generate the output
	.A_WIDTH			(time_size+data_size+1),
	.B_WIDTH			(time_size),
	.OUTPUT_WIDTH		(data_size+1),
	.FRAC_BITS_A		(data_size),
	.FRAC_BITS_B		(0),
	.FRAC_BITS_OUT		(data_size),
	.areSignalsSigned	(1),// numerator and denominators will always be positive
	.saturateOutput     (0)
) create_mt(
	.clk		(clk),
	.reset		(reset),
	.a			(nDV),
	.b			(isExponential ? (exp_SectionLength+1) : DT),
	.result		(mt)
);


always @(posedge clk)begin
	if(reset)begin
		isRunning <= 0;
		nDV <= 0;
		V0 <= 0;
		V0_atRampStart <= 0;
		n <= 0;
		currentRamp <= 0;
		out <= 0;

		exp_internalCounter <= 0;
		exp_coefficientIndex <= 0;
		exp_coefficientShifter <= 0;
	end else begin
		out <= {V0_delayed[data_size-1], V0_delayed} + mt;

		if(!isRunning)begin//waiting for a trigger?
			if(cleanTrigger && usedRamps)begin//trigger recieved?
				isRunning <= 1;
				n <= 1;
				exp_internalCounter <= 1;
				nDV <= {{time_size{step[data_size+1-1]}},step};
				if(currentRamp == 0)begin//are we waiting to start the sequence?
					//add exception for inverseRamp, and save start value
					V0 <= startValue;
					V0_atRampStart <= startValue;
				end
			end
		end else begin
			if(	(doesNextRampWaitForTrigger && cleanTrigger	) ||//should we start prematurely the next ramp?
				(					n==DT					))begin//current ramp ended?
				exp_internalCounter <= 1;
				exp_coefficientIndex <= 0;
				exp_coefficientShifter <= 0;

				if(isLastRamp)begin//last ramp?
					currentRamp <= 0;
					isRunning <= 0;
					nDV <= 0;//set to 0, so that in the next clock cycle the output won't move
					n <= 0;					
					case(idleConfig)
						c_defaultValue: begin		V0 <= defaultValue;end
						c_start:        begin		V0 <= startValue;end
						c_current:        begin		V0 <= V0_next;end
						default: begin end
					endcase

				end else begin
					V0 <= V0_next;
					V0_atRampStart <= V0_next;
					currentRamp <= currentRamp + 1;
					if(doesNextRampWaitForTrigger || isLastRamp)begin//do we have to wait for a new trigger?
						isRunning <= 0;
						nDV <= 0;//set to 0, so that in the next clock cycle the output won't move
						n <= 0;
					end else begin
						isRunning <= 1;
						nDV <= {{time_size{step_next[data_size+1-1]}},step_next};
						n <= 1;
					end
				end
			end else begin
				//let's continue the ramp
				n <= n + 1;
				//let's anticipate the update of the exponential indexes of a few clock cycles, so that all the values depending on those indexes can be calculated and ready for when we're gonna actually change the indexes
				if (isExponential && exp_internalCounter == exp_SectionLength - 2)begin
					if (exp_coefficientIndex == nOfStepsBeforeHalfing - 1) begin//go to new order of magnitude?
						exp_coefficientIndex <= 0;
						exp_coefficientShifter <= exp_coefficientShifter_next;
					end else begin
						exp_coefficientIndex <= exp_coefficientIndex + 1;
					end
				end
				if (isExponential && exp_internalCounter >= exp_SectionLength) begin//start next section?
					// if (exp_coefficientIndex == 0) begin
						V0 <= {V0_atRampStart[data_size-1],V0_atRampStart} + DV - (DV>>exp_coefficientShifter);
					// end else begin
					// 	V0 <= {V0[data_size-1],V0} + exp_slope_delayed;
					// end
					// nDV <= {{time_size{step[data_size+1-1]}},step};
					exp_internalCounter <= 1;
				end else begin
					exp_internalCounter <= exp_internalCounter + 1;
				end
					nDV <= nDV + {{time_size{step[data_size+1-1]}},step};
			end
		end
	end
end




// ---------------------------------------------------------------------------------

//  System bus connection

always @(posedge clk)
if (reset) begin
	DVs <= 0;
	DTs <= 0;
	startValue <= 0;
	usedRamps <= 0;
	defaultValue <= 0;
	idleConfig <= 0;
	doesNextRampWaitForTriggers <= 0;
end else if (wen) begin
	if (addr==20'h100) {usedRamps, doesNextRampWaitForTriggers, idleConfig} <= wdata;
	if (addr==20'h104) {defaultValue, startValue} <= wdata;
	for(i = 0; i < nOfRamps; i = i + 1) begin
		if (addr==20'h108 + i * 8) DVs[(i+1)*(data_size+1) -1-:(data_size+1)] <= wdata;
		if (addr==20'h10C + i * 8) DTs[(i+1)*time_size -1-:time_size] <= wdata;
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

		if (addr==20'h100) rdata <= {usedRamps, doesNextRampWaitForTriggers, idleConfig};
		if (addr==20'h104) rdata <= {defaultValue, startValue};
		for(i = 0; i < nOfRamps; i = i + 1) begin
			if (addr==20'h108 + i * 8) rdata <= DVs[(i+1)*(data_size+1) -1-:(data_size+1)];
			if (addr==20'h10C + i * 8) rdata <= DTs[(i+1)*time_size -1-:time_size];
		end
	end
end

endmodule



/*

vsim work.ramp_withDivisionsAndExponential
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/*
force -freeze sim:/ramp_withDivisionsAndExponential/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/ramp_withDivisionsAndExponential/reset z1 0
force -freeze sim:/ramp_withDivisionsAndExponential/trigger z0 0
force -freeze sim:/ramp_withDivisionsAndExponential/DVs 36ae823 0
force -freeze sim:/ramp_withDivisionsAndExponential/DTs 068070 0
force -freeze sim:/ramp_withDivisionsAndExponential/startValue 0 0
force -freeze sim:/ramp_withDivisionsAndExponential/usedRamps 3 0
force -freeze sim:/ramp_withDivisionsAndExponential/defaultValue 0 0
force -freeze sim:/ramp_withDivisionsAndExponential/idleConfig 1 0
force -freeze sim:/ramp_withDivisionsAndExponential/doesNextRampWaitForTriggers 2 0
force -freeze sim:/ramp_withDivisionsAndExponential/exp_SectionLengths 030704 0
force -freeze sim:/ramp_withDivisionsAndExponential/isExponentials f 0
run
force -freeze sim:/ramp_withDivisionsAndExponential/reset 10 0
run
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 01 0
run
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 10 0
run 5000ps
run 5000ps
run 5000ps



force -freeze sim:/ramp_withDivisionsAndExponential/trigger 01 0
run
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 10 0
run 2000ps


*/

