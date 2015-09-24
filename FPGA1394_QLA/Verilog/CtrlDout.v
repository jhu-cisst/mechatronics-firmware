/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2015 Johns Hopkins University.
 *
 * This module controls access to the digital output bits. Each of the four digital
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
 */

`include "Constants.v" 

module CtrlDout(
    input  wire sysclk,           // global clock and reset signals
    input  wire reset,            // global reset
    input  wire[15:0] reg_raddr,  // register file read addr from outside 
    input  wire[15:0] reg_waddr,  // register file write addr from outside 
    output wire[31:0] reg_rdata,  // outgoing register file data
    input  wire[31:0] reg_wdata,  // incoming register file data
    input  wire reg_wen,          // write enable signal from outside world
    output wire[4:1] dout         // digital outputs
);    

wire dout_set;           // write to digital output bit (masked by reg_wdata[8:11])             
assign dout_set = (reg_wen && (reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4] == 4'd0) & (reg_waddr[3:0] == `REG_DIGIOUT)) ? 1'd1 : 1'd0;
wire dout_set_en[1:4];   // enable signal for each digital output
assign dout_set_en[1] = dout_set && reg_wdata[8];
assign dout_set_en[2] = dout_set && reg_wdata[9];
assign dout_set_en[3] = dout_set && reg_wdata[10];
assign dout_set_en[4] = dout_set && reg_wdata[11];
             
wire dout_ctrl;           // write to control register (hi/low times)
assign dout_ctrl = (reg_wen && (reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[3:0]==`OFF_DOUT_CTRL)) ? 1'd1 : 1'd0;
wire dout_ctrl_en[1:4];   // enable signal for each digital output control register
assign dout_ctrl_en[1] = (dout_ctrl && (reg_waddr[7:4] == 4'd1)) ? 1'd1 : 1'd0;
assign dout_ctrl_en[2] = (dout_ctrl && (reg_waddr[7:4] == 4'd2)) ? 1'd1 : 1'd0;
assign dout_ctrl_en[3] = (dout_ctrl && (reg_waddr[7:4] == 4'd3)) ? 1'd1 : 1'd0;
assign dout_ctrl_en[4] = (dout_ctrl && (reg_waddr[7:4] == 4'd4)) ? 1'd1 : 1'd0;
   
wire [31:0] reg_rd[1:4];  // read control register (hi/low times)
assign reg_rdata = (reg_raddr[3:0]==`OFF_DOUT_CTRL) ? reg_rd[reg_raddr[7:4]] : 32'd0;
// Note: reading of digital output state is done in BoardRegs.v

// Instantiate module for each digital output      
DoutPWM DoutPWM1(sysclk, reset, reg_rd[1], dout_ctrl_en[1], reg_wdata, dout_set_en[1], reg_wdata[0], dout[1]);
DoutPWM DoutPWM2(sysclk, reset, reg_rd[2], dout_ctrl_en[2], reg_wdata, dout_set_en[2], reg_wdata[1], dout[2]);
DoutPWM DoutPWM3(sysclk, reset, reg_rd[3], dout_ctrl_en[3], reg_wdata, dout_set_en[3], reg_wdata[2], dout[3]);
DoutPWM DoutPWM4(sysclk, reset, reg_rd[4], dout_ctrl_en[4], reg_wdata, dout_set_en[4], reg_wdata[3], dout[4]);

endmodule

module DoutPWM(
    input wire         sysclk,       // sysclk
    input wire         reset,        // reset
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
    
always @(posedge(sysclk) or negedge(reset))
begin
    if (reset == 0) begin
       dout <= 1'd0;
       HiLoTime <= 32'd0;
       curTime <= 16'd0;
    end
    else if (dout_enable) begin                  // if writing a new value for dout
       dout <= dout_set;                         //    set the value
       curTime <= 16'd0;                         //    set current time to 0
    end
    else if (ctrl_enable) begin
       HiLoTime <= reg_wdata;
       curTime <= 16'd0;
    end
    else if (desiredTime[dout] != 16'd0) begin   // else if desired time is non-zero
       curTime <= curTime + 1;                   //    increment current time
       if (curTime == desiredTime[dout]) begin   //    if current time == desired time
          dout <= ~dout;                         //       negate digital output
          curTime <= 16'd0;                      //       set current time to 0
       end
    end
end

endmodule

