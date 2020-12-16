/*******************************************************************************
 *
 * Copyright(C) 2008-2020 ERC CISST, Johns Hopkins University.
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
 */

// ------------------------------------------------
// Quad Ticks Version 
// ------------------------------------------------
module EncPeriodQuad(
    input wire clk,               // sysclk
    input wire a,                 // quad encoder line a
    input wire b,                 // quad encoder line b
    input wire dir,               // dir from EncQuad
    output reg[31:0] period,      // num of fast clock ticks
    output reg[31:0] quarter1,    // [23:0] clock ticks in last quarter cycle
    output reg[31:0] quarter5,    // [23:0] clock ticks in quarter cycle 5 edges ago
    output wire[31:0] t_cur       // time since last edge
);

    reg[1:0] mux;  // Indicates most recent edge (a_up, a_dn, b_up, or b_dn)
    reg a_r;       // Previous value of A channel
    reg b_r;       // Previous value of B channel

    // Various overflow values. The counters are all 26 bits (width parameter), but the quarter-cycle
    // counts (for acceleration) are limited to 24 bits (small_overflow).
    // Starting with Rev 7, all bits are sent to the higher-level module (and to the PC via FireWire).
    parameter width = 26;
    parameter small_overflow = 24'hFFFFFF;  // 24-bit overflow value
    parameter overflow_value = 26'h3FFFFFF; // 26-bit overflow value

    // Queue of last 5 quarter cycles for acceleration and counter since last tick
    //    counter[1] -- free running counter
    //    counter[2] -- most recent latched counter
    //    ...
    //    counter[5] -- oldest latched counter
    // If edges were not skipped and direction changes did not occur, then counter[5] and counter[2]
    // correspond to the latched counters for the same encoder events.
    reg[width-1:0] counter [1:5];
    
initial begin
    counter[1] = overflow_value;
    counter[2] = overflow_value;
    counter[3] = overflow_value;
    counter[4] = overflow_value;
    counter[5] = overflow_value;
end   
    
//------------------------------------------------------------------------------
// hardware description
//

localparam[1:0] a_up = 2'b00;
localparam[1:0] a_dn = 2'b10;
localparam[1:0] b_up = 2'b01;
localparam[1:0] b_dn = 2'b11;

reg [1:0] latched_mux;   // Previous value of mux
reg [1:0] next_edge;     // Next expected edge (not currently used)

// Determine which edge is the most recent and sets mux (no longer a mux, but used
// to indicate the most recent edge). Could do some error checking here; for example,
// when the current edge is not equal to next_edge.
always @(posedge clk)
begin
    a_r <= a;
    b_r <= b;
    if (a & (~a_r)) begin        // a_up
        mux <= a_up;
        next_edge <= dir ? b_dn : b_up;
    end
    else if (b & (~b_r)) begin   // b_up
        mux <= b_up;    
        next_edge <= dir ? a_up : a_dn;
    end    
    else if ((~a) & a_r) begin   // a_dn
        mux <= a_dn;
        next_edge <= dir ? b_up : b_dn;
    end
    else if ((~b) & b_r) begin   // b_dn
        mux <= b_dn;
        next_edge <= dir ? a_dn : a_up;
    end
end

wire latch_overflow;
wire [width+1:0] sum;
assign sum = counter[1]+counter[2]+counter[3]+counter[4];
assign latch_overflow = (counter[2] == overflow_value) || (counter[3] == overflow_value) 
                        || (counter[4] == overflow_value) || (counter[5] == overflow_value);

always @(posedge clk) begin

    if (latched_mux != mux) begin
        // If a new edge has been detected, shift the queue and clear the running counter.
        // There is a 1-clock delay here, but since it happens for both clearing the counter
	// and shifting the queue, the net effect cancels out. It could be addressed by
        // setting counter[1] <= 1 and counter[2] <= counter[1]-1, but that is more work to
	// produce the same result.
        counter[1] <= 0;
        counter[2] <= counter[1];
        counter[3] <= counter[2];
        counter[4] <= counter[3];
        counter[5] <= counter[4];
        latched_mux <= mux;

        // Full cycle period
        // The MSB (period[31]) indicates an overflow and period[30] contains the direction.
        if (sum > overflow_value) begin
            period[31] <= 1;
            period[width+1:0] <= overflow_value;
        end else begin
            period[31] <= 0;
            period[width+1:0] <= sum;
        end
        period[30] <= dir;

        // Recent counter for acceleration
        if (counter[1] > small_overflow) begin
            quarter1[width-3:0] <= small_overflow[width-3:0];
        end else begin
            quarter1[width-3:0] <= counter[1][width-3:0];
        end

        // Prev counter for acceleration
        if (counter[5] > small_overflow) begin
            quarter5[width-3:0] <= small_overflow[width-3:0];
        end else begin
            quarter5[width-3:0] <= counter[1][width-3:0];
        end

    end else if (counter[1] != overflow_value) begin
        // If not overflowed, increment free-running counter
        counter[1] <= counter[1] + 26'b1;
    end else begin
        // Indicate that overflow has occurred
        period[31] <= 1;
    end
end

//Should overflow more values
assign t_cur = {1'b0, latch_overflow, latched_mux, mux, counter[1]};
endmodule
