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

wire hub_reg_addr;
// Hub register address space is 0x1800 - 0x1803
assign hub_reg_addr = (reg_waddr[15:12]==`ADDR_HUB) && (reg_waddr[11:2] == 10'b1000000000);

// Currently, only writable register is at 0x1800
assign hub_reg_wen = (reg_wen && hub_reg_addr && (reg_waddr[1:0] == 2'd0));

// read_index maintains an ordered list of boards in use, so that it is no longer necessary
// for the PC to read the entire hub memory.
reg[3:0] read_index[0:15];
reg[3:0] curIndex;
reg[3:0] curBoard;
reg newMask;

wire[31:0] reg_rdata_mem;
assign reg_rdata = !hub_reg_addr ? reg_rdata_mem :
                   (reg_raddr[1:0] == 2'b00) ? {sequence, board_mask} :
                   (reg_raddr[1:0] == 2'b01) ? { read_index[ 0], read_index[ 1], read_index[ 2], read_index[ 3],
                                                 read_index[ 4], read_index[ 5], read_index[ 6], read_index[ 7] } :
                   (reg_raddr[1:0] == 2'b10) ? { read_index[ 8], read_index[ 9], read_index[10], read_index[11],
                                                 read_index[12], read_index[13], read_index[14], read_index[15] } :
                   32'd0;

always @(posedge(sysclk))
begin
    if (hub_reg_wen) begin
        sequence <= reg_wdata[31:16];
        board_mask <= reg_wdata[15:0];
        curIndex <= 4'd0;
        curBoard <= 4'd0;
        // Avoid board_mask==0 because that will infinite loop
        newMask <= (reg_wdata[15:0] == 16'd0) ? 0 : 1;
    end
    else if (newMask) begin
       if (board_mask[curBoard]) begin
          read_index[curIndex] <= curBoard;
          curIndex <= curIndex + 4'd1;
          // We loop until curIndex is 15; this means that read_index will repeat.
          // For example, if boards 0, 5, 7 are present, read_index will be:
          //    (0, 5, 7, 0, 5, 7, 0, 5, 7, 0, 5, 7, 0, 5, 7, 0)
          if (curIndex == 4'hf)
             newMask <= 0;
       end
       curBoard <= curBoard + 4'd1;
    end
end

wire hub_mem_wen;
assign hub_mem_wen = (reg_wen & (reg_waddr[15:12]==`ADDR_HUB) && (reg_waddr[11:9]==3'd0));

wire[8:0] read_addr;
assign read_addr = { read_index[reg_raddr[8:5]], reg_raddr[4:0] };

// NOTE
//   port a: write port
//   port b: read port
hub_mem_gen hub_mem(
    .clka(sysclk),
    .wea(hub_mem_wen),
    .addra(reg_waddr[8:0]),
    .dina(reg_wdata),
    .clkb(sysclk),
    .addrb(read_addr),
    .doutb(reg_rdata_mem)
);

endmodule
