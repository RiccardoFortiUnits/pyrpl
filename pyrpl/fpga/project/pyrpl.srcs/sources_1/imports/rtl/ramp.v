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

localparam bitShift_size = $clog2(data_size+1);
reg [nOfRamps -1:0] exp_directions;//0: negative exponential (c^-kt), 1: positive exponential
reg [nOfRamps*bitShift_size -1:0] exp_initialShifts;//0: negative exponential (c^-kt), 1: positive exponential

reg [nOfRamps -1:0] isExponentials;
localparam section_size = time_size;//todo put a smaller register size, time_size is a bit too big
localparam coefficientSize = data_size;//todo corretto?
reg [section_size*nOfRamps -1:0] exp_SectionLengths;

integer i;
/*
//this code calculates the values of the halfExponents. Sadly, Vivado is a little crybaby (to not say something else), and it cannot do a few calculations by itself... 
reg [coefficientSize*nOfStepsBeforeHalfing -1:0] halfExponents;
real x,c;
initial begin
	c = $pow(0.5, 1.0 / real'(nOfStepsBeforeHalfing));
	for (i = 0; i < nOfStepsBeforeHalfing; i=i+1) begin
		x = $pow(c, i) * (c-1);
		halfExponents[(i+1)*coefficientSize -1-:coefficientSize] = $rtoi(-x * (1<<(coefficientSize)) + 0.5);
	end
end
/*/
wire [coefficientSize*nOfStepsBeforeHalfing -1:0] halfExponents = 56'h18387332240a2f;
//*/

reg isRunning;//will be 0 when waiting for a trigger, even if we're in the middle of the sequence (if the current bit in doesNextRampWaitForTrigger is 1)


localparam delay_expShifter = 1;//green to cyan
localparam delay_ns_sum = 1;//cyan to blue
localparam delay_divisor = 20;//blue to purple

localparam delay_1 = delay_expShifter;
localparam delay_2 = delay_ns_sum;
localparam delay_3 = delay_divisor;
localparam delay_12 = delay_1 + delay_2;
localparam delay_23 = delay_2 + delay_3;
localparam delay_123 = delay_12 + delay_3;


`define delayedRegister(registerSize, inputName, outputName, delayCycles) 			\
	reg [registerSize -1:0] inputName;													\
	wire [registerSize -1:0] outputName;												\
	delayer#(registerSize, delayCycles) delay_``inputName(clk,reset, inputName, outputName);

`define delayedWire(registerSize, inputName, outputName, delayCycles, assignedValue)\
	wire [registerSize -1:0] inputName = assignedValue;									\
	wire [registerSize -1:0] outputName;												\
	delayer#(registerSize, delayCycles) delay_``inputName(clk,reset, inputName, outputName);

`define delayedWire_noAssignment(registerSize, inputName, outputName, delayCycles)	\
	wire [registerSize -1:0] inputName;													\
	wire [registerSize -1:0] outputName;												\
	delayer#(registerSize, delayCycles) delay_``inputName(clk,reset, inputName, outputName);

`define delayedIntermediatedRegister(registerSize, inputName, outputName, intermediateIndexName, delayCycles, intermediateDelay) 			\
	reg [registerSize -1:0] inputName;													\
	wire [registerSize -1:0] outputName;												\
	reg intermediateIndexName;												\
	delayer_withIntermediateSet#(registerSize, delayCycles, intermediateDelay) delay_``inputName(clk,reset, inputName, intermediateIndexName, outputName);


reg [$clog2(nOfRamps+1) -1:0] currentRamp;
reg [time_size -1:0] n;//main counter. We'll go to the next ramp when n == DT
reg [section_size -1:0] m;//internal counter of the exponential ramp. resets when m==exp_SectionLength
reg reversed;

wire [1:0] modifiedIdleConfig = reversed ? c_start : idleConfig;
wire needToReverse = idleConfig == c_inverseRamp && currentRamp == usedRamps - 1;
wire isLastRamp = reversed || needToReverse ? currentRamp == 0 : currentRamp == usedRamps - 1;
wire [$clog2(nOfRamps+1) -1:0] nextRamp = currentRamp + (
											reversed ?
												-1 : 
												needToReverse ?
													0 :
													1
											);

