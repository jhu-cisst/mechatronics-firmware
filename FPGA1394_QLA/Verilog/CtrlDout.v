/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2015-2022 Johns Hopkins University.
 *
 * This module controls access to the digital output bits. Each of the digital
 * output bits can be set/cleared, put in PWM mode, or used as a 1-shot.
 * These modes are selected by a 32-bit control register for each digital output bit.
 * The upper 16 bits are the high time and the lower 16 bits are the low time.
 * If the time is 0, the digital output is kept at the current value indefinitely
 * (i.e., until either the digital output or the control register is changed).
 * If the time is non-zero, the digital output is kept at the current value for
 * the specified time and then it is inverted.
 * 
 * General DOUT (set/clear):  high_time = low_time = 0
 * Pulse high for DT:  high_time = DT, low_time = 0
 * Pulse low for DT:   high_time = 0, low_time = DT
 * PWM mode:           high_time = DTH, low_time = DTL (period = DTH+DTL)
 * 
 * Note that regardless of the mode, writing to DOUT will cause it to change
 * to the new value. It will also reset the timer. For example, if we set
 * the control register to pulse high for 100 clocks, but then set DOUT to 1
 * after 50 clocks, it will stay high for a total of 150 clocks.
 * Writing to the control register also resets the time, so the same behavior
 * would occur if we write to the control register after 50 clocks (assuming
 * we do not change the high_time).
 *
 * Revision history
 *     9/23/15    Peter Kazanzides  Initial implementation
 *     4/21/16    Peter Kazanzides  Added support for QLA Rev 1.4
 *     4/07/17    Jie Ying Wu       Minor changes so PWM finishes its current period before changing duty cycle
 *    12/13/20    Peter Kazanzides  Added waveform table
 *    12/15/22    Peter Kazanzides  Parameterized based on NUM_DOUT and made DoutCfgCheck a separate module
 */

`include "Constants.v" 

module CtrlDout
    #(parameter NUM_DOUT = 4)
(
    input  wire sysclk,           // global clock
    input  wire[15:0] reg_raddr,  // register file read addr from outside 
    input  wire[15:0] reg_waddr,  // register file write addr from outside 
    output wire[31:0] reg_rdata,  // outgoing register file data
    output wire[31:0] table_rdata,  // outgoing table data
    input  wire[31:0] reg_wdata,  // incoming register file data
    input  wire reg_wen,          // write enable signal from outside world
    output wire[31:0] dout,       // digital outputs
    input  wire[3:0] io_extra     // Extra I/O for FPGA V3.1+
);

wire dout_set;           // write to digital output bit (masked by reg_wdata[15:8])
assign dout_set = (reg_wen && (reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4] == 4'd0) & (reg_waddr[3:0] == `REG_DIGIOUT)) ? 1'd1 : 1'd0;
wire dout_set_en[1:NUM_DOUT];  // enable signal for each digital output

wire dout_pwm[1:NUM_DOUT];     // DOUT from PWM module (also handles regular DOUT setting)

// Whether to enable waveform table output for each DOUT.
// To use the waveform table, the host should first fill the table (by block write to `ADDR_WAVEFORM)
// and then write to `REG_DIGIOUT, setting the most significant bit (to enable waveform output)
// and the mask bits (reg[wdata[8:11]) for each digital output that should be driven by the table.
reg[NUM_DOUT-1:0] dout_waveform_en;

