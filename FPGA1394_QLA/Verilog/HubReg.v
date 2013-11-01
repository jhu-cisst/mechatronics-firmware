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
    input  wire reg_wen,           // hub reg write enable 
    input  wire[15:0] reg_raddr,    // hub reg addr 10-bit
    input  wire[15:0] reg_waddr,    // hub reg addr 10-bit
    output wire[31:0] reg_rdata,   // hub outgoing read data 
    input  wire[31:0] reg_wdata    // hub incoming write data 
);

wire hub_mem_wen;
assign hub_mem_wen = (reg_wen & (reg_waddr[15:12]==`ADDR_HUB));

// NOTE
//   port a: write port
//   port b: read port
hub_mem_gen hub_mem(
    .clka(sysclk),       
    .wea(hub_mem_wen),
    .addra(reg_waddr[8:0]),
    .dina(reg_wdata),
    .clkb(sysclk),
    .addrb(reg_raddr[8:0]),
    .doutb(reg_rdata)
);


// -------------------
// chipscope
// -------------------
// wire[35:0] control0;
// icon_hub icon(
//     .CONTROL0(control0)
// );
// ila_hub ila(
//     .CONTROL(control0),
//     .CLK(sysclk),
//     .TRIG0(reg_wen),
//     .TRIG1(reg_raddr),
//     .TRIG2(reg_waddr),
//     .TRIG3(reg_rdata),
//     .TRIG4(reg_wdata),
//     .TRIG5(reg_wdata)
// );

endmodule