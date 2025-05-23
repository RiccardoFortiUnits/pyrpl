/**
 * $Id: red_pitaya_scope.v 965 2014-01-24 13:39:56Z matej.oblak $
 *
 * @brief Red Pitaya oscilloscope application, used for capturing ADC data
 *        into BRAMs, which can be later read by SW.
 *
 * @Author Matej Oblak
 *
 * (c) Red Pitaya  http://www.redpitaya.com
 *
 * This part of code is written in Verilog hardware description language (HDL).
 * Please visit http://en.wikipedia.org/wiki/Verilog
 * for more details on the language used herein.
 */
/*
###############################################################################
#    pyrpl - DSP servo controller for quantum optics with the RedPitaya
#    Copyright (C) 2014-2016  Leonhard Neuhaus  (neuhaus@spectro.jussieu.fr)
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
############################################################################### 
*/

/**
 * GENERAL DESCRIPTION:
 *
 * This is simple data aquisition module, primerly used for scilloscope 
 * application. It consists from three main parts.
 *
 *
 *                /--------\      /-----------\            /-----\
 *   ADC CHA ---> | DFILT1 | ---> | AVG & DEC | ---------> | BUF | --->  SW
 *                \--------/      \-----------/     |      \-----/
 *                                                  ˇ         ^
 *                                              /------\      |
 *   ext trigger -----------------------------> | TRIG | -----+
 *                                              \------/      |
 *                                                  ^         ˇ
 *                /--------\      /-----------\     |      /-----\
 *   ADC CHB ---> | DFILT1 | ---> | AVG & DEC | ---------> | BUF | --->  SW
 *                \--------/      \-----------/            \-----/ 
 *
 *
 * Input data is optionaly averaged and decimated via average filter.
 *
 * Trigger section makes triggers from input ADC data or external digital 
 * signal. To make trigger from analog signal schmitt trigger is used, external
 * trigger goes first over debouncer, which is separate for pos. and neg. edge.
 *
 * Data capture buffer is realized with BRAM. Writing into ram is done with 
 * arm/trig logic. With adc_arm_do signal (SW) writing is enabled, this is active
 * until trigger arrives and adc_dly_cnt counts to zero. Value adc_wp_trig
 * serves as pointer which shows when trigger arrived. This is used to show
 * pre-trigger data.
 * 
 */

module red_pitaya_scope #(
  parameter RSZ = 14  // RAM size 2^RSZ
)(

   // ADC
   input                 adc_clk_i       ,  // ADC clock
   input                 adc_rstn_i      ,  // ADC reset - active low
   input      [ 14-1: 0] adc_a_i         ,  // ADC data CHA
   input      [ 14-1: 0] adc_b_i         ,  // ADC data CHB
   // trigger sources
   input                 trig_ext_i      ,  // external trigger
   input      [  2-1: 0] trig_asg_i      ,  // ASG trigger
   input                 trig_dsp_i      ,  // DSP module trigger
   output                trig_scope_o    ,  // copy of scope trigger

   // AXI0 master
   output                axi0_clk_o      ,  // global clock
   output                axi0_rstn_o     ,  // global reset
   output     [ 32-1: 0] axi0_waddr_o    ,  // system write address
   output     [ 64-1: 0] axi0_wdata_o    ,  // system write data
   output     [  8-1: 0] axi0_wsel_o     ,  // system write byte select
   output                axi0_wvalid_o   ,  // system write data valid
   output     [  4-1: 0] axi0_wlen_o     ,  // system write burst length
   output                axi0_wfixed_o   ,  // system write burst type (fixed / incremental)
   input                 axi0_werr_i     ,  // system write error
   input                 axi0_wrdy_i     ,  // system write ready

   // AXI1 master
   output                axi1_clk_o      ,  // global clock
   output                axi1_rstn_o     ,  // global reset
   output     [ 32-1: 0] axi1_waddr_o    ,  // system write address
   output     [ 64-1: 0] axi1_wdata_o    ,  // system write data
   output     [  8-1: 0] axi1_wsel_o     ,  // system write byte select
   output                axi1_wvalid_o   ,  // system write data valid
   output     [  4-1: 0] axi1_wlen_o     ,  // system write burst length
   output                axi1_wfixed_o   ,  // system write burst type (fixed / incremental)
   input                 axi1_werr_i     ,  // system write error
   input                 axi1_wrdy_i     ,  // system write ready

   // System bus
   input      [ 32-1: 0] sys_addr      ,  // bus saddress
   input      [ 32-1: 0] sys_wdata     ,  // bus write data
   input      [  4-1: 0] sys_sel       ,  // bus write byte select
   input                 sys_wen       ,  // bus write enable
   input                 sys_ren       ,  // bus read enable
   output reg [ 32-1: 0] sys_rdata     ,  // bus read data
   output reg            sys_err       ,  // bus error indicator
   output reg            sys_ack       ,   // bus acknowledge signal

   input      [RSZ -1:0] real_adc_a_i, // for the peak detection, let's always use the actual ADC signals (otherwise we run out of signals to trigger/show)
   input      [RSZ -1:0] real_adc_b_i,
   output     [RSZ -1:0] peak_a,
   output     [RSZ -1:0]  peak_a_index,
   output peak_a_valid,
   output     [RSZ -1:0] peak_b,
   output     [RSZ -1:0]  peak_b_index,
   output peak_b_valid,
   output     [RSZ -1:0] peak_c,
   output     [RSZ -1:0]  peak_c_index,
   output peak_c_valid

);

reg             adc_arm_do   ;
reg             adc_rst_do   ;

// input filter is disabled

//---------------------------------------------------------------------------------
//  Input filtering

wire [ 14-1: 0] adc_a_filt_in  ;
wire [ 14-1: 0] adc_a_filt_out ;
wire [ 14-1: 0] adc_b_filt_in  ;
wire [ 14-1: 0] adc_b_filt_out ;
/*
reg  [ 18-1: 0] set_a_filt_aa  ;
reg  [ 25-1: 0] set_a_filt_bb  ;
reg  [ 25-1: 0] set_a_filt_kk  ;
reg  [ 25-1: 0] set_a_filt_pp  ;
reg  [ 18-1: 0] set_b_filt_aa  ;
reg  [ 25-1: 0] set_b_filt_bb  ;
reg  [ 25-1: 0] set_b_filt_kk  ;
reg  [ 25-1: 0] set_b_filt_pp  ;
*/


// bypass the filtering for the scope in order to spare the DSP slices for other stuff, 
// since we never look at signals close to nyquist
assign adc_a_filt_in = adc_a_i ;
assign adc_b_filt_in = adc_b_i ;
assign adc_a_filt_out = adc_a_filt_in;
assign adc_b_filt_out = adc_b_filt_in;

/*
red_pitaya_dfilt1 i_dfilt1_cha (
   // ADC
  .adc_clk_i   ( adc_clk_i       ),  // ADC clock
  .adc_rstn_i  ( adc_rstn_i      ),  // ADC reset - active low
  .adc_dat_i   ( adc_a_filt_in   ),  // ADC data
  .adc_dat_o   ( adc_a_filt_out  ),  // ADC data
   // configuration
  .cfg_aa_i    ( set_a_filt_aa   ),  // config AA coefficient
  .cfg_bb_i    ( set_a_filt_bb   ),  // config BB coefficient
  .cfg_kk_i    ( set_a_filt_kk   ),  // config KK coefficient
  .cfg_pp_i    ( set_a_filt_pp   )   // config PP coefficient
);

red_pitaya_dfilt1 i_dfilt1_chb (
   // ADC
  .adc_clk_i   ( adc_clk_i       ),  // ADC clock
  .adc_rstn_i  ( adc_rstn_i      ),  // ADC reset - active low
  .adc_dat_i   ( adc_b_filt_in   ),  // ADC data
  .adc_dat_o   ( adc_b_filt_out  ),  // ADC data
   // configuration
  .cfg_aa_i    ( set_b_filt_aa   ),  // config AA coefficient
  .cfg_bb_i    ( set_b_filt_bb   ),  // config BB coefficient
  .cfg_kk_i    ( set_b_filt_kk   ),  // config KK coefficient
  .cfg_pp_i    ( set_b_filt_pp   )   // config PP coefficient
);
*/
//---------------------------------------------------------------------------------
//  Decimate input data

