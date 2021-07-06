`timescale 1ns / 1ps
/*******************************************************************************
 *
 * Copyright(C) 2013-2021 ERC CISST, Johns Hopkins University.
 *
 * This module estimates the back EMF on single motor. 
 *
 * Revision history
 *    05/07/21   Jintan Zhang          Initial revision 
*/

`include "Constants.v"

module MotorEMF(
    input  wire               clk,
    input  wire               val_ready,
    input  wire        [15:0] cur_cmd,
    input  wire        [15:0] cur_fb,
    output reg                emf_ready,
    output reg                emf_overflow,
    output reg signed  [16:0] emf_out
    );

// local wires for QLA board gain
reg [15:0] board_gain;
reg [4 :0] board_gain_shift;

// modified QLA board gain is 38.2, stored as 38.2 * 2^8 ~= 9779 (9779.2 raw)
// needs to be right shifted 8 times to regain fractional value
initial begin
    board_gain = 9779;
    board_gain_shift = 8;
end

// local wires for current to voltage conversion
reg [15:0] cur2vol;
reg [4 :0] cur2vol_shift;

// conversion factor used in digital control is 1.25, stored as 1.25 * 2^8 = 320
// needs to be right shifted 8 times to regain fractional value
initial begin
    cur2vol = 320;
    cur2vol_shift = 8;
end

// local wires for motor resistence and R62
reg [15:0] resist;
reg [4 :0] resist_shift;

// total resistence of R_motor and R62 = 7.73 ohms + 0.2 ohms = 7.93 ohms,
// stored as 7.93 * 2^8 ~= 2030 (2030.08 raw) needs to be right shifted 8 times 
// to regain fractional value
initial begin
    resist = 2030;
    resist_shift = 8;
end

// local wires for intermediate/output registers
reg signed [16:0] e_cur;
reg signed [32:0] cur_res_prod;
reg signed [32:0] cur2vol_prod;
reg signed [32:0] brd_prod;
reg signed [16:0] vol_res;
reg signed [16:0] vol_brd;

// local wires for trigger signal 
reg cur_val_ready;
reg cur_val_ready_last;

initial begin
        cur_val_ready = 0;
        cur_val_ready_last = 0;
end

// functional module
always @(posedge(clk)) begin
    // edge detection, trigger emf computation
    cur_val_ready = val_ready;

    // edge detected, implements bemf = board_gain * cur2vol * (cur_cmd - cur_fb) - cur_fb * resist
    // values in the above equation are in fixed-point representation
    if (cur_val_ready && cur_val_ready_last == 0) begin
        // cur_cmd - cur_fb
        e_cur = {1'b0, cur_fb} - {1'b0, cur_cmd};

        // cur_fb * resist
        cur_res_prod = cur_fb * resist;
        vol_res = {cur_res_prod[32], cur_res_prod[22:7] >>> resist_shift};

        // cur2vol * (cur_cmd - cur_fb)
        cur2vol_prod = cur2vol * e_cur;
        vol_brd = {cur2vol_prod[32], cur2vol_prod[22:7] >>> cur2vol_shift};

        // board_gain * cur2vol * (cur_cmd - cur_fb) - cur_fb * resist
        brd_prod = vol_brd[15:0] * board_gain;
        emf_out <= {vol_brd[16], brd_prod[22:7] >>> board_gain_shift - vol_res};

        // conversion complete
        emf_ready <= 1;
    end else begin
        // wait for next valid ADC sample
        emf_ready <= 0;
    end

    // update edge detection
    cur_val_ready_last = cur_val_ready;
end

// check emf overflow
// if current error and back emf have different sign, an overflow is detected
always @(posedge(clk)) begin
    if (emf_ready) begin
        emf_overflow <= e_cur[16] & emf_out[16];
    end else begin
        emf_overflow <= 0;
    end
end

endmodule