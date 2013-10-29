/*******************************************************************************
 *
 * Copyright(C) 2011 ERC CISST, Johns Hopkins University.
 *
 * Module: HubReg
 *
 * Purpose: Register Space for Hub Capabilit
 * 
 * Revision history
 *     09/14/13    Zihan Chen    Initial revision - ICRA14
 */

`include "Constants.v"

module HubReg(
    input  wire sysclk,            // system clk 
    input  wire reset,             // system reset 
    input  wire reg_wen,           // hub reg write enable 
    input  wire[15:0] reg_raddr,    // hub reg addr 10-bit
    input  wire[15:0] reg_waddr,    // hub reg addr 10-bit
    output wire[31:0] reg_rdata,   // hub outgoing read data 
    input  wire[31:0] reg_wdata    // hub incoming write data 
);

reg[31:0] hub_mem[511:0];         // 16x32, 16: max boards, 32: max quads


// reg_raddr[8:5] = board id 
// reg_raddr[4:0] = quad index
assign reg_rdata = hub_mem[reg_raddr[8:0]];


// handle register write
always @(posedge(sysclk) or negedge(reset))
begin
    if (reset==0) begin
        hub_mem[0] <= 32'h05;    // debug data 
        hub_mem[169] <= 32'h99;  // debug data 
    end
    else begin
        if (reg_wen && reg_waddr[15:12]==`ADDR_HUB) begin
             hub_mem[reg_waddr[8:0]] <= reg_wdata;
        end
    end
end

endmodule