reg  [ 14-1: 0] adc_a_dat     ;
reg  [ 14-1: 0] adc_b_dat     ;
reg  [ 14-1: 0] real_adc_a_dat;
reg  [ 14-1: 0] real_adc_b_dat;
reg  [ 32-1: 0] adc_a_sum     ;
reg  [ 32-1: 0] adc_b_sum     ;
reg  [ 32-1: 0] real_adc_a_sum;
reg  [ 32-1: 0] real_adc_b_sum;
reg  [ 17-1: 0] set_dec       ;
reg  [ 17-1: 0] adc_dec_cnt   ;
reg             set_avg_en    ;
reg             adc_dv        ;

always @(posedge adc_clk_i)
if (adc_rstn_i == 1'b0) begin
   adc_a_sum   <= 32'h0 ; real_adc_a_sum   <= 32'h0 ;
   adc_b_sum   <= 32'h0 ; real_adc_b_sum   <= 32'h0 ;
   adc_dec_cnt <= 17'h0 ;
   adc_dv      <=  1'b0 ;
end else begin
   if ((adc_dec_cnt >= set_dec) || adc_arm_do) begin // start again or arm
      adc_dec_cnt <= 17'h1                   ;
      adc_a_sum   <= $signed(adc_a_filt_out) ;
      adc_b_sum   <= $signed(adc_b_filt_out) ;
      real_adc_a_sum   <= $signed(real_adc_a_i) ;
      real_adc_b_sum   <= $signed(real_adc_b_i) ;
   end else begin
      adc_dec_cnt <= adc_dec_cnt + 17'h1 ;
      adc_a_sum   <= $signed(adc_a_sum) + $signed(adc_a_filt_out) ;
      adc_b_sum   <= $signed(adc_b_sum) + $signed(adc_b_filt_out) ;
      real_adc_a_sum   <= $signed(real_adc_a_sum) + $signed(real_adc_a_i) ;
      real_adc_b_sum   <= $signed(real_adc_b_sum) + $signed(real_adc_b_i) ;
   end

   adc_dv <= (adc_dec_cnt >= set_dec) ;

   case (set_dec & {17{set_avg_en}})
      17'h0     : begin adc_a_dat <= adc_a_filt_out;            adc_b_dat <= adc_b_filt_out;          real_adc_a_dat <= real_adc_a_i;                   real_adc_b_dat <= real_adc_b_i;               end
      17'h1     : begin adc_a_dat <= adc_a_sum[15+0 :  0];      adc_b_dat <= adc_b_sum[15+0 :  0];    real_adc_a_dat <= real_adc_a_sum[15+0 :  0];      real_adc_b_dat <= real_adc_b_sum[15+0 :  0];  end
      17'h2     : begin adc_a_dat <= adc_a_sum[15+1 :  1];      adc_b_dat <= adc_b_sum[15+1 :  1];    real_adc_a_dat <= real_adc_a_sum[15+1 :  1];      real_adc_b_dat <= real_adc_b_sum[15+1 :  1];  end
      17'h4     : begin adc_a_dat <= adc_a_sum[15+2 :  2];      adc_b_dat <= adc_b_sum[15+2 :  2];    real_adc_a_dat <= real_adc_a_sum[15+2 :  2];      real_adc_b_dat <= real_adc_b_sum[15+2 :  2];  end
      17'h8     : begin adc_a_dat <= adc_a_sum[15+3 :  3];      adc_b_dat <= adc_b_sum[15+3 :  3];    real_adc_a_dat <= real_adc_a_sum[15+3 :  3];      real_adc_b_dat <= real_adc_b_sum[15+3 :  3];  end
      17'h10    : begin adc_a_dat <= adc_a_sum[15+4 :  4];      adc_b_dat <= adc_b_sum[15+4 :  4];    real_adc_a_dat <= real_adc_a_sum[15+4 :  4];      real_adc_b_dat <= real_adc_b_sum[15+4 :  4];  end
      17'h20    : begin adc_a_dat <= adc_a_sum[15+5 :  5];      adc_b_dat <= adc_b_sum[15+5 :  5];    real_adc_a_dat <= real_adc_a_sum[15+5 :  5];      real_adc_b_dat <= real_adc_b_sum[15+5 :  5];  end
      17'h40    : begin adc_a_dat <= adc_a_sum[15+6 :  6];      adc_b_dat <= adc_b_sum[15+6 :  6];    real_adc_a_dat <= real_adc_a_sum[15+6 :  6];      real_adc_b_dat <= real_adc_b_sum[15+6 :  6];  end
      17'h80    : begin adc_a_dat <= adc_a_sum[15+7 :  7];      adc_b_dat <= adc_b_sum[15+7 :  7];    real_adc_a_dat <= real_adc_a_sum[15+7 :  7];      real_adc_b_dat <= real_adc_b_sum[15+7 :  7];  end
      17'h100   : begin adc_a_dat <= adc_a_sum[15+8 :  8];      adc_b_dat <= adc_b_sum[15+8 :  8];    real_adc_a_dat <= real_adc_a_sum[15+8 :  8];      real_adc_b_dat <= real_adc_b_sum[15+8 :  8];  end
      17'h200   : begin adc_a_dat <= adc_a_sum[15+9 :  9];      adc_b_dat <= adc_b_sum[15+9 :  9];    real_adc_a_dat <= real_adc_a_sum[15+9 :  9];      real_adc_b_dat <= real_adc_b_sum[15+9 :  9];  end
      17'h400   : begin adc_a_dat <= adc_a_sum[15+10: 10];      adc_b_dat <= adc_b_sum[15+10: 10];    real_adc_a_dat <= real_adc_a_sum[15+10: 10];      real_adc_b_dat <= real_adc_b_sum[15+10: 10];  end
      17'h800   : begin adc_a_dat <= adc_a_sum[15+11: 11];      adc_b_dat <= adc_b_sum[15+11: 11];    real_adc_a_dat <= real_adc_a_sum[15+11: 11];      real_adc_b_dat <= real_adc_b_sum[15+11: 11];  end
      17'h1000  : begin adc_a_dat <= adc_a_sum[15+12: 12];      adc_b_dat <= adc_b_sum[15+12: 12];    real_adc_a_dat <= real_adc_a_sum[15+12: 12];      real_adc_b_dat <= real_adc_b_sum[15+12: 12];  end
      17'h2000  : begin adc_a_dat <= adc_a_sum[15+13: 13];      adc_b_dat <= adc_b_sum[15+13: 13];    real_adc_a_dat <= real_adc_a_sum[15+13: 13];      real_adc_b_dat <= real_adc_b_sum[15+13: 13];  end
      17'h4000  : begin adc_a_dat <= adc_a_sum[15+14: 14];      adc_b_dat <= adc_b_sum[15+14: 14];    real_adc_a_dat <= real_adc_a_sum[15+14: 14];      real_adc_b_dat <= real_adc_b_sum[15+14: 14];  end
      17'h8000  : begin adc_a_dat <= adc_a_sum[15+15: 15];      adc_b_dat <= adc_b_sum[15+15: 15];    real_adc_a_dat <= real_adc_a_sum[15+15: 15];      real_adc_b_dat <= real_adc_b_sum[15+15: 15];  end
      17'h10000 : begin adc_a_dat <= adc_a_sum[15+16: 16];      adc_b_dat <= adc_b_sum[15+16: 16];    real_adc_a_dat <= real_adc_a_sum[15+16: 16];      real_adc_b_dat <= real_adc_b_sum[15+16: 16];  end
      default   : begin adc_a_dat <= adc_a_sum[15+0 :  0];      adc_b_dat <= adc_b_sum[15+0 :  0];    real_adc_a_dat <= real_adc_a_sum[15+0 :  0];      real_adc_b_dat <= real_adc_b_sum[15+0 :  0];  end
/*
      17'h0     : begin adc_a_dat <= adc_a_filt_out;            adc_b_dat <= adc_b_filt_out;        end
      17'h1     : begin adc_a_dat <= adc_a_sum[15+0 :  0];      adc_b_dat <= adc_b_sum[15+0 :  0];  end
      17'h8     : begin adc_a_dat <= adc_a_sum[15+3 :  3];      adc_b_dat <= adc_b_sum[15+3 :  3];  end
      17'h40    : begin adc_a_dat <= adc_a_sum[15+6 :  6];      adc_b_dat <= adc_b_sum[15+6 :  6];  end
      17'h400   : begin adc_a_dat <= adc_a_sum[15+10: 10];      adc_b_dat <= adc_b_sum[15+10: 10];  end
      17'h2000  : begin adc_a_dat <= adc_a_sum[15+13: 13];      adc_b_dat <= adc_b_sum[15+13: 13];  end
      17'h10000 : begin adc_a_dat <= adc_a_sum[15+16: 16];      adc_b_dat <= adc_b_sum[15+16: 16];  end
      default   : begin adc_a_dat <= adc_a_sum[15+0 :  0];      adc_b_dat <= adc_b_sum[15+0 :  0];  end
*/
   endcase
end

//---------------------------------------------------------------------------------
//  ADC buffer RAM

reg   [  14-1: 0] adc_a_buf [0:(1<<RSZ)-1] ;
reg   [  14-1: 0] adc_b_buf [0:(1<<RSZ)-1] ;
reg   [  14-1: 0] adc_a_rd      ;
reg   [  14-1: 0] adc_b_rd      ;
reg   [ RSZ-1: 0] adc_wp        ;
reg   [ RSZ-1: 0] adc_raddr     ;
reg   [ RSZ-1: 0] adc_a_raddr   ;
reg   [ RSZ-1: 0] adc_b_raddr   ;
reg   [   4-1: 0] adc_rval      ;
wire              adc_rd_dv     ;
reg               adc_we        ;
reg               adc_we_keep   ;
reg               adc_trig      ;
reg               peak_trig     ;

reg   [ RSZ-1: 0] adc_wp_trig   ;
reg   [ RSZ-1: 0] adc_wp_cur    ;
reg   [  32-1: 0] set_dly       ;
reg   [  32-1: 0] adc_we_cnt    ;
reg   [  32-1: 0] adc_dly_cnt   ;
reg               adc_dly_do    ;
reg    [ 20-1: 0] set_deb_len   ; // debouncing length (glitch free time after a posedge)

reg               triggered    ;

reg   [ 64 - 1:0] timestamp_trigger;
reg   [ 64 - 1:0] ctr_value        ;
reg   [ 14 - 1:0] pretrig_data_min; // make sure this amount of data has been acquired before trig
reg 			  pretrig_ok;


// Write
always @(posedge adc_clk_i) begin
   if (adc_rstn_i == 1'b0) begin
      adc_wp      <= {RSZ{1'b0}};
      adc_we      <=  1'b0      ;
      adc_wp_trig <= {RSZ{1'b0}};
	  timestamp_trigger <= 64'h0;
	  ctr_value <=         64'h0;
      adc_wp_cur  <= {RSZ{1'b0}};
      adc_we_cnt  <= 32'h0      ;
      adc_dly_cnt <= 32'h0      ;
      adc_dly_do  <=  1'b0      ;
      triggered   <=  1'b0      ;
      pretrig_data_min <= 2**RSZ - set_dly;
      pretrig_ok <= 1'b0; // goes to 1 when enough data has been acquired pretrigger
   end
   else begin
      ctr_value <= ctr_value + 1'b1;
      pretrig_data_min <= 2**RSZ - set_dly; // next line takes care of negative overflow (when set_dly > 2**RSZ)
      // ready for trigger when enough samples are acquired or trigger delay is longer than buffer duration
      pretrig_ok <= (adc_we_cnt > pretrig_data_min) || (|(set_dly[32-1:RSZ]));

      if (adc_arm_do)
         adc_we <= 1'b1 ;
      else if (((adc_dly_do || adc_trig) && (adc_dly_cnt == 32'h0) && ~adc_we_keep) || adc_rst_do) //delayed reached or reset
         adc_we <= 1'b0 ;

      // count how much data was written into the buffer before trigger
      if (adc_rst_do | adc_arm_do)
         adc_we_cnt <= 32'h0;
      if (adc_we & ~adc_dly_do & adc_dv & ~&adc_we_cnt)
         adc_we_cnt <= adc_we_cnt + 1;

      if (adc_rst_do)
         adc_wp <= {RSZ{1'b0}};
      else if (adc_we && adc_dv)
         adc_wp <= adc_wp + 1;

      if (adc_rst_do) begin
         adc_wp_trig <= {RSZ{1'b0}};
		 timestamp_trigger <= ctr_value ;
      end else if (adc_trig && !adc_dly_do && pretrig_ok) begin //last condition added to make sure pretrig data is available
         adc_wp_trig <= adc_wp_cur ; // save write pointer at trigger arrival
		 timestamp_trigger <= ctr_value ;
	  end
      if (adc_rst_do)
         adc_wp_cur <= {RSZ{1'b0}};
      else if (adc_we && adc_dv)
         adc_wp_cur <= adc_wp ; // save current write pointer

      if (adc_trig && pretrig_ok) begin
         adc_dly_do  <= 1'b1 ;
      end else if ((adc_dly_do && (adc_dly_cnt == 32'b0)) || adc_rst_do || adc_arm_do) //delayed reached or reset
         adc_dly_do  <= 1'b0 ;

      if (adc_dly_do && adc_we && adc_dv)
         adc_dly_cnt <= adc_dly_cnt - 1;
      else if (!adc_dly_do)
         adc_dly_cnt <= set_dly ;

      //trigger for fgen recording
      if (adc_trig && adc_we)
         triggered <= 1'b1     ; //communicate the precise moment of the trigger to the main module
      else if ((adc_dly_do && (adc_dly_cnt == 32'b0)) || adc_rst_do || adc_arm_do) //delayed reached or reset
         triggered <= 1'b0     ; 

   end
end

assign trig_scope_o = triggered;

always @(posedge adc_clk_i) begin
   if (adc_we && adc_dv) begin
      adc_a_buf[adc_wp] <= adc_a_dat ;
      adc_b_buf[adc_wp] <= adc_b_dat ;
   end
end

// Read
always @(posedge adc_clk_i) begin
   if (adc_rstn_i == 1'b0)
      adc_rval <= 4'h0 ;
   else
      adc_rval <= {adc_rval[2:0], (sys_ren || sys_wen)};
end
assign adc_rd_dv = adc_rval[3];

always @(posedge adc_clk_i) begin
   adc_raddr   <= sys_addr[RSZ+1:2] ; // address synchronous to clock
   adc_a_raddr <= adc_raddr     ; // double register 
   adc_b_raddr <= adc_raddr     ; // otherwise memory corruption at reading
   adc_a_rd    <= adc_a_buf[adc_a_raddr] ;
   adc_b_rd    <= adc_b_buf[adc_b_raddr] ;
end

localparam  chForPeak_realAdc0 = 0,
            chForPeak_realAdc1 = 1,
            chForPeak_adc0 = 2,
            chForPeak_adc1 = 3;

reg [1:0] chUsedByPeak_a, chUsedByPeak_b, chUsedByPeak_c;
reg [RSZ -1:0] peak_a_minIndex, peak_b_minIndex, peak_c_minIndex;
reg [RSZ -1:0] peak_a_maxIndex, peak_b_maxIndex, peak_c_maxIndex;
reg [RSZ -1:0] peak_a_minValue, peak_b_minValue, peak_c_minValue;
reg [RSZ -1:0] signalForPeak_a, signalForPeak_b, signalForPeak_c;
wire [RSZ*4 -1:0] availablePeakSignals = {adc_b_dat, adc_a_dat, real_adc_b_dat, real_adc_a_dat};
wire [RSZ -1:0]  intermediate_peak_c_index;
wire intermediate_peak_c_valid;
always @(posedge adc_clk_i) begin
   if(~adc_rstn_i) begin
      signalForPeak_a <= 0;
      signalForPeak_b <= 0;
      signalForPeak_c <= 0;
   end else begin
      signalForPeak_a <= availablePeakSignals[RSZ*(chUsedByPeak_a+1) -1-:RSZ];
      signalForPeak_b <= availablePeakSignals[RSZ*(chUsedByPeak_b+1) -1-:RSZ];
      signalForPeak_c <= availablePeakSignals[RSZ*(chUsedByPeak_c+1) -1-:RSZ];
   end
end


reg [RSZ -1:0] peak_flipIndex;
peakFinder #(
   .dataSize          (RSZ),
   .indexSize         (RSZ),
   .areSignalsSigned  (1)
)peakFinders[0:2](
   .clk              (adc_clk_i),
   .reset            (!adc_rstn_i),

   .trigger          (peak_trig),
   .in               ({signalForPeak_a, signalForPeak_b, signalForPeak_c}),
   .in_valid         (adc_dv),

   .indexRange_min   ({peak_a_minIndex, peak_b_minIndex, peak_c_minIndex}),
   .indexRange_max   ({peak_a_maxIndex, peak_b_maxIndex, peak_c_maxIndex}),

   .minValue         ({peak_a_minValue, peak_b_minValue, peak_c_minValue}),
   // .flipIndex        (peak_flipIndex),

   .max              ({peak_a, peak_b, peak_c}),
   .maxIndex         ({peak_a_index, peak_b_index, intermediate_peak_c_index}),
   .max_valid        ({peak_a_valid, peak_b_valid, intermediate_peak_c_valid})
);

//////////////// AXI IS DISABLED SINCE WE ARE NOT USING IT /////////////////////

//---------------------------------------------------------------------------------
//
//  AXI CHA connection

reg  [ 32-1: 0] set_a_axi_start    ;
reg  [ 32-1: 0] set_a_axi_stop     ;
reg  [ 32-1: 0] set_a_axi_dly      ;
reg             set_a_axi_en       ;
reg  [ 32-1: 0] set_a_axi_trig     ;
reg  [ 32-1: 0] set_a_axi_cur      ;
reg             axi_a_we           ;
reg  [ 64-1: 0] axi_a_dat          ;
reg  [  2-1: 0] axi_a_dat_sel      ;
reg  [  1-1: 0] axi_a_dat_dv       ;
reg  [ 32-1: 0] axi_a_dly_cnt      ;
reg             axi_a_dly_do       ;
wire            axi_a_clr          ;
wire [ 32-1: 0] axi_a_cur_addr     ;

assign axi_a_clr = adc_rst_do ;


always @(posedge axi0_clk_o) begin
   if (axi0_rstn_o == 1'b0) begin
      axi_a_we      <=  1'b0 ;
      axi_a_dat     <= 64'h0 ;
      axi_a_dat_sel <=  2'h0 ;
      axi_a_dat_dv  <=  1'b0 ;
      axi_a_dly_cnt <= 32'h0 ;
      axi_a_dly_do  <=  1'b0 ;
   end
   /*
   else begin
      if (adc_arm_do && set_a_axi_en)
         axi_a_we <= 1'b1 ;
      else if (((axi_a_dly_do || adc_trig) && (axi_a_dly_cnt == 32'h0)) || adc_rst_do) //delayed reached or reset
         axi_a_we <= 1'b0 ;

      if (adc_trig && axi_a_we)
         axi_a_dly_do  <= 1'b1 ;
      else if ((axi_a_dly_do && (axi_a_dly_cnt == 32'b0)) || axi_a_clr || adc_arm_do) //delayed reached or reset
         axi_a_dly_do  <= 1'b0 ;

      if (axi_a_dly_do && axi_a_we && adc_dv)
         axi_a_dly_cnt <= axi_a_dly_cnt - 1;
      else if (!axi_a_dly_do)
         axi_a_dly_cnt <= set_a_axi_dly ;

      if (axi_a_clr)
         axi_a_dat_sel <= 2'h0 ;
      else if (axi_a_we && adc_dv)
         axi_a_dat_sel <= axi_a_dat_sel + 2'h1 ;

      axi_a_dat_dv <= axi_a_we && (axi_a_dat_sel == 2'b11) && adc_dv ;
   end

   if (axi_a_we && adc_dv) begin
      if (axi_a_dat_sel == 2'b00) axi_a_dat[ 16-1:  0] <= $signed(adc_a_dat);
      if (axi_a_dat_sel == 2'b01) axi_a_dat[ 32-1: 16] <= $signed(adc_a_dat);
      if (axi_a_dat_sel == 2'b10) axi_a_dat[ 48-1: 32] <= $signed(adc_a_dat);
      if (axi_a_dat_sel == 2'b11) axi_a_dat[ 64-1: 48] <= $signed(adc_a_dat);
   end

   if (axi_a_clr)
      set_a_axi_trig <= {RSZ{1'b0}};
   else if (adc_trig && !axi_a_dly_do && axi_a_we)
      set_a_axi_trig <= {axi_a_cur_addr[32-1:3],axi_a_dat_sel,1'b0} ; // save write pointer at trigger arrival

   if (axi_a_clr)
      set_a_axi_cur <= set_a_axi_start ;
   else if (axi0_wvalid_o)
      set_a_axi_cur <= axi_a_cur_addr ;
*/
end
/*
axi_wr_fifo #(
  .DW  (  64    ), // data width (8,16,...,1024)
  .AW  (  32    ), // address width
  .FW  (   8    )  // address width of FIFO pointers
) i_wr0 (
   // global signals
  .axi_clk_i          (  axi0_clk_o        ), // global clock
  .axi_rstn_i         (  axi0_rstn_o       ), // global reset

   // Connection to AXI master
  .axi_waddr_o        (  axi0_waddr_o      ), // write address
  .axi_wdata_o        (  axi0_wdata_o      ), // write data
  .axi_wsel_o         (  axi0_wsel_o       ), // write byte select
  .axi_wvalid_o       (  axi0_wvalid_o     ), // write data valid
  .axi_wlen_o         (  axi0_wlen_o       ), // write burst length
  .axi_wfixed_o       (  axi0_wfixed_o     ), // write burst type (fixed / incremental)
  .axi_werr_i         (  axi0_werr_i       ), // write error
  .axi_wrdy_i         (  axi0_wrdy_i       ), // write ready

   // data and configuration
  .wr_data_i          (  axi_a_dat         ), // write data
  .wr_val_i           (  axi_a_dat_dv      ), // write data valid
  .ctrl_start_addr_i  (  set_a_axi_start   ), // range start address
  .ctrl_stop_addr_i   (  set_a_axi_stop    ), // range stop address
  .ctrl_trig_size_i   (  4'hF              ), // trigger level
  .ctrl_wrap_i        (  1'b1              ), // start from begining when reached stop
  .ctrl_clr_i         (  axi_a_clr         ), // clear / flush
  .stat_overflow_o    (                    ), // overflow indicator
  .stat_cur_addr_o    (  axi_a_cur_addr    ), // current write address
  .stat_write_data_o  (                    )  // write data indicator
);
*/
assign axi0_clk_o  = adc_clk_i ;
assign axi0_rstn_o = adc_rstn_i;

//---------------------------------------------------------------------------------
//
//  AXI CHB connection

reg  [ 32-1: 0] set_b_axi_start    ;
reg  [ 32-1: 0] set_b_axi_stop     ;
reg  [ 32-1: 0] set_b_axi_dly      ;
reg             set_b_axi_en       ;
reg  [ 32-1: 0] set_b_axi_trig     ;
reg  [ 32-1: 0] set_b_axi_cur      ;
reg             axi_b_we           ;
reg  [ 64-1: 0] axi_b_dat          ;
reg  [  2-1: 0] axi_b_dat_sel      ;
reg  [  1-1: 0] axi_b_dat_dv       ;
reg  [ 32-1: 0] axi_b_dly_cnt      ;
reg             axi_b_dly_do       ;
wire            axi_b_clr          ;
wire [ 32-1: 0] axi_b_cur_addr     ;

assign axi_b_clr = adc_rst_do ;


always @(posedge axi1_clk_o) begin
   if (axi1_rstn_o == 1'b0) begin
      axi_b_we      <=  1'b0 ;
      axi_b_dat     <= 64'h0 ;
      axi_b_dat_sel <=  2'h0 ;
      axi_b_dat_dv  <=  1'b0 ;
      axi_b_dly_cnt <= 32'h0 ;
      axi_b_dly_do  <=  1'b0 ;
   end
/*   else begin
      if (adc_arm_do && set_b_axi_en)
         axi_b_we <= 1'b1 ;
      else if (((axi_b_dly_do || adc_trig) && (axi_b_dly_cnt == 32'h0)) || adc_rst_do) //delayed reached or reset
         axi_b_we <= 1'b0 ;

      if (adc_trig && axi_b_we)
         axi_b_dly_do  <= 1'b1 ;
      else if ((axi_b_dly_do && (axi_b_dly_cnt == 32'b0)) || axi_b_clr || adc_arm_do) //delayed reached or reset
         axi_b_dly_do  <= 1'b0 ;

      if (axi_b_dly_do && axi_b_we && adc_dv)
         axi_b_dly_cnt <= axi_b_dly_cnt - 1;
      else if (!axi_b_dly_do)
         axi_b_dly_cnt <= set_b_axi_dly ;

      if (axi_b_clr)
         axi_b_dat_sel <= 2'h0 ;
      else if (axi_b_we && adc_dv)
         axi_b_dat_sel <= axi_b_dat_sel + 2'h1 ;

      axi_b_dat_dv <= axi_b_we && (axi_b_dat_sel == 2'b11) && adc_dv ;
   end

   if (axi_b_we && adc_dv) begin
      if (axi_b_dat_sel == 2'b00) axi_b_dat[ 16-1:  0] <= $signed(adc_b_dat);
      if (axi_b_dat_sel == 2'b01) axi_b_dat[ 32-1: 16] <= $signed(adc_b_dat);
      if (axi_b_dat_sel == 2'b10) axi_b_dat[ 48-1: 32] <= $signed(adc_b_dat);
      if (axi_b_dat_sel == 2'b11) axi_b_dat[ 64-1: 48] <= $signed(adc_b_dat);
   end

   if (axi_b_clr)
      set_b_axi_trig <= {RSZ{1'b0}};
   else if (adc_trig && !axi_b_dly_do && axi_b_we)
      set_b_axi_trig <= {axi_b_cur_addr[32-1:3],axi_b_dat_sel,1'b0} ; // save write pointer at trigger arrival

   if (axi_b_clr)
      set_b_axi_cur <= set_b_axi_start ;
   else if (axi1_wvalid_o)
      set_b_axi_cur <= axi_b_cur_addr ;
    */
end
/*
axi_wr_fifo #(
  .DW  (  64    ), // data width (8,16,...,1024)
  .AW  (  32    ), // address width
  .FW  (   8    )  // address width of FIFO pointers
) i_wr1 (
   // global signals
  .axi_clk_i          (  axi1_clk_o        ), // global clock
  .axi_rstn_i         (  axi1_rstn_o       ), // global reset

   // Connection to AXI master
  .axi_waddr_o        (  axi1_waddr_o      ), // write address
  .axi_wdata_o        (  axi1_wdata_o      ), // write data
  .axi_wsel_o         (  axi1_wsel_o       ), // write byte select
  .axi_wvalid_o       (  axi1_wvalid_o     ), // write data valid
  .axi_wlen_o         (  axi1_wlen_o       ), // write burst length
  .axi_wfixed_o       (  axi1_wfixed_o     ), // write burst type (fixed / incremental)
  .axi_werr_i         (  axi1_werr_i       ), // write error
  .axi_wrdy_i         (  axi1_wrdy_i       ), // write ready

   // data and configuration
  .wr_data_i          (  axi_b_dat         ), // write data
  .wr_val_i           (  axi_b_dat_dv      ), // write data valid
  .ctrl_start_addr_i  (  set_b_axi_start   ), // range start address
  .ctrl_stop_addr_i   (  set_b_axi_stop    ), // range stop address
  .ctrl_trig_size_i   (  4'hF              ), // trigger level
  .ctrl_wrap_i        (  1'b1              ), // start from begining when reached stop
  .ctrl_clr_i         (  axi_b_clr         ), // clear / flush
  .stat_overflow_o    (                    ), // overflow indicator
  .stat_cur_addr_o    (  axi_b_cur_addr    ), // current write address
  .stat_write_data_o  (                    )  // write data indicator
);
*/
assign axi1_clk_o  = adc_clk_i ;
assign axi1_rstn_o = adc_rstn_i;

////////////// END AXI DISABLING ////////////////////


//---------------------------------------------------------------------------------
//  Trigger source selector

reg               adc_trig_ap   , real_adc_trig_ap   ;
reg               adc_trig_an   , real_adc_trig_an   ;
reg               adc_trig_bp   , real_adc_trig_bp   ;
reg               adc_trig_bn   , real_adc_trig_bn   ;
reg               adc_trig_sw      ;
reg   [   4-1: 0] set_trig_src     ;
reg   [   4-1: 0] continuous_trig_src     ;//used for peak detection, since for that we don't want to disable the trigger once an acquisition has ended, but we want to restart the peak control immediately
wire              ext_trig_p       ;
wire              ext_trig_n       ;
wire              asg_trig_p       ;
wire              asg_trig_n       ;

always @(posedge adc_clk_i)
if (adc_rstn_i == 1'b0) begin
   adc_arm_do    <= 1'b0 ;
   adc_rst_do    <= 1'b0 ;
   adc_trig_sw   <= 1'b0 ;
   set_trig_src  <= 4'h0 ;
   continuous_trig_src <= 0;
   adc_trig      <= 1'b0 ;
end else begin
   adc_arm_do  <= sys_wen && (sys_addr[19:0]==20'h0) && sys_wdata[0] ; // SW ARM
   adc_rst_do  <= sys_wen && (sys_addr[19:0]==20'h0) && sys_wdata[1] ;
   adc_trig_sw <= sys_wen && (sys_addr[19:0]==20'h4) && (sys_wdata[3:0]==4'h1); // SW trigger

      if (sys_wen && (sys_addr[19:0]==20'h4))begin
         set_trig_src <= sys_wdata[3:0] ;
         continuous_trig_src <= sys_wdata[3:0];
      end
      else if (((adc_dly_do || adc_trig) && (adc_dly_cnt == 32'h0)) || adc_rst_do) //delayed reached or reset
         set_trig_src <= 4'h0 ;
         //we don't want to disable continuous_trig_src

   case (set_trig_src)
       4'd1 : adc_trig <= adc_trig_sw   ; // manual
       4'd2 : adc_trig <= adc_trig_ap   ; // A ch rising edge
       4'd3 : adc_trig <= adc_trig_an   ; // A ch falling edge
       4'd4 : adc_trig <= adc_trig_bp   ; // B ch rising edge
       4'd5 : adc_trig <= adc_trig_bn   ; // B ch falling edge
       4'd6 : adc_trig <= ext_trig_p    ; // external - rising edge
       4'd7 : adc_trig <= ext_trig_n    ; // external - falling edge
       4'd8 : adc_trig <= asg_trig_p    ; // ASG - rising edge
       4'd9 : adc_trig <= asg_trig_n    ; // ASG - falling edge
       4'd10: adc_trig <= trig_dsp_i    ; // dsp trigger input
       4'd11: adc_trig <= real_adc_trig_ap;
       4'd12: adc_trig <= real_adc_trig_an;
       4'd13: adc_trig <= real_adc_trig_bp;
       4'd14: adc_trig <= real_adc_trig_bn;
    default : adc_trig <= 1'b0          ;
   endcase
   case (continuous_trig_src)
       4'd1 : peak_trig <= adc_trig_sw   ; // manual
       4'd2 : peak_trig <= adc_trig_ap   ; // A ch rising edge
       4'd3 : peak_trig <= adc_trig_an   ; // A ch falling edge
       4'd4 : peak_trig <= adc_trig_bp   ; // B ch rising edge
       4'd5 : peak_trig <= adc_trig_bn   ; // B ch falling edge
       4'd6 : peak_trig <= ext_trig_p    ; // external - rising edge
       4'd7 : peak_trig <= ext_trig_n    ; // external - falling edge
       4'd8 : peak_trig <= asg_trig_p    ; // ASG - rising edge
       4'd9 : peak_trig <= asg_trig_n    ; // ASG - falling edge
       4'd10: peak_trig <= trig_dsp_i    ; // dsp trigger input
       4'd11: peak_trig <= real_adc_trig_ap;
       4'd12: peak_trig <= real_adc_trig_an;
       4'd13: peak_trig <= real_adc_trig_bp;
       4'd14: peak_trig <= real_adc_trig_bn;
    default : peak_trig <= 1'b0          ;
   endcase
end

//---------------------------------------------------------------------------------
//  Trigger created from input signal

reg  [  2-1: 0] adc_scht_ap  , real_adc_scht_ap;
reg  [  2-1: 0] adc_scht_an  , real_adc_scht_an;
reg  [  2-1: 0] adc_scht_bp  , real_adc_scht_bp;
reg  [  2-1: 0] adc_scht_bn  , real_adc_scht_bn;
reg  [ 14-1: 0] set_a_tresh  ;
reg  [ 14-1: 0] set_a_treshp ;
reg  [ 14-1: 0] set_a_treshm ;
//reg  [ 14-1: 0] set_b_tresh  ;
//reg  [ 14-1: 0] set_b_treshp ;
//reg  [ 14-1: 0] set_b_treshm ;
reg  [ 14-1: 0] set_a_hyst   ;
//reg  [ 14-1: 0] set_b_hyst   ;

always @(posedge adc_clk_i)
if (adc_rstn_i == 1'b0) begin
   adc_scht_ap  <=  2'h0 ;  real_adc_scht_ap  <=  2'h0 ;
   adc_scht_an  <=  2'h0 ;  real_adc_scht_an  <=  2'h0 ;
   adc_scht_bp  <=  2'h0 ;  real_adc_scht_bp  <=  2'h0 ;
   adc_scht_bn  <=  2'h0 ;  real_adc_scht_bn  <=  2'h0 ;
   adc_trig_ap  <=  1'b0 ;  real_adc_trig_ap  <=  1'b0 ;
   adc_trig_an  <=  1'b0 ;  real_adc_trig_an  <=  1'b0 ;
   adc_trig_bp  <=  1'b0 ;  real_adc_trig_bp  <=  1'b0 ;
   adc_trig_bn  <=  1'b0 ;  real_adc_trig_bn  <=  1'b0 ;
end else begin
   set_a_treshp <= set_a_tresh + set_a_hyst ; // calculate positive
   set_a_treshm <= set_a_tresh - set_a_hyst ; // and negative treshold
   //set_b_treshp <= set_b_tresh + set_b_hyst ;
   //set_b_treshm <= set_b_tresh - set_b_hyst ;

   if (adc_dv) begin
           if ($signed(adc_a_dat) >= $signed(set_a_tresh ))      adc_scht_ap[0] <= 1'b1 ;  // treshold reached
      else if ($signed(adc_a_dat) <  $signed(set_a_treshm))      adc_scht_ap[0] <= 1'b0 ;  // wait until it goes under hysteresis
           if ($signed(adc_a_dat) <= $signed(set_a_tresh ))      adc_scht_an[0] <= 1'b1 ;  // treshold reached
      else if ($signed(adc_a_dat) >  $signed(set_a_treshp))      adc_scht_an[0] <= 1'b0 ;  // wait until it goes over hysteresis

           if ($signed(adc_b_dat) >= $signed(set_a_tresh ))      adc_scht_bp[0] <= 1'b1 ; //set_b_tresh
      else if ($signed(adc_b_dat) <  $signed(set_a_treshm))      adc_scht_bp[0] <= 1'b0 ; //set_b_treshm
           if ($signed(adc_b_dat) <= $signed(set_a_tresh ))      adc_scht_bn[0] <= 1'b1 ; //set_b_tresh
      else if ($signed(adc_b_dat) >  $signed(set_a_treshp))      adc_scht_bn[0] <= 1'b0 ; //set_b_treshp


           if ($signed(real_adc_a_dat) >= $signed(set_a_tresh ))      real_adc_scht_ap[0] <= 1'b1 ;  // treshold reached
      else if ($signed(real_adc_a_dat) <  $signed(set_a_treshm))      real_adc_scht_ap[0] <= 1'b0 ;  // wait until it goes under hysteresis
           if ($signed(real_adc_a_dat) <= $signed(set_a_tresh ))      real_adc_scht_an[0] <= 1'b1 ;  // treshold reached
      else if ($signed(real_adc_a_dat) >  $signed(set_a_treshp))      real_adc_scht_an[0] <= 1'b0 ;  // wait until it goes over hysteresis

           if ($signed(real_adc_b_dat) >= $signed(set_a_tresh ))      real_adc_scht_bp[0] <= 1'b1 ; //set_b_tresh
      else if ($signed(real_adc_b_dat) <  $signed(set_a_treshm))      real_adc_scht_bp[0] <= 1'b0 ; //set_b_treshm
           if ($signed(real_adc_b_dat) <= $signed(set_a_tresh ))      real_adc_scht_bn[0] <= 1'b1 ; //set_b_tresh
      else if ($signed(real_adc_b_dat) >  $signed(set_a_treshp))      real_adc_scht_bn[0] <= 1'b0 ; //set_b_treshp
   end

   adc_scht_ap[1] <= adc_scht_ap[0] ; real_adc_scht_ap[1] <= real_adc_scht_ap[0] ;
   adc_scht_an[1] <= adc_scht_an[0] ; real_adc_scht_an[1] <= real_adc_scht_an[0] ;
   adc_scht_bp[1] <= adc_scht_bp[0] ; real_adc_scht_bp[1] <= real_adc_scht_bp[0] ;
   adc_scht_bn[1] <= adc_scht_bn[0] ; real_adc_scht_bn[1] <= real_adc_scht_bn[0] ;

 // make 1 cyc pulse 
   adc_trig_ap <= adc_scht_ap[0] && !adc_scht_ap[1] ;  real_adc_trig_ap <= real_adc_scht_ap[0] && !real_adc_scht_ap[1] ;
   adc_trig_an <= adc_scht_an[0] && !adc_scht_an[1] ;  real_adc_trig_an <= real_adc_scht_an[0] && !real_adc_scht_an[1] ;
   adc_trig_bp <= adc_scht_bp[0] && !adc_scht_bp[1] ;  real_adc_trig_bp <= real_adc_scht_bp[0] && !real_adc_scht_bp[1] ;
   adc_trig_bn <= adc_scht_bn[0] && !adc_scht_bn[1] ;  real_adc_trig_bn <= real_adc_scht_bn[0] && !real_adc_scht_bn[1] ;
end

//---------------------------------------------------------------------------------
//  External trigger

reg  [  3-1: 0] ext_trig_in    ;
reg  [  2-1: 0] ext_trig_dp    ;
reg  [  2-1: 0] ext_trig_dn    ;
reg  [ 20-1: 0] ext_trig_debp  ;
reg  [ 20-1: 0] ext_trig_debn  ;
reg  [  3-1: 0] asg_trig_in_ch1;
reg  [  3-1: 0] asg_trig_in_ch2;
reg  [  2-1: 0] asg_trig_dp    ;
reg  [  2-1: 0] asg_trig_dn    ;
reg  [ 20-1: 0] asg_trig_debp  ;
reg  [ 20-1: 0] asg_trig_debn  ;

always @(posedge adc_clk_i)
if (adc_rstn_i == 1'b0) begin
   ext_trig_in   <=  3'h0 ;
   ext_trig_dp   <=  2'h0 ;
   ext_trig_dn   <=  2'h0 ;
   ext_trig_debp <= 20'h0 ;
   ext_trig_debn <= 20'h0 ;
   asg_trig_in_ch1 <=  3'h0 ;
   asg_trig_in_ch2 <=  3'h0 ;
   asg_trig_dp   <=  2'h0 ;
   asg_trig_dn   <=  2'h0 ;
   asg_trig_debp <= 20'h0 ;
   asg_trig_debn <= 20'h0 ;
end else begin
   //----------- External trigger
   // synchronize FFs
   ext_trig_in <= {ext_trig_in[1:0],trig_ext_i} ;

   // look for input changes
   if ((ext_trig_debp == 20'h0) && (ext_trig_in[1] && !ext_trig_in[2]))
      ext_trig_debp <= set_deb_len ; // ~0.5ms
   else if (ext_trig_debp != 20'h0)
      ext_trig_debp <= ext_trig_debp - 20'd1 ;

   if ((ext_trig_debn == 20'h0) && (!ext_trig_in[1] && ext_trig_in[2]))
      ext_trig_debn <= set_deb_len ; // ~0.5ms
   else if (ext_trig_debn != 20'h0)
      ext_trig_debn <= ext_trig_debn - 20'd1 ;

   // update output values
   ext_trig_dp[1] <= ext_trig_dp[0] ;
   if (ext_trig_debp == 20'h0)
      ext_trig_dp[0] <= ext_trig_in[1] ;

   ext_trig_dn[1] <= ext_trig_dn[0] ;
   if (ext_trig_debn == 20'h0)
      ext_trig_dn[0] <= ext_trig_in[1] ;

   //----------- ASG trigger - instead of pos/neg. edge we use ch1 pos edge / ch2 pos edge
   // synchronize FFs
   asg_trig_in_ch1 <= {asg_trig_in_ch1[1:0],trig_asg_i[0]} ;
   asg_trig_in_ch2 <= {asg_trig_in_ch2[1:0],trig_asg_i[1]} ;

   // look for input changes -ch1
   if ((asg_trig_debp == 20'h0) && (asg_trig_in_ch1[1] && !asg_trig_in_ch1[2]))
      asg_trig_debp <= set_deb_len ; // ~0.5ms
   else if (asg_trig_debp != 20'h0)
      asg_trig_debp <= asg_trig_debp - 20'd1 ;

   // look for input changes - ch2
   if ((asg_trig_debn == 20'h0) && (asg_trig_in_ch2[1] && !asg_trig_in_ch2[2]))
      asg_trig_debn <= set_deb_len ; // ~0.5ms
   else if (asg_trig_debn != 20'h0)
      asg_trig_debn <= asg_trig_debn - 20'd1 ;

   // update output values
   asg_trig_dp[1] <= asg_trig_dp[0] ;
   if (asg_trig_debp == 20'h0)
      asg_trig_dp[0] <= asg_trig_in_ch1[1] ;

   asg_trig_dn[1] <= asg_trig_dn[0] ;
   if (asg_trig_debn == 20'h0)
      asg_trig_dn[0] <= asg_trig_in_ch2[1] ;
end

assign ext_trig_p = (ext_trig_dp == 2'b01) ;
assign ext_trig_n = (ext_trig_dn == 2'b10) ;
assign asg_trig_p = (asg_trig_dp == 2'b01) ;
assign asg_trig_n = (asg_trig_dn == 2'b01) ;

//---------------------------------------------------------------------------------
//  System bus connection

always @(posedge adc_clk_i)
if (adc_rstn_i == 1'b0) begin
   adc_we_keep   <=   1'b0      ;
   set_a_tresh   <=  14'd0000   ;
   //set_b_tresh   <=  14'd0000   ;
   set_dly       <=  2**(RSZ-1);
   set_dec       <=  17'h2000; // corresponds to 1s duration, formerly at minimum: 17'd1
   set_a_hyst    <=  14'd20     ;
   //set_b_hyst    <=  14'd20     ;
   set_avg_en    <=   1'b0      ;
/*   set_a_filt_aa <=  18'h0      ;
   set_a_filt_bb <=  25'h0      ;
   set_a_filt_kk <=  25'hFFFFFF ;
   set_a_filt_pp <=  25'h0      ;
   set_b_filt_aa <=  18'h0      ;
   set_b_filt_bb <=  25'h0      ;
   set_b_filt_kk <=  25'hFFFFFF ;
   set_b_filt_pp <=  25'h0      ;*/
   set_deb_len   <=  20'd62500  ;
   set_a_axi_en  <=   1'b0      ;
   set_b_axi_en  <=   1'b0      ;

   peak_a_minIndex <= 0;
   peak_a_maxIndex <= 2**(RSZ-1);
   peak_b_minIndex <= 0;
   peak_b_maxIndex <= 2**(RSZ-1);
   peak_c_minIndex <= 0;
   peak_c_maxIndex <= 2**(RSZ-1);
   peak_flipIndex <= 0;

   chUsedByPeak_a <= chForPeak_realAdc0;
   chUsedByPeak_b <= chForPeak_realAdc1;
   chUsedByPeak_c <= chForPeak_realAdc0;
   peak_a_minValue <= 0;
   peak_b_minValue <= 0;
   peak_c_minValue <= 0;


end else begin
   if (sys_wen) begin
      if (sys_addr[19:0]==20'h00)   adc_we_keep   <= sys_wdata[     3] ;

      if (sys_addr[19:0]==20'h08)   set_a_tresh   <= sys_wdata[14-1:0] ;
      //if (sys_addr[19:0]==20'h0C)   set_b_tresh   <= sys_wdata[14-1:0] ;
      if (sys_addr[19:0]==20'h10)   set_dly       <= sys_wdata[32-1:0] ;
      if (sys_addr[19:0]==20'h14)   set_dec       <= sys_wdata[17-1:0] ;
      if (sys_addr[19:0]==20'h20)   set_a_hyst    <= sys_wdata[14-1:0] ;
      //if (sys_addr[19:0]==20'h24)   set_b_hyst    <= sys_wdata[14-1:0] ;
      if (sys_addr[19:0]==20'h28)   set_avg_en    <= sys_wdata[     0] ;

      /*
      if (sys_addr[19:0]==20'h30)   set_a_filt_aa <= sys_wdata[18-1:0] ;
      if (sys_addr[19:0]==20'h34)   set_a_filt_bb <= sys_wdata[25-1:0] ;
      if (sys_addr[19:0]==20'h38)   set_a_filt_kk <= sys_wdata[25-1:0] ;
      if (sys_addr[19:0]==20'h3C)   set_a_filt_pp <= sys_wdata[25-1:0] ;
      if (sys_addr[19:0]==20'h40)   set_b_filt_aa <= sys_wdata[18-1:0] ;
      if (sys_addr[19:0]==20'h44)   set_b_filt_bb <= sys_wdata[25-1:0] ;
      if (sys_addr[19:0]==20'h48)   set_b_filt_kk <= sys_wdata[25-1:0] ;
      if (sys_addr[19:0]==20'h4C)   set_b_filt_pp <= sys_wdata[25-1:0] ;
      */
      /*
      if (sys_addr[19:0]==20'h50)   set_a_axi_start <= sys_wdata[32-1:0] ;
      if (sys_addr[19:0]==20'h54)   set_a_axi_stop  <= sys_wdata[32-1:0] ;
      if (sys_addr[19:0]==20'h58)   set_a_axi_dly   <= sys_wdata[32-1:0] ;
      if (sys_addr[19:0]==20'h5C)   set_a_axi_en    <= sys_wdata[     0] ;

      if (sys_addr[19:0]==20'h70)   set_b_axi_start <= sys_wdata[32-1:0] ;
      if (sys_addr[19:0]==20'h74)   set_b_axi_stop  <= sys_wdata[32-1:0] ;
      if (sys_addr[19:0]==20'h78)   set_b_axi_dly   <= sys_wdata[32-1:0] ;
      if (sys_addr[19:0]==20'h7C)   set_b_axi_en    <= sys_wdata[     0] ;
      */
      if (sys_addr[19:0]==20'h90)   set_deb_len <= sys_wdata[20-1:0] ;

      if (sys_addr[19:0]==20'h094)   peak_a_minIndex <= sys_wdata ;
      if (sys_addr[19:0]==20'h098)   peak_a_maxIndex <= sys_wdata ;
      if (sys_addr[19:0]==20'h09C)   peak_b_minIndex <= sys_wdata ;
      if (sys_addr[19:0]==20'h0A0)   peak_b_maxIndex <= sys_wdata ;
      if (sys_addr[19:0]==20'h0B0)   {chUsedByPeak_c, chUsedByPeak_b, chUsedByPeak_a} <= sys_wdata ;
      if (sys_addr[19:0]==20'h0B4)   {peak_b_minValue, peak_a_minValue} <= sys_wdata ;
      if (sys_addr[19:0]==20'h0B8)   peak_flipIndex <= sys_wdata ;

      if (sys_addr[19:0]==20'h0BC)   peak_c_minIndex <= sys_wdata ;
      if (sys_addr[19:0]==20'h0C0)   peak_c_maxIndex <= sys_wdata ;
      if (sys_addr[19:0]==20'h0CC)   {peak_c_minValue} <= sys_wdata ;
      
   end
end
normalizedRatio#(
   .inputSize     (RSZ),
   .ratioSize     (RSZ),//ratio is unsigned, with 0 whole bits (only fractional bits)
   .isInputSigned (1)
) nr (
   .clk        (adc_clk_i),
   .reset      (!adc_rstn_i),
   .min        (peak_a_index),
   .max        (peak_b_index),
   .middle     (intermediate_peak_c_index),
   .ratio      (peak_c_index)
);
assign peak_c_valid = intermediate_peak_c_valid & peak_b_valid & peak_a_valid;


wire sys_en;
assign sys_en = sys_wen | sys_ren;

always @(posedge adc_clk_i)
if (adc_rstn_i == 1'b0) begin
   sys_err <= 1'b0 ;
   sys_ack <= 1'b0 ;
end else begin
   sys_err <= 1'b0 ;
   casez (sys_addr[19:0])
     20'h00000 : begin sys_ack <= sys_en;          sys_rdata <= {{32- 4{1'b0}}, adc_we_keep               // do not disarm on 
                                                                              , adc_dly_do                // trigger status
                                                                              , 1'b0                      // reset
                                                                              , adc_we}             ; end // arm

     20'h00004 : begin sys_ack <= sys_en;          sys_rdata <= {{32- 8{1'b0}},continuous_trig_src, set_trig_src}       ; end 

     20'h00008 : begin sys_ack <= sys_en;          sys_rdata <= {{32-14{1'b0}}, set_a_tresh}        ; end
     //20'h0000C : begin sys_ack <= sys_en;          sys_rdata <= {{32-14{1'b0}}, set_b_tresh}        ; end
     20'h00010 : begin sys_ack <= sys_en;          sys_rdata <= {               set_dly}            ; end
     20'h00014 : begin sys_ack <= sys_en;          sys_rdata <= {{32-17{1'b0}}, set_dec}            ; end

     20'h00018 : begin sys_ack <= sys_en;          sys_rdata <= {{32-RSZ{1'b0}}, adc_wp_cur}        ; end
     20'h0001C : begin sys_ack <= sys_en;          sys_rdata <= {{32-RSZ{1'b0}}, adc_wp_trig}       ; end

     20'h00020 : begin sys_ack <= sys_en;          sys_rdata <= {{32-14{1'b0}}, set_a_hyst}         ; end
     //20'h00024 : begin sys_ack <= sys_en;          sys_rdata <= {{32-14{1'b0}}, set_b_hyst}         ; end

     20'h00028 : begin sys_ack <= sys_en;          sys_rdata <= {{32- 1{1'b0}}, set_avg_en}         ; end

     20'h0002C : begin sys_ack <= sys_en;          sys_rdata <=                 adc_we_cnt          ; end

     /*
     20'h00030 : begin sys_ack <= sys_en;          sys_rdata <= {{32-18{1'b0}}, set_a_filt_aa}      ; end
     20'h00034 : begin sys_ack <= sys_en;          sys_rdata <= {{32-25{1'b0}}, set_a_filt_bb}      ; end
     20'h00038 : begin sys_ack <= sys_en;          sys_rdata <= {{32-25{1'b0}}, set_a_filt_kk}      ; end
     20'h0003C : begin sys_ack <= sys_en;          sys_rdata <= {{32-25{1'b0}}, set_a_filt_pp}      ; end
     20'h00040 : begin sys_ack <= sys_en;          sys_rdata <= {{32-18{1'b0}}, set_b_filt_aa}      ; end
     20'h00044 : begin sys_ack <= sys_en;          sys_rdata <= {{32-25{1'b0}}, set_b_filt_bb}      ; end
     20'h00048 : begin sys_ack <= sys_en;          sys_rdata <= {{32-25{1'b0}}, set_b_filt_kk}      ; end
     20'h0004C : begin sys_ack <= sys_en;          sys_rdata <= {{32-25{1'b0}}, set_b_filt_pp}      ; end
     */
     /*
     20'h00050 : begin sys_ack <= sys_en;          sys_rdata <=                 set_a_axi_start     ; end
     20'h00054 : begin sys_ack <= sys_en;          sys_rdata <=                 set_a_axi_stop      ; end
     20'h00058 : begin sys_ack <= sys_en;          sys_rdata <=                 set_a_axi_dly       ; end
     20'h0005C : begin sys_ack <= sys_en;          sys_rdata <= {{32- 1{1'b0}}, set_a_axi_en}       ; end
     20'h00060 : begin sys_ack <= sys_en;          sys_rdata <=                 set_a_axi_trig      ; end
     20'h00064 : begin sys_ack <= sys_en;          sys_rdata <=                 set_a_axi_cur       ; end

     20'h00070 : begin sys_ack <= sys_en;          sys_rdata <=                 set_b_axi_start     ; end
     20'h00074 : begin sys_ack <= sys_en;          sys_rdata <=                 set_b_axi_stop      ; end
     20'h00078 : begin sys_ack <= sys_en;          sys_rdata <=                 set_b_axi_dly       ; end
     20'h0007C : begin sys_ack <= sys_en;          sys_rdata <= {{32- 1{1'b0}}, set_b_axi_en}       ; end
     20'h00080 : begin sys_ack <= sys_en;          sys_rdata <=                 set_b_axi_trig      ; end
     20'h00084 : begin sys_ack <= sys_en;          sys_rdata <=                 set_b_axi_cur       ; end
     */

     20'h00090 : begin sys_ack <= sys_en;          sys_rdata <= {{32-20{1'b0}}, set_deb_len}        ; end
     
     20'h00094 : begin sys_ack <= sys_en;          sys_rdata <= peak_a_minIndex        ; end
     20'h00098 : begin sys_ack <= sys_en;          sys_rdata <= peak_a_maxIndex        ; end
     20'h0009C : begin sys_ack <= sys_en;          sys_rdata <= peak_b_minIndex        ; end
     20'h000A0 : begin sys_ack <= sys_en;          sys_rdata <= peak_b_maxIndex        ; end

     20'h000A4 : begin sys_ack <= sys_en;          sys_rdata <= {peak_b_valid, peak_b, {(15-RSZ){1'b0}}, peak_a_valid, peak_a}        ; end
     20'h000A8 : begin sys_ack <= sys_en;          sys_rdata <= peak_a_index        ; end
     20'h000AC : begin sys_ack <= sys_en;          sys_rdata <= peak_b_index        ; end
     20'h000B0 : begin sys_ack <= sys_en;          sys_rdata <= {chUsedByPeak_c, chUsedByPeak_b, chUsedByPeak_a}        ; end
     20'h000B4 : begin sys_ack <= sys_en;          sys_rdata <= {peak_b_minValue, peak_a_minValue}        ; end
     20'h000B8 : begin sys_ack <= sys_en;          sys_rdata <= peak_flipIndex        ; end
     // peak c
     20'h000BC : begin sys_ack <= sys_en;          sys_rdata <= peak_c_minIndex        ; end
     20'h000C0 : begin sys_ack <= sys_en;          sys_rdata <= peak_c_maxIndex        ; end
     20'h000C4 : begin sys_ack <= sys_en;          sys_rdata <= {intermediate_peak_c_valid, peak_c_valid, peak_c}        ; end
     20'h000C8 : begin sys_ack <= sys_en;          sys_rdata <= {intermediate_peak_c_index, {(16-RSZ){1'b0}}, peak_c_index}        ; end
     20'h000CC : begin sys_ack <= sys_en;          sys_rdata <= peak_c_minValue        ; end

    
     20'h00154 : begin sys_ack <= sys_en;          sys_rdata <= {{32-14{1'b0}}, adc_a_i }         ; end
     20'h00158 : begin sys_ack <= sys_en;          sys_rdata <= {{32-14{1'b0}}, adc_b_i }         ; end
	 
	 20'h0015c : begin sys_ack <= sys_en;          sys_rdata <= ctr_value[32-1:0]     		    ; end
	 20'h00160 : begin sys_ack <= sys_en;          sys_rdata <= ctr_value[64-1:32]			    ; end
	 
	 20'h00164 : begin sys_ack <= sys_en;          sys_rdata <= timestamp_trigger[32-1:0]       ; end
	 20'h00168 : begin sys_ack <= sys_en;          sys_rdata <= timestamp_trigger[64-1:32]	    ; end
     
     20'h0016c : begin sys_ack <= sys_en;          sys_rdata <= {{32-1{1'b0}}, pretrig_ok}       ; end

     20'h1???? : begin sys_ack <= adc_rd_dv;       sys_rdata <= {16'h0, 2'h0,adc_a_rd}              ; end
     20'h2???? : begin sys_ack <= adc_rd_dv;       sys_rdata <= {16'h0, 2'h0,adc_b_rd}              ; end
	 
	 

       default : begin sys_ack <= sys_en;          sys_rdata <=  32'h0                              ; end
   endcase
end

endmodule
