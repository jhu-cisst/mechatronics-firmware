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
 */


// // ---------- Peter ------------------
// module EncPeriod(
//    input wire clk_fast,    // count this clock between encoder ticks
//    input wire reset,       // global reset signal
//    input wire ticks,       // encoder transition signal
//    input wire dir,         // direction of the ticks
//    output reg[15:0] count  // number clk_fast periods per tick
// );

//    // local registers
//    reg[15:0] count_temp;     // register for counter
//    reg[15:0] count_2;        // intermediate count register

//    // overflow value for signed 16-bit number
//    parameter overflow = 16'h8000;

// // set count to 0 on overflow
// //   - PC code check 0 value
// always @(posedge clk_fast)
// begin
//    if (count_temp != overflow)
//        count <= count_2;
//    else 
//        count <= 16'd0;
// end


// // Convert ticks to pulse
// reg dir_r;      // dir start 
// reg ticks_r;    // previous ticks
// wire ticks_en = ticks & (~ticks_r);
// always @(posedge clk_fast)
// begin
//    ticks_r <= ticks;
// end

// // Latch count value to count_2
// always @(posedge ticks_en or negedge reset)
// begin
//    if ((reset == 0) || (dir != dir_r))
//        count_2 <= 16'd0;
//    else
//        count_2 <= count_temp;
// end

// // up/down counter to measure period between encoder ticks
// always @(posedge ticks_en or posedge clk_fast)
// begin
//    if (ticks_en) begin
//        count_temp <= 16'd0;
//        dir_r <= dir;
//    end
//    else if (count_temp != overflow)
//        count_temp <= count_temp + (dir ? 1'b1 : -1'b1);
// end

// endmodule


// -------------------------------------------------
// Quad Ticks Version
// 
// module EncPeriodQuad(
//     input clk,                // sysclk
//     input reset,              // global reset signal
//     input wire a,             // quad encoder line a
//     input wire b,             // quad encoder line b
//     output wire[31:0] period, // num of fast clock ticks 
//     inout wire[35:0] control0 // cp debug control line
// );

//     // 16 bits + 6 bit for time dividing
//     reg[21:0] cnter;    // number clk periods per tick
//     reg[21:0] cnter_prev;  // previous cnter value 

//     // signals for encoder state
//     wire[1:0] code;         // value formed from concatenated encoder lines
//     reg[1:0] prev;          // used to remember the previously received code
//     wire  code_changed;      // indicates if encoder has moved since prev clk
//     reg dir;

//     // overflow value for signed 22-bit number
//     parameter overflow = 22'h200000;     // max 3fffff

// //------------------------------------------------------------------------------
// // hardware description
// //
// assign code = { a, b };
// assign code_changed = code[1] ^ prev[1] ^ code[0] ^ prev[0];
// always @(posedge(clk)) prev <= code;

// // always @(posedge(clk)) begin 
// //     prev <= code;    // ? maybe sysclk
// //     code_changed <= code[1] ^ prev[1] ^ code[0] ^ prev[0];
// // end

// always @(posedge clk) begin
//     if (code_changed) dir <= code[1] ^ prev[0];
// end

// // assign value to period
// assign period = {cnter_prev[21:6], cnter[21:6]};

// always @(posedge code_changed or negedge reset) 
// begin
//     if (reset == 0) begin
//         cnter_prev <= 22'd0;
//     end
//     else begin
//         cnter_prev <= cnter;
//     end
// end

// // counter 
// always @(posedge code_changed or posedge clk) begin
//     if (code_changed) begin
//         cnter <= 0;          
//     end        
//     else if (cnter != overflow) begin
//         // cnter <= cnter + 1'b1;
//         cnter <= cnter + (dir ? 1'b1 : -1'b1);
//     end        
// end

// ila_enc ilaenc(
//     .CONTROL(control0),
//     .CLK(clk),
//     .TRIG0(code_changed),  //  8-bit
//     .TRIG1(cnter[21:6]),         // 16-bit
//     .TRIG2(cnter_prev[21:6])     // 16-bit
// );

// endmodule


// ---------- Peter ------------------
module EncPeriod(
   input wire clk_fast,     // count this clock between encoder ticks
   input wire reset,        // global reset signal
   input wire ticks,        // encoder transition signal
   input wire dir,          // direction of the ticks
   output wire ticks_en,    // edge signal 
   output wire[31:0] count  // number clk_fast periods per tick
);

    // local registers 
    reg[15:0] cnter;        // cnter current value
    reg[15:0] cnter_latch;  // latched cnter value

    // overflow value for signed 16-bit number
    parameter overflow = 16'h8000;


//------------------------------------------------------------------------------
// hardware description
//

// assign count value 
assign count = {cnter_latch, cnter};

// convert ticks to pulse
reg dir_r;      // dir start 
reg ticks_r;    // previous ticks
assign ticks_en = ticks & (~ticks_r);
always @(posedge clk_fast) 
begin
   ticks_r <= ticks;
end

// latch previous dir 
always @(posedge ticks_en) begin
    dir_r <= dir;
end

// latch cnter value 
always @(posedge ticks_en or negedge reset)
begin
    if (reset == 0) begin
        cnter_latch <= 16'd0;
    end
    else if (dir != dir_r) begin  
        // dir changed set to overflow
        cnter_latch <= overflow;  
    end    
    else begin
        cnter_latch <= cnter;
    end
end

// counter 
always @(posedge clk_fast or posedge ticks_en or negedge reset) begin
    if (reset == 0 || ticks_en) begin
        cnter <= 16'd0;
    end
    else if (cnter != overflow) begin
        cnter <= cnter + (dir ? 1'b1 : -1'b1);    
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
    output reg[31:0] period, // num of fast clock ticks 
    inout wire[35:0] control0 // cp debug control line
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
    else if (a_dn_tick) begin
        mux <= 2'b01;    
    end    
    else if (b_up_tick) begin
        mux <= 2'b10;
    end
    else if (b_dn_tick) begin
        mux <= 2'b11;
    end
end

always @(posedge clk or negedge reset) begin
    if (reset == 0) begin
        period <= 32'd0;
    end
    else if (mux == 2'b00) begin
        period <= perd_a_up;
    end
    else if (mux == 2'b01) begin
        period <= perd_a_dn;
    end
    else if (mux == 2'b10) begin
        period <= perd_b_up;
    end
    else if (mux == 2'b11) begin
        period <= perd_b_dn;
    end
end

endmodule


