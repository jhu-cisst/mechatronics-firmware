/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2013-2020 ERC CISST, Johns Hopkins University.
 *
 * Module: HubReg
 *
 * Purpose: Register Space for Hub Capability
 * 
 * Revision history
 *     09/14/13    Zihan Chen         Initial revision - ICRA14
 *     07/23/20    Peter Kazanzides   Added sequence/board_mask registers
 */

`include "Constants.v"

module HubReg(
    input  wire sysclk,            // system clk
    input  wire reg_wen,           // hub memory write enable
    input  wire[15:0] reg_raddr,   // hub reg addr 9-bit
    input  wire[15:0] reg_waddr,   // hub reg addr 9-bit
    output wire[31:0] reg_rdata,   // hub outgoing read data
    input  wire[31:0] reg_wdata,   // hub incoming write data
    output reg[15:0]  sequence,    // sequence number received via read request
    output reg[15:0]  board_mask,  // board mask received via read request
    output wire       hub_reg_wen  // broadcast request received (write to register)
);

assign hub_reg_wen = (reg_wen & (reg_waddr[15:12]==`ADDR_HUB) && (reg_waddr[11:0]==12'h800));

wire[31:0] reg_rdata_mem;
assign reg_rdata = (reg_raddr[11:0]==12'h800) ? {sequence, board_mask} : reg_rdata_mem;

always @(posedge(sysclk))
begin
    if (hub_reg_wen) begin
        sequence <= reg_wdata[31:16];
        board_mask <= reg_wdata[15:0];
    end
end

wire hub_mem_wen;
assign hub_mem_wen = (reg_wen & (reg_waddr[15:12]==`ADDR_HUB) && (reg_waddr[11:9]==3'd0));

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
    .doutb(reg_rdata_mem)
);

endmodule
