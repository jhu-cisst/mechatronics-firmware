/*******************************************************************************
 *
 * Copyright(C) 2008-2012 ERC CISST, Johns Hopkins University.
 *
 * This module measures the encoder pulse period by counting the edges of a
 * fixed fast clock (~1 MHz) between encoder pulses.  Each new encoder pulse
 * latches the current count and starts a new one.  From this measurement the
 * encoder period can be obtained by multiplying the number of counts by the
 * period of the fixed fast clock.
 *
 * Assumes counter will overflow if encoder moves too slowly.
 *
 * Revision history
 *     07/20/08    Paul Thienphrapa    Initial revision
 *     11/21/11    Paul Thienphrapa    Fix to use ticks+ as clock
 *     02/27/12    Paul Thienphrapa    Only count up due to unknown problem
 *     02/29/12    Zihan Chen          Fix implementation and debug module
 *     03/17/14    Peter Kazanzides    Update data every ticks (dP = 4)
 *	    04/07/17    Jie Ying Wu  	      Return only larger of cnter or cnter_latch
 */

// ---------- Peter ------------------
module EncPeriod1(
   input wire clk_fast,     // count this clock between encoder ticks
   input wire reset,        // global reset signal
   input wire ticks,        // encoder transition signal
   input wire dir,          // direction of the ticks
   output wire ticks_en,    // edge signal 
   output reg[31:0] count  // number clk_fast periods per tick
);

    // local registers 
    reg[21:0] cnter;        // cnter current value
    reg[21:0] cnter_latch;  // latched cnter value

    // overflow value for unsigned 22-bit number
    parameter overflow = 22'h3FFFFF;


//------------------------------------------------------------------------------
// hardware description
//

// convert ticks to pulse
reg dir_r;      // dir start 
reg dir_changed; //changed direction in this cycle
reg ticks_r;    // previous ticks
assign ticks_en = ticks & (~ticks_r);

// choose output to be the larger of latched value or free-running counter
always @(posedge clk_fast) 
begin
   ticks_r <= ticks;
	dir_r <= dir;
   
	if (cnter >= cnter_latch) begin
		count <= {0, dir, dir_changed, 7'h00, cnter};
	end 
	else begin
		count <= {1, dir, dir_changed, 7'h00, cnter_latch};
	end
end

// latch cnter value 
always @(posedge ticks_en or negedge reset)
begin
    if (reset == 0) begin
        cnter_latch <= 22'd0;
    end
    else begin
        cnter_latch <= cnter;
    end
end

// free-running counter 
always @(posedge clk_fast or posedge ticks_en or negedge reset) 
begin
	if (reset == 0 || ticks_en) begin
		cnter <= 22'd0;
      dir_changed <= 0;
	end
   else if (dir != dir_r) begin
      cnter <= overflow;
      dir_changed <= 1;
   end
   else if (cnter != overflow) begin
      cnter <= cnter + 1;   
   end
end

endmodule


// ------------------------------------------------
// Quad Ticks Version 
// ------------------------------------------------
module EncPeriodSingle(
    input wire clk,           // sysclk
    input wire clk_fast,      // count this clock between encoder ticks
    input wire reset,         // global reset signal
    input wire a,             // quad encoder line a
    input wire b,             // quad encoder line b
    input wire dir,           // dir from EncQuad
    output reg[31:0] period   // num of fast clock ticks
);

    reg[1:0] mux;
    wire a_up_tick;
    wire a_dn_tick;
    wire b_up_tick;
    wire b_dn_tick;
    wire[31:0] perd_a_up;   // channel a up data 
    wire[31:0] perd_a_dn;   // channel a dn data
    wire[31:0] perd_b_up;   // channel b up data
    wire[31:0] perd_b_dn;   // channel b dn data

//------------------------------------------------------------------------------
// hardware description
//
EncPeriod1 EncPerUpA(clk_fast, reset,  a, dir, a_up_tick, perd_a_up);

always @ (posedge clk_fast) begin
    period = perd_a_up;
end

endmodule