// Whether any digital output is configured to be driven by the table
wire dout_waveform_any;
assign dout_waveform_any = (dout_waveform_en == {NUM_DOUT{1'b0}}) ? 1'b0 : 1'b1;

genvar i;
generate
for (i = 0; i < NUM_DOUT; i = i + 1) begin : dout_loop
    assign dout_set_en[i+1] = dout_set && reg_wdata[i+8];
    // Assign the digital output to be either from the waveform table (if dout_waveform_en and entry_valid)
    // or from the PWM module.
    assign dout[i] = (dout_waveform_en[i]&entry_valid) ? table_rdata[i] : dout_pwm[i+1];
end
// Zero any unused dout
for (i = NUM_DOUT; i < 8; i = i + 1) begin : dout0_loop
    assign dout[i] = 1'b0;
end
endgenerate

assign dout[11:8] = io_extra;
assign dout[15:12] = 4'd0;
assign dout[25:16] = table_raddr;
assign dout[29:26] = 4'd0;
assign dout[30] = dout_waveform_any&entry_valid;
assign dout[31] = dout_waveform_any;

//************************** DOUT Waveform Table **********************************

wire dout_table_wen;
assign dout_table_wen = (reg_wen && (reg_waddr[15:12]==`ADDR_WAVEFORM)) ? 1'd1 : 1'd0;

reg[9:0] table_raddr;     // Table read address (10 bits)

reg[22:0] table_cnt;      // Used to count duration of table output

// Whether a valid table entry
wire entry_valid;
assign entry_valid = table_rdata[31];

// Last count for table entry (23 bits):
//    0        -> 1 sysclk (~20.3 ns)
//    0x7fffff -> 8,388,608 sysclk (~170.7 ms)
wire[22:0] end_cnt;
assign end_cnt = table_rdata[30:8];

// Table of DOUT values to be written.
// This table is 1024 x 32
// Format:  Valid(1), EndCnt(23), DOUT(8)
Dual_port_RAM_32X1024 dout_table(
                       .clka(sysclk),
                       .ena(1'b1),
                       .wea(dout_table_wen),
                       .addra(reg_waddr[9:0]),
                       .dina(reg_wdata),
                       .clkb(sysclk),
                       .enb(1'b1),
                       .addrb(dout_waveform_any ? table_raddr : reg_raddr[9:0]),
                       .doutb(table_rdata)
                      );

always @(posedge sysclk)
begin
   if (dout_set) begin
      // If bit 31 set, enable DOUT based on mask bits reg_wdata[15:8]
      dout_waveform_en <= reg_wdata[31] ? reg_wdata[NUM_DOUT+7:8] : {NUM_DOUT{1'b0}};
      table_raddr <= 10'd0;
      table_cnt <= 23'd0;
   end
   else if (dout_waveform_any&entry_valid) begin
      // If driving at least one DOUT from the waveform table
      if (table_cnt == end_cnt) begin
         table_raddr <= table_raddr + 10'd1;
         table_cnt <= 23'd0;
      end
      else begin
         table_cnt <= table_cnt + 23'd1;
      end
   end
   else begin
      // Idle
      dout_waveform_en <= {NUM_DOUT{1'b0}};
      table_raddr <= 10'd0;
      table_cnt <= 23'd0;
   end
end

genvar j;
generate
for (j = 1; j <= NUM_DOUT; j = j + 1) begin : ctrl_loop
    assign dout_ctrl_en[j] = (dout_ctrl && (reg_waddr[7:4] == j)) ? 1'd1 : 1'd0;
end
endgenerate

wire dout_ctrl;           // write to control register (hi/low times)
assign dout_ctrl = (reg_wen && (reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[3:0]==`OFF_DOUT_CTRL)) ? 1'd1 : 1'd0;
wire dout_ctrl_en[1:NUM_DOUT];   // enable signal for each digital output control register

wire [31:0] reg_rd[1:NUM_DOUT];  // read control register (hi/low times)
assign reg_rdata = (reg_raddr[3:0] == `OFF_DOUT_CTRL) ? reg_rd[reg_raddr[7:4]] : 32'd0;
// Note: reading of digital output state is done in BoardRegs.v

// Instantiate module for each digital output      
genvar k;
generate
for (k = 1; k <= NUM_DOUT; k = k + 1) begin : pwm_loop
    DoutPWM DoutPWM(sysclk, reg_rd[k], dout_ctrl_en[k], reg_wdata, dout_set_en[k], reg_wdata[k-1], dout_pwm[k]);
end
endgenerate

endmodule

//***********************************************************************************************

module DoutCfgCheck(
    input  wire sysclk,           // global clock
    input  wire dir12_read,       // direction control for channels 1-2 (QLA Rev 1.4+)
    input  wire dir34_read,       // direction control for channels 3-4 (QLA Rev 1.4+)
    output reg  dir12_reg,        // direction control for channels 1-2 (QLA Rev 1.4+)
    output reg  dir34_reg,        // direction control for channels 3-4 (QLA Rev 1.4+)
    output reg  dout_cfg_valid,   // 1 -> DOUT configuration valid
    output reg  dout_cfg_bidir,   // 1 -> new DOUT hardware (bidirectional control)
    input  wire dout_cfg_reset    // 1 -> reset dout_cfg_valid
);

initial begin
  dout_cfg_valid = 0;
  dout_cfg_bidir = 0;
end

// The following code is for a configuration check. QLA Version 1.4 has bidirectional transceivers instead of the
// MOSFET drivers used in prior versions of the QLA. We can detect this by checking the state of the two
// direction pins (dir12_read, dir34_read), if we are not driving those pins. The FPGA should power up with those pins
// as inputs, but to be sure we get a correct value we first tri-state those lines (during reset) before we
// check their values. QLA Rev 1.4+ has pulldown resistors on the direction lines, so we should read them as 0.
// In prior versions of the QLA, those IO pins are not connected, but since the FPGA has weak pullups, they should read as 1.
//
// If we detect QLA Rev 1.4+, we set the direction pins to 1 so that the FPGA starts to drive the digital outputs.
// We also set a dout_cfg_bidir flag to indicate that we have detected the newer QLA DOUT hardware. In this case,
// we also need to invert the dout signals for backward compatibility with the older QLA version, which inverted
// the DOUT signals in hardware (due to the MOSFET).
//
// Note that QLA Rev 1.4+ allows the DOUT pins to be used as inputs, but this is not currently supported by the firmware,
// except that the DS2505 module can set ds_enable to take over DOUT3 and DIR34 for the 1-wire interface.

// Following counter used during initialization to detect DOUT configuration
// (12 bits --> about 80 usec)
reg[11:0] dout_cfg_cnt;

reg  wasOldQLA;
reg  wasNewQLA;
wire isOldQLA;
wire isNewQLA;
// dir12_read==0 && dir34_read==0  --> New QLA (Rev 1.4+)
// dir12_read==1 && dir34_read==1  --> Old QLA
assign isOldQLA = dir12_read&dir34_read;
assign isNewQLA = ~(dir12_read|dir34_read);

always @(posedge(sysclk))
begin
   if (dout_cfg_reset) begin
      dout_cfg_valid <= 1'b0;
      dout_cfg_bidir <= 1'b0;
      dout_cfg_cnt <= 12'd0;
   end
   else if (!dout_cfg_valid) begin
      wasOldQLA <= isOldQLA;
      wasNewQLA <= isNewQLA;
      // Increment counter only when isOldQLA or isNewQLA is consistent with previous state
      dout_cfg_cnt <= ((wasOldQLA&isOldQLA)|(wasNewQLA&isNewQLA)) ? (dout_cfg_cnt + 12'd1) : 12'd0;

      if (dout_cfg_cnt == 12'hfff) begin
         dout_cfg_bidir <= isNewQLA;
         dout_cfg_valid <= 1'b1;
         if (isNewQLA) begin
            // If QLA Rev 1.4+ detected, start driving outputs
            dir12_reg <= 1'b1;
            dir34_reg <= 1'b1;
         end
      end
   end
end

endmodule

//***********************************************************************************************

module DoutPWM(
    input wire         sysclk,       // sysclk
    output wire [31:0] reg_rdata,    // outgoing register data (control register)
    input wire         ctrl_enable,  // write enable signal for control register
    input wire [31:0]  reg_wdata,    // incoming register data (for control register)
    input wire         dout_enable,  // if 1, set dout to dout_set
    input wire         dout_set,     // new value for dout
    output reg         dout          // digital output bit
);

    // -------------------------------------------------------------------------
    // local wires and registers
    //

    reg[31:0]  HiLoTime;       // hi/low times
    reg[15:0]  curTime;        // working counter

    wire [15:0] desiredTime[0:1];
    assign desiredTime[1] = HiLoTime[31:16];   // high time
    assign desiredTime[0] = HiLoTime[15:0];    // low time

    // Provide control register to outside world
    assign reg_rdata = HiLoTime;
    
always @(posedge(sysclk))
begin
    if (dout_enable) begin                       // if writing a new value for dout
       dout <= dout_set;                         //    set the value
       curTime <= 16'd0;                         //    set current time to 0
    end
    else if (ctrl_enable) begin
       HiLoTime <= reg_wdata;
    end
    else if (desiredTime[dout] != 16'd0) begin   // else if desired time is non-zero
       curTime <= curTime + 16'd1;               //    increment current time
       if (curTime > desiredTime[dout]) begin    //    if current time == desired time
          dout <= ~dout;                         //       negate digital output
          curTime <= 16'd0;                      //       set current time to 0
       end
    end
end

endmodule
