    `timescale 1ns / 1ps
    //////////////////////////////////////////////////////////////////////////////////
    // Company: 
    // Engineer: 
    // 
    // Create Date: 16.07.2024 09:52:59
    // Design Name: 
    // Module Name: fastSwitcher
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
    

/*
implemented process:
optical tweezer turned off (by default its always on)
delay
PI pulse, to move the atoms to the excited state
delay
blast pulse, to push away the atoms that decayed to the ground state. The blast laser is one the fastSwitch ones, which is used for both processes
delay
tweezers turned on again
*/
    
module tweezer_pi_blast#(
    parameter maxSmallTimes = 255,
    parameter maxLongTimes = 2_000_000
)(
    input clk,
    input reset,
    input trigger,
    input [$clog2(maxLongTimes+1) -1:0] nOfPeriods_inactive_TweezerPi,
    input [$clog2(maxSmallTimes+1) -1:0] nOfPeriods_pi,
    input [$clog2(maxSmallTimes+1) -1:0] nOfPeriods_inactive_PiBlast,
    input [$clog2(maxSmallTimes+1) -1:0] nOfPeriods_blast,
    input [$clog2(maxSmallTimes+1) -1:0] nOfPeriods_inactive_BlastTweezer,
    output tweezer,
    output pi,
    output blast
);

	wire cleanTrigger;

	triggerCleaner#(
		.nOfInhibitionCycles(125)//1e-6s
	)tc(
		.clk	(clk),
		.reset	(reset),
		.in		(trigger),
		.out	(cleanTrigger)
	);
	localparam timingSize = $clog2(maxLongTimes+1);
	wire [(timingSize * 5) -1:0] allTimings;
	wire [3 * 5 -1:0] allValues;
	`define setTimingAndValue(time, value, index)							\
			assign allTimings[(index+1) * timingSize -1-:timingSize] = time;\
			assign allValues [(index+1) * 3 -1-:3] = value;
	`setTimingAndValue(nOfPeriods_inactive_TweezerPi, 	3'b000, 0)
	`setTimingAndValue(nOfPeriods_pi, 					3'b010, 1)
	`setTimingAndValue(nOfPeriods_inactive_PiBlast, 	3'b000, 2)
	`setTimingAndValue(nOfPeriods_blast, 				3'b001, 3)
	`setTimingAndValue(nOfPeriods_inactive_BlastTweezer,3'b000, 4)

	wire [2:0] defaultValue = 							3'b100;
	multiTimingDoubleFreqCounter#(
		.nOfTimings		(5),
		.nofOutputs		(3),
		.timingSizes	(timingSize)
	)mtdfc(
    	.clk					(clk),
    	.reset					(reset),
		.trigger				(cleanTrigger),
		.timings				(allTimings),
		.requestedOutputValues	(allValues),
		.defaultOutputValue		(defaultValue),
		.outputs				({tweezer, pi, blast})
	);
    
endmodule



/*
vsim work.tweezer_pi_blast
add wave -position insertpoint sim:/tweezer_pi_blast/*
add wave -position insertpoint sim:/tweezer_pi_blast/dfc/*
force -freeze sim:/tweezer_pi_blast/clk 1 0, 0 {50 ps} -r 100
force -freeze sim:/tweezer_pi_blast/reset z1 0
force -freeze sim:/tweezer_pi_blast/trigger z0 0
force -freeze sim:/tweezer_pi_blast/nOfPeriods_inactive_TweezerPi 8 0
force -freeze sim:/tweezer_pi_blast/nOfPeriods_pi 4 0
force -freeze sim:/tweezer_pi_blast/nOfPeriods_inactive_PiBlast 6 0
force -freeze sim:/tweezer_pi_blast/nOfPeriods_blast 4 0
force -freeze sim:/tweezer_pi_blast/nOfPeriods_inactive_BlastTweezer 7 0
run
run
run
force -freeze sim:/tweezer_pi_blast/reset 00 0
run
run
force -freeze sim:/tweezer_pi_blast/trigger 01 0
run
force -freeze sim:/tweezer_pi_blast/trigger 0 0
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