//green lines
reg [$clog2(nOfStepsBeforeHalfing+1) -1:0] exp_coeffIndex;
wire [coefficientSize -1:0] exp_coeff = halfExponents[(exp_coeffIndex+1)*coefficientSize -1-:coefficientSize];
wire [data_size+1 -1:0] unreversedDV = DVs[(currentRamp+1)*(data_size+1) -1-:(data_size+1)];
wire [data_size+1 -1:0] next_unreversedDV = DVs[(nextRamp+1)*(data_size+1) -1-:(data_size+1)];
`delayedWire(data_size+1, DV_forExpMult, DV, delay_1, reversed ? - unreversedDV : unreversedDV)// wire[data_size+1 -1:0] DV = DVs[(currentRamp+1)*(data_size+1) -1-:(data_size+1)];
wire [data_size+1 -1:0] next_DV = reversed ? - next_unreversedDV : next_unreversedDV;
wire [bitShift_size -1:0] exp_initialShift = exp_initialShifts[(currentRamp+1)*bitShift_size -1-:bitShift_size];
wire [bitShift_size -1:0] exp_nextInitialShift = exp_initialShifts[(nextRamp+1)*bitShift_size -1-:bitShift_size];
`delayedWire(1, exp_direction, exp_direction_forShift, delay_1, exp_directions[currentRamp])
wire exp_nextdirection = exp_directions[nextRamp];
wire [$clog2(nOfStepsBeforeHalfing+1) -1:0] exp_startingCoeffIndex = exp_direction ? nOfStepsBeforeHalfing - 1 : 0;

`delayedRegister(bitShift_size, exp_bitShift, exp_bitShift_forShift, delay_1)// reg[bitShift_size -1:0] exp_bitShift;
`delayedWire(time_size, DT_forEndOfRamp, DT, delay_12, DTs[(currentRamp+1)*time_size -1-:time_size])//wire[time_size -1:0] DT = DTs[(currentRamp_blue+1)*time_size -1-:time_size];
`delayedWire(1, endOfRamp, endOfRamp_cyan, delay_1, n==DT_forEndOfRamp)	//current ramp ended?  //wire endOfRamp = (doesNextRampWaitForTrigger && cleanTrigger	) ||//should we start prematurely the next ramp?\				 (					n==DT						);//current ramp ended?
`delayedWire($clog2(nOfRamps+1), currentRamp_green, currentRamp_cyan, delay_1, currentRamp)
`delayedRegister(data_size, overrideV0, overrideV0_blue, delay_123-2)
`delayedRegister(2, selectWhichV0, selectWhichV0_blue, delay_123-2)
localparam swv0_noChange=1,swv0_outputValue=2,swv0_overrideValue=3;

//cyan lines
wire [coefficientSize+data_size+1 -1:0] exp_s_unshifted;
wire [data_size+1 -1:0] exp_s;
`delayedWire(1, isExponential, isExponential_forDenomitatorChoice, delay_2, isExponentials[currentRamp_cyan])
wire [data_size+1 -1:0] s = isExponential ? exp_s : DV;
`delayedWire($clog2(nOfRamps+1), currentRamp_cyan_copy, currentRamp_blue, delay_2, currentRamp_cyan)
reg override_ns;
reg [time_size+data_size+1 -1:0] newValueFor_ns;


//blue lines
wire[section_size -1:0] exp_SectionLength = exp_SectionLengths[(currentRamp_blue+1)*time_size -1-:time_size];
wire[time_size -1:0] denominator = isExponential_forDenomitatorChoice ? exp_SectionLength : DT - 1;
reg [time_size+data_size+1 -1:0] ns;//will store n*s

//purple lines
wire [data_size+1 -1:0] mt;
reg [data_size -1:0] V0;





wire doesNextRampWaitForTrigger = doesNextRampWaitForTriggers[currentRamp];//this bit tells us if the next ramp wants a trigger, not the current one

