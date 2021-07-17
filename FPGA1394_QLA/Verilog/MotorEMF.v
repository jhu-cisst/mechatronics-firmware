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

module MotorEMF(
    input  wire               clk,
    input  wire               val_ready,
    input  wire        [15:0] cur_cmd,
    input  wire        [15:0] cur_fb,
    output reg                emf_ready,
    output reg                emf_overflow,
    output reg         [16:0] emf_out
);

// local wires for QLA board gain
reg [15:0] board_gain;
reg [4 :0] board_gain_shift;

// modified QLA board gain is 38.2, stored as 38.2 * 2^8 ~= 9779 (9779.2 raw)
// needs to be right shifted 8 times to regain fractional value
initial begin
    board_gain = 9779; // 00100110_00110011
    board_gain_shift = 8;
end

// local wires for commanded current to motor voltage conversion
reg [15:0] cur2vol;
reg [4 :0] cur2vol_shift;

// DAC gain V_OUT = cur_cmd * V_REF, where V_REF = 2.5V
// i.e. cur2vol = 
// stored as 2.5 * 2^8 = 640
// needs to be right shifted 8 times to regain fractional value
initial begin
    cur2vol = 640;     // 00000010_10000000
    cur2vol_shift = 8;
end

// local wires for motor resistence
reg [15:0] resist;
reg [4 :0] resist_shift;

// total resistence of R_motor and R62 = 7.73 ohms + 0.2 ohms = 7.93 ohms,
// stored as 7.93 * 2^8 ~= 2030 (2030.08 raw) needs to be right shifted 8 times 
// to regain fractional value
initial begin
    resist = 2030;     // 00000111_11101110
    resist_shift = 8;
end

// local wires for intermediate/output registers
reg [31:0] cur_res_prod;
reg [31:0] cur2vol_prod;
reg [16:0] vol_res;
reg [16:0] vol_brd;
reg [47:0] brd_prod;

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

    // edge detected, implements bemf = 2 * board_gain * cur2vol * cur_cmd - cur_fb * resist
    // values in the above equation are in fixed-point representation
    if (cur_val_ready && cur_val_ready_last == 0) begin

        cur_res_prod = ((cur_fb * resist) >>> resist_shift);
        vol_res = {1'b0, cur_res_prod[23:8]};

        brd_prod = (cur2vol * cur_cmd * board_gain) >>> cur2vol_shift;
        vol_brd = {1'b0, brd_prod[31:16] <<< 1};

        emf_out = vol_brd - vol_res;
        
        // conversion complete
        emf_ready <= 1;

        // case 1: cur_cmd = (0x8000)
        // cur_fb * resist = 0.5A (0x8000) * 7.93 = 3.965, 
        // i.e. 3.965 * 2^8 ~= 1015 (1015.04 raw) == 00001111_11011100
        // 2 * board_gain * cur2vol * cur_cmd = 2 * 0.5A (0x8000) * 2.5 * 38.2 = 95.5
        // i.e. 95.5 * 2^8 = 24448 == 01011111_10000000

        // case 2: cur_cmd = (0xf000)
        // cur_fb * resist = 0.9375A (0xf000) * 7.93 = 7.434, 
        // i.e. 7.434 * 2^8 ~= 1903 (1903.2 raw) == 00000111_01101111
        // 2 * board_gain * cur2vol * cur_cmd = 2 * 0.9375A (0xf000) * 2.5 * 38.2 ~= 179.0625
        // i.e. 179.0625 * 2^8 = 45840 == 10110011_00010000

        // max case: 
        // i.e. vol_res = 7.93 * (0xffff) 1A = 7.93 ~= 8 -> 8 * 2^8 = 2048 == 00001000_00000000
        //      vol_brd = 2 * 38.2 * 2.5 * (0xffff) 1A = 191 -> 191 * 2^8 = 48896 == 10111111_00000000
        //      emf_out = vol_brd - vol_res = 191 - 8 = 183 -> 183 * 2^8 = 46848 == 10110111_00000000
    end else begin
        // wait for next valid ADC sample
        emf_ready <= 0;
    end

    // update edge detection
    cur_val_ready_last = cur_val_ready;
end

// check emf overflow
// if MSB of emf is set, an overflow is detected
always @(posedge(clk)) begin
    if (emf_ready) begin
        emf_overflow <= emf_out[16];
    end else begin
        emf_overflow <= 0;
    end
end

endmodule