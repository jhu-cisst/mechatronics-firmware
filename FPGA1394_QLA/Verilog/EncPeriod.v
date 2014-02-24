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


// ---------- Peter ------------------
module EncPeriod(
    input wire clk_fast,    // count this clock between encoder ticks
    input wire reset,       // global reset signal
    input wire ticks,       // encoder transition signal
    input wire dir,         // direction of the ticks
    output reg[15:0] count  // number clk_fast periods per tick
);

    // local registers
    reg[15:0] count_temp;     // register for counter
    reg[15:0] count_2;        // intermediate count register

    // overflow value for signed 16-bit number
    parameter overflow = 16'h8000;

// set count to 0 on overflow
//   - PC code check 0 value
always @(posedge clk_fast)
begin
    if (count_temp != overflow) begin
        count <= count_2;
    end        
    else begin
        count <= 16'd0;
    end        
end


// Convert ticks to pulse
reg dir_r;      // dir start 
reg ticks_r;    // previous ticks
wire ticks_en = ticks & (~ticks_r);
always @(posedge clk_fast)
begin
    ticks_r <= ticks;
end

// Latch count value to count_2
always @(posedge ticks_en or negedge reset)
begin
    if ((reset == 0) || (dir != dir_r))
        count_2 <= 16'd0;
    else
        count_2 <= count_temp;
end

// up/down counter to measure period between encoder ticks
always @(posedge ticks_en or posedge clk_fast)
begin
    if (ticks_en) begin
        count_temp <= 16'd0;
        dir_r <= dir;
    end
    else if (count_temp != overflow)
        count_temp <= count_temp + (dir ? 1'b1 : -1'b1);
end


//wire[35:0] control0;
//////
////// icon
//icon_prom icon1(
//   .CONTROL0(control0)
//);
//
//ila_enc ilaenc(
//    .CONTROL(control0),
//    .CLK(clk_fast),
//    .TRIG0(ticks),        //  8-bit
//    .TRIG1(count),        // 16-bit
//    .TRIG2(count_temp)    // 16-bit
//);

endmodule



// -------------------------------------------------
// Quad Ticks Version
// 
// module EncPeriodQuad(
//     input clk_fast,           // count this clock between encoder ticks
//     input reset,              // global reset signal
//     input wire a,             // quad encoder line a
//     input wire b,             // quad encoder line b
//     output wire[31:0] period   // number clk_fast periods per tick
// );

//     // local registers
//     reg[15:0] cnter;          // register for counter
//     reg[15:0] cnter_prev;     // register for previous counter value

//         // signals for encoder state
//     wire[1:0] code;         // value formed from concatenated encoder lines
//     reg[1:0] prev;          // used to remember the previously received code
//     reg code_changed;      // indicates if encoder has moved since prev clk
//     reg dir;

//     // overflow value for signed 16-bit number
//     parameter overflow = 16'hFFFF;  

// //------------------------------------------------------------------------------
// // hardware description
// //
// assign code = { a, b };
// //assign code_changed = code[1] ^ prev[1] ^ code[0] ^ prev[0];
// always @(posedge(clk_fast)) begin 
//     prev <= code;    // ? maybe sysclk
//     code_changed <= code[1] ^ prev[1] ^ code[0] ^ prev[0];
// end

// always @(posedge clk_fast) begin
//     if (code_changed) dir <= code[1] ^ prev[0];
// end

// // assign value to period
// assign period = {cnter_prev[15:0], cnter[15:0]};
// // assign period = {16'h1234, cnter[15:0]};

// //always @(posedge code_changed or negedge reset) begin
// //    if (reset == 0) begin
// //        cnter_prev <= 0;
// //    end
// //    else 
// //end

// // counter 
// always @(posedge code_changed or posedge clk_fast) begin
//     if (code_changed) begin
//         cnter_prev <= cnter;
//         cnter <= 0;          
//     end        
//     else if (cnter != overflow) begin
//         cnter <= cnter + 1'b1;        
//     end        
// end

// endmodule