// wire[data_size+1 -1:0] DV_next = DVs[(currentRamp+2)*(data_size+1) -1-:(data_size+1)];
// wire [data_size+1 -1:0] s_next = isExponential ? exp_s : DV_next;//exp_s is already updated to the next value

wire triggerReceived = cleanTrigger && usedRamps;
wire exp_nextSectionLength = m >= exp_SectionLength;
wire exp_nextShift = exp_direction ? (exp_coeffIndex == 0) : (exp_coeffIndex == nOfStepsBeforeHalfing - 1);

clocked_FractionalMultiplier #(
  .A_WIDTH			(data_size+1),
  .B_WIDTH			(coefficientSize),//exp_coeff is unsigned, but its MSB is always 0 (unless nOfStepsBeforeHalfing=1)
  .OUTPUT_WIDTH		(coefficientSize+data_size+1),
  .FRAC_BITS_A		(data_size),
  .FRAC_BITS_B		(coefficientSize),
  .FRAC_BITS_OUT	(data_size+coefficientSize),
  .areSignalsSigned (1)
) generate_expSlope (
  .clk(clk),
  .a(DV_forExpMult),
  .b(exp_coeff),
  .result(exp_s_unshifted)
);

wire calculateNextCoefficient = m == 1;
reg resetShifter;
fixedSumCoefficientShifter_oneAtATime #(
	.coefficientSize	(coefficientSize+data_size+1),
	.nOfCoefficients	(nOfStepsBeforeHalfing)
) shift_exp_coeff (
	.clk						(clk),
	.reset						(reset | resetShifter),
	.triggerNextCoeff			(calculateNextCoefficient),
	.currentCoefficient			(exp_s_unshifted),
	.areCoefficientsDecreasing	(exp_direction_forShift),
	.shift						({1'b0, exp_bitShift_forShift} + coefficientSize),
	.shiftedCoefficient			(exp_s)
);


fractionalDivider #(//dividers take 5 clock cycles to generate the output
	.A_WIDTH			(time_size+data_size+1),
	.B_WIDTH			(time_size+1),
	.OUTPUT_WIDTH		(data_size+1),
	.FRAC_BITS_A		(data_size),
	.FRAC_BITS_B		(0),
	.FRAC_BITS_OUT		(data_size),
	.areSignalsSigned	(1),// numerator can be negative
	.saturateOutput     (0)
) create_mt(
	.clk		(clk),
	.reset		(reset),
	.a			(ns),
	.b			({1'b0, denominator ? denominator : -1}),//let's avoid divisions by 0, though they should only occurr during reset (I hope)
	.result		(mt)
);


// wire [time_size+data_size+1 -1:0] ns_startValue = 0;//{{time_size{s[data_size+1-1]}},s}



always @(posedge clk)begin
	if(reset)begin
		isRunning <= 0;
		ns <= 0;
		V0 <= 0;
		n <= 0;
		m <= 0;
		exp_bitShift <= 0;
		currentRamp <= 0;
		out <= 0;
		exp_coeffIndex <= 0;
		resetShifter <= 0;
		newValueFor_ns <= 0;
		override_ns <= 1;
		ns <= 0;
		reversed <= 0;
		selectWhichV0 <= 0;
		overrideV0 <= 0;
	end else begin
		out <= {V0[data_size-1], V0} + mt;
		ns <= override_ns ? newValueFor_ns : ns + {{time_size{s[data_size+1-1]}},s};
		case (selectWhichV0_blue)
			swv0_noChange: V0 <= V0;
			swv0_outputValue: V0 <= {V0[data_size-1], V0} + mt;
			swv0_overrideValue: V0 <= overrideV0_blue; 
			default: V0 <= 0;
		endcase
		if(!isRunning)begin//waiting for a trigger?
			if(triggerReceived)begin
				isRunning <= 1;
				n <= 1;
				m <= 1;
				newValueFor_ns <= 0;
				override_ns <= 1;
				if(currentRamp == 0 && !reversed)begin//are we waiting to start the sequence?
					//add exception for inverseRamp, and save start value
					selectWhichV0 <= swv0_overrideValue;
					overrideV0 <= startValue;
					exp_bitShift <= exp_initialShift;
				end
				resetShifter <= 1;
			end
		end else begin
			if(endOfRamp)begin
				exp_bitShift <= exp_nextInitialShift;
				exp_coeffIndex <= exp_nextdirection ? nOfStepsBeforeHalfing - 1 : 0;
				resetShifter <= 1;
				override_ns <= 1;
				newValueFor_ns <= 0;
				if(needToReverse)begin
					reversed <= 1;
				end
				if(isLastRamp)begin//last ramp?
					currentRamp <= 0;
					isRunning <= 0;
					n <= 0;
					m <= 0;
					case(modifiedIdleConfig)
						c_defaultValue:	begin	selectWhichV0 <= swv0_overrideValue; overrideV0 <= defaultValue;end
						c_start:		begin	selectWhichV0 <= swv0_overrideValue; overrideV0 <= startValue;end
						c_current:		begin	selectWhichV0 <= swv0_outputValue;end
						default: begin end
					endcase
				end else begin
					selectWhichV0 <= swv0_outputValue;
					currentRamp <= nextRamp;
					if(doesNextRampWaitForTrigger)begin//do we have to wait for a new trigger?
						isRunning <= 0;
						n <= 0;
						m <= 0;
					end else begin
						isRunning <= 1;
						n <= 1;
						m <= 1;
					end
				end
			end else begin
				//let's continue the ramp
				n <= n + 1;
				override_ns <= 0;
				selectWhichV0 <= swv0_noChange;
				if (exp_nextSectionLength) begin
					m <= 1;
					if (exp_nextShift) begin
						exp_coeffIndex <= exp_startingCoeffIndex;
						exp_bitShift <= exp_direction ? 
											(exp_bitShift > 0 ?
												exp_bitShift - 1 : 
												exp_bitShift)
											:
											(exp_bitShift < data_size ?
												exp_bitShift + 1 :
												exp_bitShift);
					end else begin
						exp_coeffIndex <= exp_coeffIndex + (exp_direction ? -1 : 1);
					end
				end else begin
					m <= m + 1;
				end
				resetShifter <= 0;
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
	isExponentials <= 0;
	exp_SectionLengths <= 0;

	exp_directions <= 0;
	exp_initialShifts <= 0;
end else if (wen) begin
	if (addr==20'h100) {isExponentials, usedRamps, doesNextRampWaitForTriggers, idleConfig} <= wdata;
	if (addr==20'h104) {defaultValue, startValue} <= wdata;
	for(i = 0; i < nOfRamps; i = i + 1) begin
		if (addr==20'h108 + i * 12) {exp_initialShifts[(i+1)*bitShift_size -1-:bitShift_size], exp_directions[i], DVs[(i+1)*(data_size+1) -1-:(data_size+1)]} <= wdata;
		if (addr==20'h10C + i * 12) DTs[(i+1)*time_size -1-:time_size] <= wdata;
		if (addr==20'h110 + i * 12) exp_SectionLengths[(i+1)*section_size -1-:time_size] <= wdata;
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

		if (addr==20'h100) rdata <= {isExponentials, usedRamps, doesNextRampWaitForTriggers, idleConfig};
		if (addr==20'h104) rdata <= {defaultValue, startValue};
		for(i = 0; i < nOfRamps; i = i + 1) begin
			if (addr==20'h108 + i * 12) rdata <= {exp_initialShifts[(i+1)*bitShift_size -1-:bitShift_size], exp_directions[i], DVs[(i+1)*(data_size+1) -1-:(data_size+1)]};
			if (addr==20'h10C + i * 12) rdata <= DTs[(i+1)*time_size -1-:time_size];
			if (addr==20'h110 + i * 12) rdata <= exp_SectionLengths[(i+1)*section_size -1-:time_size];
		end
	end
end

endmodule



/*


vsim work.ramp_withDivisionsAndExponential
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/clk 
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/out
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/V0_forOutSum
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/V0
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/ns
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/mt
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/s
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/s_next
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/exp_coeff
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/exp_bitShift
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/*
force -freeze sim:/ramp_withDivisionsAndExponential/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/ramp_withDivisionsAndExponential/reset z1 0
force -freeze sim:/ramp_withDivisionsAndExponential/trigger z0 0
force -freeze sim:/ramp_withDivisionsAndExponential/DVs cfb6ae823 0
force -freeze sim:/ramp_withDivisionsAndExponential/DTs 25060371 0
force -freeze sim:/ramp_withDivisionsAndExponential/startValue 0 0
force -freeze sim:/ramp_withDivisionsAndExponential/usedRamps 4 0
force -freeze sim:/ramp_withDivisionsAndExponential/defaultValue aa 0
force -freeze sim:/ramp_withDivisionsAndExponential/idleConfig 2 0
force -freeze sim:/ramp_withDivisionsAndExponential/doesNextRampWaitForTriggers 0 0
force -freeze sim:/ramp_withDivisionsAndExponential/exp_SectionLengths 10080404 0
force -freeze sim:/ramp_withDivisionsAndExponential/isExponentials 0 0
force -freeze sim:/ramp_withDivisionsAndExponential/exp_directions 1 0
force -freeze sim:/ramp_withDivisionsAndExponential/exp_initialShifts 0205 0
run 500ps
force -freeze sim:/ramp_withDivisionsAndExponential/reset 10 0
run 500ps
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 01 0
run
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 10 0
run 80000ps

vsim work.ramp_withDivisionsAndExponential
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/clk 
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/out
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/V0_forOutSum
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/V0
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/ns
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/mt
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/s
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/s_next
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/exp_coeff
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/exp_bitShift
add wave -position insertpoint sim:/ramp_withDivisionsAndExponential/*
force -freeze sim:/ramp_withDivisionsAndExponential/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/ramp_withDivisionsAndExponential/reset z1 0
force -freeze sim:/ramp_withDivisionsAndExponential/trigger z0 0
force -freeze sim:/ramp_withDivisionsAndExponential/DVs e01078040 0
force -freeze sim:/ramp_withDivisionsAndExponential/DTs 60606060 0
force -freeze sim:/ramp_withDivisionsAndExponential/startValue 0 0
force -freeze sim:/ramp_withDivisionsAndExponential/usedRamps 4 0
force -freeze sim:/ramp_withDivisionsAndExponential/defaultValue aa 0
force -freeze sim:/ramp_withDivisionsAndExponential/idleConfig 2 0
force -freeze sim:/ramp_withDivisionsAndExponential/doesNextRampWaitForTriggers 0 0
force -freeze sim:/ramp_withDivisionsAndExponential/exp_SectionLengths 03030303 0
force -freeze sim:/ramp_withDivisionsAndExponential/isExponentials f 0
force -freeze sim:/ramp_withDivisionsAndExponential/exp_directions c 0
force -freeze sim:/ramp_withDivisionsAndExponential/exp_initialShifts 7700 0
run 500ps
force -freeze sim:/ramp_withDivisionsAndExponential/reset 10 0
run 500ps
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 01 0
run
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 10 0
run 80000ps



force -freeze sim:/ramp_withDivisionsAndExponential/isExponentials 3 0
run 500ps
force -freeze sim:/ramp_withDivisionsAndExponential/reset 10 0
run 500ps
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 01 0
run
force -freeze sim:/ramp_withDivisionsAndExponential/trigger 10 0
run 20000ps

*/




module ramp_easy#(
	parameter nOfRamps = 4,
	parameter data_size = 8,
	parameter time_size = 8
)(
	input clk,
	input superFastClk,//we'll remove this in the final version
	input reset,
	input trigger,
	
	output reg [data_size-1:0] out,

	input [(data_size+1)*nOfRamps -1:0] DVs,//needs an extra bit, because you can have a ramp that does the entire range, and it can also be negative
	input [time_size*nOfRamps -1:0] DTs,
	input [data_size -1:0] startValue//V0
);

reg isRunning;//will be 0 when waiting for a trigger

reg [$clog2(nOfRamps) -1:0] currentRamp;// i
wire [time_size -1:0] DT = DTs[(currentRamp+1)*time_size -1-:time_size];
wire [data_size+1 -1:0] DV = DVs[(currentRamp+1)*(data_size+1) -1-:(data_size+1)];

reg [time_size -1:0] n;//main counter. We'll go to the next ramp when n == DT
reg [time_size+data_size+1 -1:0] DVn;//will store n*DV
reg [data_size-1:0] V0;//=startValue + DV[0] + DV[1] + ... + DV[i-1]

//for the division, I have a module that already does all the calculations and fixed-point register shifts. The actual implementation is not that important now
wire [data_size+1 -1:0] DVn_DT;
fractionalDivider #(//this divider takes 5 clock cycles to generate the output
	.A_WIDTH			(time_size+data_size+1),
	.B_WIDTH			(time_size+1),
	.OUTPUT_WIDTH		(data_size+1),
	.FRAC_BITS_A		(data_size),
	.FRAC_BITS_B		(0),
	.FRAC_BITS_OUT		(data_size),
	.areSignalsSigned	(1),// numerator can be negative
	.saturateOutput     (0)
) divide(
	.clk		(superFastClk),
	.reset		(reset),
	.a			(DVn),
	.b			({1'b0, DT ? DT : -1}),//let's avoid divisions by 0, and let's add a 0 bit to avoid the number being treated as negative
	.result		(DVn_DT)
);

always @(posedge clk)begin
	if(reset)begin
		isRunning <= 0;
		DVn <= 0;
		V0 <= 0;
		n <= 0;
		currentRamp <= 0;
		out <= 0;
	end else begin
		out <= {V0[data_size-1], V0} + DVn_DT;//just a bit padding for V0

		if(!isRunning)begin//waiting for a trigger?
			if(trigger)begin//trigger recieved?
				isRunning <= 1;
				DVn <= {{time_size{DV[data_size+1-1]}},DV};//just a bit padding
			end else begin//are we waiting to start the sequence?
				V0 <= startValue;
			end
		end else begin
			if(n==DT-1)begin//current ramp ended?
				n <= 0;
				DVn <= 0;
				V0 <= {V0[data_size-1],V0} + DV;//update the offset, so that the next ramp starts from the last value of the previous one
				if(currentRamp == nOfRamps - 1)begin//last ramp?
					currentRamp <= 0;
					isRunning <= 0;
				end else begin
					currentRamp <= currentRamp + 1;
				end
			end else begin
				//let's continue the ramp
				n <= n + 1;
				DVn <= DVn + {{time_size{DV[data_size+1-1]}},DV};
			end
		end
	end
end
endmodule

/*
vsim work.ramp_easy
add wave -position insertpoint sim:/ramp_easy/*
force -freeze sim:/ramp_easy/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/ramp_easy/superFastClk 1 0, 0 {5 ps} -r 10
force -freeze sim:/ramp_easy/reset 1 0
force -freeze sim:/ramp_easy/trigger z0 0
force -freeze sim:/ramp_easy/DVs cfb6ae823 0
force -freeze sim:/ramp_easy/DTs 04081305 0
force -freeze sim:/ramp_easy/startValue f0 0
run 100ps
force -freeze sim:/ramp_easy/reset 0 0
run 100ps
force -freeze sim:/ramp_easy/trigger 1 0
run 100ps
force -freeze sim:/ramp_easy/trigger 0 0
run 4ns
noforce sim:/ramp_easy/superFastClk
force -freeze sim:/ramp_easy/superFastClk  1 0, 0 {50 ps} -r 100
force -freeze sim:/ramp_easy/reset 1 0
run 100ps
force -freeze sim:/ramp_easy/reset 0 0
run 100ps
force -freeze sim:/ramp_easy/trigger 1 0
run 100ps
force -freeze sim:/ramp_easy/trigger 0 0
run 5ns

*/


module ramp_correctedDelays#(
	parameter nOfRamps = 4,
	parameter data_size = 8,
	parameter time_size = 8
)(
	input clk,
	// input superFastClk,//not needed anymore
	input reset,
	input trigger,
	
	output reg [data_size-1:0] out,

	input [(data_size+1)*nOfRamps -1:0] DVs,//needs an extra bit, because you can have a ramp that does the entire range, and it can also be negative
	input [time_size*nOfRamps -1:0] DTs,
	input [data_size -1:0] startValue//V0
);

reg isRunning;//will be 0 when waiting for a trigger

reg [$clog2(nOfRamps) -1:0] currentRamp;// i
wire [$clog2(nOfRamps) -1:0] currentRamp_forSelectingDT;// i
delayer#($clog2(nOfRamps), 1) delay_currentRamp(clk,reset, currentRamp, currentRamp_forSelectingDT);

wire [time_size -1:0] DT = DTs[(currentRamp_forSelectingDT+1)*time_size -1-:time_size];
wire [data_size+1 -1:0] DV = DVs[(currentRamp+1)*(data_size+1) -1-:(data_size+1)];

reg [time_size -1:0] n;//main counter. We'll go to the next ramp when n == DT
reg [time_size+data_size+1 -1:0] DVn;//will store n*DV
reg [data_size-1:0] V0;//=startValue + DV[0] + DV[1] + ... + DV[i-1]
wire [data_size-1:0] V0_forFinalSum;//=startValue + DV[0] + DV[1] + ... + DV[i-1]
delayer#(data_size, 5) delay_V0(clk,reset, V0, V0_forFinalSum);

//for the division, I have a module that already does all the calculations and fixed-point register shifts. The actual implementation is not that important now
wire [data_size+1 -1:0] DVn_DT;
fractionalDivider #(//this divider takes 5 clock cycles to generate the output
	.A_WIDTH			(time_size+data_size+1),
	.B_WIDTH			(time_size+1),
	.OUTPUT_WIDTH		(data_size+1),
	.FRAC_BITS_A		(data_size),
	.FRAC_BITS_B		(0),
	.FRAC_BITS_OUT		(data_size),
	.areSignalsSigned	(1),// numerator can be negative
	.saturateOutput     (0)
) divide(
	.clk		(clk),
	.reset		(reset),
	.a			(DVn),
	.b			({1'b0, DT-1 ? DT-1 : -1}),//let's avoid divisions by 0, and let's add a 0 bit to avoid the number being treated as negative
	.result		(DVn_DT)
);

always @(posedge clk)begin
	if(reset)begin
		isRunning <= 0;
		DVn <= 0;
		V0 <= 0;
		n <= 0;
		currentRamp <= 0;
		out <= 0;
	end else begin
		out <= {V0_forFinalSum[data_size-1], V0_forFinalSum} + DVn_DT;//just a bit padding for V0_forFinalSum

		if(!isRunning)begin//waiting for a trigger?
			if(trigger)begin//trigger recieved?
				isRunning <= 1;
				DVn <= {{time_size{DV[data_size+1-1]}},DV};//just a bit padding
			end else begin//are we waiting to start the sequence?
				V0 <= startValue;
			end
		end else begin
			if(n==DT-1)begin//current ramp ended?
				n <= 0;
				DVn <= 0;
				V0 <= {V0[data_size-1],V0} + DV;//update the offset, so that the next ramp starts from the last value of the previous one
				if(currentRamp == nOfRamps - 1)begin//last ramp?
					currentRamp <= 0;
					isRunning <= 0;
				end else begin
					currentRamp <= currentRamp + 1;
				end
			end else begin
				//let's continue the ramp
				n <= n + 1;
				DVn <= DVn + {{time_size{DV[data_size+1-1]}},DV};
			end
		end
	end
end
endmodule

/*

vsim work.ramp_correctedDelays
add wave -position insertpoint sim:/ramp_correctedDelays/*
force -freeze sim:/ramp_correctedDelays/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/ramp_correctedDelays/reset 1 0
force -freeze sim:/ramp_correctedDelays/trigger z0 0
force -freeze sim:/ramp_correctedDelays/DVs cfb6ae823 0
force -freeze sim:/ramp_correctedDelays/DTs 04081305 0
force -freeze sim:/ramp_correctedDelays/startValue f0 0
run 100ps
force -freeze sim:/ramp_correctedDelays/reset 0 0
run 100ps
force -freeze sim:/ramp_correctedDelays/trigger 1 0
run 100ps
force -freeze sim:/ramp_correctedDelays/trigger 0 0
run 4ns

*/