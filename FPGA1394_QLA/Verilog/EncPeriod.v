/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2008-2021 ERC CISST, Johns Hopkins University.
 *
 * This module measures the encoder pulse period by counting the edges of a
 * fixed fast clock between encoder pulses.  Each new encoder pulse
 * latches the current count and starts a new one.  From this measurement the
 * encoder period can be obtained by multiplying the number of counts by the
 * period of the fixed fast clock.
 *
 * Initially, the fixed fast clock was ~3 MHz, but it is now sysclk (FireWire clock),
 * which is 49.152 MHz.
 *
 * Assumes counter will overflow if encoder moves too slowly.
 *
 * Revision history
 *     07/20/08    Paul Thienphrapa    Initial revision
 *     11/21/11    Paul Thienphrapa    Fix to use ticks+ as clock
 *     02/27/12    Paul Thienphrapa    Only count up due to unknown problem
 *     02/29/12    Zihan Chen          Fix implementation and debug module
 *     03/17/14    Peter Kazanzides    Update data every tick (dP = 4)
 *     04/07/17    Jie Ying Wu         Return only larger of cnter or cnter_latch
 *     10/19/17    Jie Ying Wu         Added acceleration estimation
 *     12/07/20    Peter Kazanzides    Return both cnter (free running counter) and cnter_latch
 *     12/16/20    Peter Kazanzides    Revised implementation
 */

// ------------------------------------------------
// Quad Ticks Version 
// ------------------------------------------------
module EncPeriodQuad(
    input wire clk,               // sysclk
    input wire a,                 // quad encoder line a
    input wire b,                 // quad encoder line b
    input wire dir,               // dir from EncQuad
    output wire[31:0] period,     // num of clock ticks since last edge of same type (full cycle)
    output wire[31:0] quarter1,   // [25:0] clock ticks in last quarter cycle
    output wire[31:0] quarter5,   // [25:0] clock ticks in quarter cycle 5 edges ago
    output wire[31:0] t_cur       // time since last edge
);

    reg a_r;       // Previous value of A channel
    reg b_r;       // Previous value of B channel

    // Starting with Rev 7, all bits are sent to the higher-level module.
    parameter width = 26;
    parameter overflow_value = 26'h3FFFFFF; // Maximum 26-bit value (overflow)

    // Queue of last 5 quarter cycles for acceleration and counter since last tick
    //    counter[0] -- free running counter
    //    counter[1] -- most recent latched counter (QTR1)
    //    counter[2] -- QTR2
    //    counter[3] -- QTR3
    //    counter[4] -- QTR4
    //    counter[5] -- oldest latched counter (QTR5)
    // If edges were not skipped and direction changes did not occur, then counter[5] and counter[1]
    // correspond to the latched counters for the same encoder events and can be used to estimate
    // acceleration.
    reg[width-1:0] counter[0:5];
    reg            counter0_overflow;   // whether counter[0] has overflowed
    reg[6:0]       flags[1:5];          // overflow, dir, enc_error, a_up, b_up, a_down, b_down

    localparam ovf_bit = 6,     // overflow bit in flags
               dir_bit = 5,     // direction bit in flags
               error_bit = 4,   // encoder error
               a_up_bit = 3,
               b_up_bit = 2,
               a_dn_bit = 1,
               b_dn_bit = 0;

initial begin
    counter[0] = overflow_value;
    counter[1] = overflow_value;
    counter[2] = overflow_value;
    counter[3] = overflow_value;
    counter[4] = overflow_value;
    counter[5] = overflow_value;
    counter0_overflow = 1'b1;
    flags[1] = 7'b100000;
    flags[2] = 7'b100000;
    flags[3] = 7'b100000;
    flags[4] = 7'b100000;
    flags[5] = 7'b100000;
end   

//------------------------------------------------------------------------------
// hardware description
//
// Encoder convention (same as EncQuad)
//    dir = 0: a_up -> b_dn -> a_dn -> b_up  (flags[3:0]: 1000, 0001, 0010, 0100) -- left shift (B leads A)
//    dir = 1: a_up -> b_up -> a_dn -> b_dn  (flags[3:0]: 1000, 0100, 0010, 0001) -- right shift (A leads B)

wire a_up;
wire b_up;
wire a_down;
wire b_down;
assign a_up = a & (~a_r);
assign b_up = b & (~b_r);
assign a_down = (~a) & a_r;
assign b_down = (~b) & b_r;

