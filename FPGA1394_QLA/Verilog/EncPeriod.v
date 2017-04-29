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
module EncPeriod(
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

    // overflow value for signed 22-bit number
    parameter overflow = 22'h3FFFFF;


//------------------------------------------------------------------------------
// hardware description
//

// convert ticks to pulse
reg dir_r;      // dir start 
reg dir_changed; //changed direction in this cycle
reg ticks_r;    // previous ticks
assign ticks_en = ticks & (~ticks_r);

always @(posedge clk_fast) 
begin
   ticks_r <= ticks;
	
	if (cnter > cnter_latch) begin
		count <= {1, dir, dir_changed, 7'h00, cnter};
	end 
	else begin
		count <= {0, dir, dir_changed, 7'h00, cnter_latch};
	end
end

// latch previous dir 
always @(posedge ticks_en) 
begin
    dir_r <= dir;
end

// latch cnter value 
always @(posedge ticks_en or negedge reset)
begin
    if (reset == 0) begin
        cnter_latch <= 22'd0;
		  dir_changed <= 0;
    end
    else if (dir != dir_r) begin  
        // dir changed set to overflow
        if (cnter != 0) begin //I think dir is one clock cycle behind the edge change
		      cnter_latch <= overflow;  
		      dir_changed <= 1;
		  end
    end    
    else begin
        cnter_latch <= cnter;
		  dir_changed <= 0;
    end
end

// counter 
always @(posedge clk_fast or posedge ticks_en or negedge reset) 
begin
	if (reset == 0 || ticks_en) begin
		cnter <= 22'd0;
	end
   else if (cnter != overflow) begin
      cnter <= cnter + 1;   
   end
end

endmodule


// ------------------------------------------------
// Quad Ticks Version 
// ------------------------------------------------
module EncPeriodQuad(
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
EncPeriod EncPerUpA(clk_fast, reset,  a, dir, a_up_tick, perd_a_up);
EncPeriod EncPerDnA(clk_fast, reset, ~a, dir, a_dn_tick, perd_a_dn);
EncPeriod EncPerUpB(clk_fast, reset,  b, dir, b_up_tick, perd_b_up);
EncPeriod EncPerDnB(clk_fast, reset, ~b, dir, b_dn_tick, perd_b_dn);


always @(posedge a_up_tick or posedge a_dn_tick or posedge b_up_tick or posedge b_dn_tick)
begin
    if (a_up_tick) begin
        mux <= 2'b00;
    end
    else if (b_up_tick) begin
        mux <= 2'b01;    
    end    
    else if (a_dn_tick) begin
        mux <= 2'b10;
    end
    else if (b_dn_tick) begin
        mux <= 2'b11;
    end
end

always @(posedge clk_fast or negedge reset) begin
    if (reset == 0) begin
        period <= 32'd0;
    end
    else if (mux == 2'b00) begin
        if (perd_b_up[31] && ~perd_b_up[29]) begin
            period <= {perd_b_up[31:29], 2'b00, perd_b_up[26:0]};
		  end 
		  else begin
            period <= {perd_a_up[31:29], 2'b00, perd_a_up[26:0]};
		  end
    end
    else if (mux == 2'b01) begin
        if (perd_a_dn[31] && ~perd_a_dn[29]) begin
				period <= {perd_a_dn[31:29], 2'b00, perd_a_dn[26:0]};
		  end 
		  else begin
            period <= {perd_b_up[31:29], 2'b00, perd_b_up[26:0]};
		  end
    end
    else if (mux == 2'b10) begin
        if (perd_b_dn[31] && ~perd_b_dn[29]) begin
				period <= {perd_b_dn[31:29], 2'b00, perd_b_dn[26:0]};
		  end 
		  else begin
            period <= {perd_a_dn[31:29], 2'b00, perd_a_dn[26:0]};
		  end
    end
	 else if (mux == 2'b11) begin
        if (perd_a_up[31] && ~perd_a_up[29]) begin
				period <= {perd_a_up[31:29], 2'b00, perd_a_up[26:0]};
		  end 
		  else begin
            period <= {perd_b_dn[31:29], 2'b00, perd_b_dn[26:0]};
		  end
    end
end

endmodule