// Encoder direction -- this signal is only valid when a pulse
// (i.e., a_up, b_up, a_down, or b_down) has just occurred.
// After that, use the "dir" register.
wire dir_now;
assign dir_now = a^b_r;   // dir 1 is A leading B

reg init_done;          // indicates that prev has a valid value

wire [width+1:0] sum;   // 28-bits for sum of 4 26-bit values
assign sum = counter[1]+counter[2]+counter[3]+counter[4];

// Following used to determine whether last two encoder edges are valid, based on the direction
// (assuming direction has not changed)
wire enc_valid_dir[0:1];
assign enc_valid_dir[0] = (flags[1][3:0] == {b_down, a_up, b_up, a_down}) ? 1'b1 : 1'b0;  // dir == 0, left shift
assign enc_valid_dir[1] = (flags[1][3:0] == {b_up, a_down, b_down, a_up}) ? 1'b1 : 1'b0;  // dir == 1, right shift
// Following used to determine whether the last two encoder edges are valid, if direction changed
wire enc_valid_change;
assign enc_valid_change = (flags[1][3:0] == { a_down, b_down, a_up, b_up }) ? 1'b1 : 1'b0;
// Combining above two checks
wire enc_valid;
assign enc_valid = (flags[1][dir_bit] == dir_now) ? enc_valid_dir[dir_now] : enc_valid_change;

// We skip the checks if flags[1][3:0] has not yet been set (initial value is 0000).
wire flags1_valid;
assign flags1_valid = (flags[1][3:0] == 4'b0000) ? 1'b0 : 1'b1;

always @(posedge clk)
begin
    a_r <= a;
    b_r <= b;
    init_done <= 1;
    if (init_done & (a_up | a_down | b_up | b_down)) begin
        // If a new edge has been detected, shift the queue and initialize the running counter
        counter[0] <= 26'b0;
        counter0_overflow <= 1'b0;
        counter[1] <= counter[0];
        flags[1] <= {counter0_overflow, dir_now, (flags1_valid ? ~enc_valid : 1'b0), a_up, b_up, a_down, b_down};
        counter[2] <= counter[1];
        flags[2] <= flags[1];
        counter[3] <= counter[2];
        flags[3] <= flags[2];
        counter[4] <= counter[3];
        flags[4] <= flags[3];
        counter[5] <= counter[4];
        flags[5] <= flags[4];
    end
    else if (counter[0] != overflow_value) begin
        // If not overflowed, increment free-running counter
        counter[0] <= counter[0] + 26'b1;
    end
    else begin
        // Indicate that overflow has occurred
        counter0_overflow <= 1'b1;
    end
end

assign t_cur =    {counter0_overflow, dir, {30-width{1'b0}}, counter[0]};
assign quarter1 = {flags[1][ovf_bit], flags[1][dir_bit], flags[1][3:0], counter[1]};
assign quarter5 = {flags[5][ovf_bit], flags[5][dir_bit], flags[5][3:0], counter[5]};

// Last full-cycle period
// Set overflow bit if sum is greater than overflow_value; note that if any quarter-cycle period
// has overflowed, then sum will also overflow.
wire overflow_flag;
assign overflow_flag = (sum > overflow_value) ? 1'b1 : 1'b0;
// Set direction bit based on most recent quarter-cycle direction (flags[1][dir_bit]),
// but also indicate if there was a direction change (~dir_same).
// Wire dir_same indicates whether last 4 quarter-cycles were all in the same direction (all 0 or all 1).
// A 4-input NOR indicates whether all bits are 0 and a 4-input AND indicates whether all bits are 1.
wire dir_same;
assign dir_same =
  ~(flags[1][dir_bit] | flags[2][dir_bit] | flags[3][dir_bit] | flags[4][dir_bit]) |
   (flags[1][dir_bit] & flags[2][dir_bit] & flags[3][dir_bit] & flags[4][dir_bit]);
// Indicate whether any encoder error was detected
wire enc_error;
assign enc_error = flags[1][error_bit] | flags[2][error_bit] | flags[3][error_bit] | flags[4][error_bit];
// Indicate whether not enough edges have occurred for a full cycle (this is only important during testing).
// We detect this by checking if the edge mask for the last counter is all zero (flags[4][3:0] == 4'd0)
// because that means it is still at its initial value.
wire partial_cycle;
assign partial_cycle = (flags[4][3:0] == 4'd0) ? 1'b1 : 1'b0;

assign period = { overflow_flag, flags[1][dir_bit], ~dir_same, enc_error, partial_cycle, 1'b0,
                  overflow_flag ? overflow_value : sum[width-1:0] };

endmodule
