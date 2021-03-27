/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2013-2021 ERC CISST, Johns Hopkins University.
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
    output wire       hub_reg_wen, // broadcast request received (write to register)
    input wire[3:0]   board_id,    // board id
    output reg        write_trig,  // request to broadcast this board's info via FireWire
    input wire        write_trig_reset, // reset write_trig
    input wire        fw_idle,     // whether Firewire state machine is idle
    output wire       updated      // hub has been updated since last query (write to 0x1800)
);

wire hub_reg_waddr;
// Hub register address space is 0x1800 - 0x1803
assign hub_reg_waddr = (reg_waddr[15:12]==`ADDR_HUB) && (reg_waddr[11:2] == 10'b1000000000);

// Currently, only writable register is at 0x1800
assign hub_reg_wen = (reg_wen && hub_reg_waddr && (reg_waddr[1:0] == 2'd0));

// For timing measurements. Cleared when broadcast query command received (i.e., quadlet write to 0x1800).
reg[13:0] bcTimer;
reg[13:0] bcReadStart;

// Whether write_trig has been asserted for this broadcast read cycle
reg write_trig_done;

// read_index maintains an ordered list of boards in use, so that it is no longer necessary
// for the PC to read the entire hub memory.
reg[3:0] read_index[0:15];
reg[3:0] curIndex;
reg[3:0] curBoard;
reg[15:0] last_mask;

// Indicates whether board has been updated
reg[15:0] board_updated;

assign updated = (board_updated == board_mask) ? 1'b1 : 1'b0;

wire[15:0] board_mask_lower;  // only boards with lower board ids
assign board_mask_lower = ((16'b1 << board_id) - 16'b1) & board_mask;

assign board_selected = board_mask[board_id];

wire hub_reg_raddr;
// Hub register address space is 0x1800 - 0x1803
assign hub_reg_raddr = (reg_raddr[15:12]==`ADDR_HUB) && (reg_raddr[11:2] == 10'b1000000000);

wire[31:0] reg_rdata_hub;
assign reg_rdata = !hub_reg_raddr ? reg_rdata_hub :
                   (reg_raddr[1:0] == 2'b00) ? {sequence, board_mask} :
                   (reg_raddr[1:0] == 2'b01) ? { read_index[ 0], read_index[ 1], read_index[ 2], read_index[ 3],
                                                 read_index[ 4], read_index[ 5], read_index[ 6], read_index[ 7] } :
                   (reg_raddr[1:0] == 2'b10) ? { read_index[ 8], read_index[ 9], read_index[10], read_index[11],
                                                 read_index[12], read_index[13], read_index[14], read_index[15] } :
                   { 12'd0, board_id, board_mask_lower };

always @(posedge(sysclk))
begin
    bcTimer <=  bcTimer + 14'd1;
    if (hub_reg_wen) begin
        sequence <= reg_wdata[31:16];
        if (reg_wdata[15:0] != 16'd0) begin
            // Avoid board_mask==0 because that will infinite loop
            board_mask <= reg_wdata[15:0];
            curIndex <= 4'd0;
            curBoard <= 4'd0;
        end
        bcTimer <=  14'd0;
        board_updated <= 16'd0;
        write_trig <= 0;
        write_trig_done <= 0;
    end
    else if (board_mask != last_mask) begin
       if (board_mask[curBoard]) begin
          read_index[curIndex] <= curBoard;
          curIndex <= curIndex + 4'd1;
          // We loop until curIndex is 15; this means that read_index will repeat.
          // For example, if boards 0, 5, 7 are present, read_index will be:
          //    (0, 5, 7, 0, 5, 7, 0, 5, 7, 0, 5, 7, 0, 5, 7, 0)
          if (curIndex == 4'hf) begin
             last_mask <= board_mask;
             bcTimer <= 14'd0;
          end
       end
       curBoard <= curBoard + 4'd1;
    end
    else if (write_trig_reset) begin
       write_trig <= 0;
    end
    else if (board_selected && !write_trig_done) begin
       // write_trig is sent to Firewire module to start broadcast write of hub data from this board to
       // all other boards. Note that writing is done sequentially, by board number.
       if (board_mask_lower == 16'd0) begin
          // First board: wait 150 cycles (~3 usec)
          if (bcTimer == 14'd150) begin
             write_trig <= 1;
             write_trig_done <= 1;
          end
       end
       else if ((board_updated == board_mask_lower) && fw_idle) begin
          write_trig <= 1;
          write_trig_done <= 1;
       end
    end
    if (hub_mem_wen) begin
       // Start of board update; could check for (reg_waddr[4:0] == (NUM_QUADS-1)) if we
       // wish to know when update is finished.
       board_updated[reg_waddr[8:5]] <= 1'b1;
    end
end

wire hub_mem_wen;
assign hub_mem_wen = (reg_wen & (reg_waddr[15:12]==`ADDR_HUB) && (reg_waddr[11:9]==3'd0));

// Number of quadlets per entry (29)
localparam[8:0] NUM_QUADS = `NUM_BC_READ_QUADS;
// Offset to skip to next entry (32-29 = 3)
localparam[8:0] QUAD_OFFSET = (9'd32-`NUM_BC_READ_QUADS);

//*************************** Read address translation ********************************
//
// The following code allows the Firewire and Ethernet modules to sequentially address
// Hub memory, rather than having to read the precise number of quadlets for each board
// (currently 29) and then skip to the next board.
//
// The implementation assumes that the hub read will start at address 0. It should actually
// work for any start address up to the number of quadlets per board (29).
//
// Note that multNQ and offset are initialized when writing to the hub register (i.e., by
// the broadcast query command) or when starting to read from address 0. The latter case
// allows reading the hub multiple times after the broadcast query command, as long as
// the start address is 0. Note that it is also possible to do partial reads, as long as
// the reads cover contiguous memory. For example, one can read from 0 to 57, then from 58
// to 86, etc.

// Multiple of number of quadlets per entry (e.g., 29, 58, 87, ...)
reg[8:0] multNQ;
initial multNQ = NUM_QUADS;

// Offset to add to reg_raddr
reg[8:0] offset;

always @(posedge sysclk)
begin
   if (hub_reg_wen || ((reg_raddr[15:12] == `ADDR_HUB) && (reg_raddr[8:0] == 9'd0))) begin
      // Also check for 0 address to handle reading again
      multNQ <= NUM_QUADS;
      offset <= 9'd0;
      if (~hub_reg_wen)
         bcReadStart <= bcTimer;
   end
   else if ((reg_raddr[15:12] == `ADDR_HUB) && (reg_raddr[8:0] == multNQ)) begin
      multNQ <= multNQ + NUM_QUADS;
      offset <= offset + QUAD_OFFSET;
   end
end

wire[8:0] reg_raddr_offset;
assign reg_raddr_offset = (reg_raddr[8:0] == multNQ) ? { reg_raddr[8:0] + offset + QUAD_OFFSET }
                                                     : { reg_raddr[8:0] + offset };

// Board number being read
wire[3:0] read_board;
assign read_board = read_index[reg_raddr_offset[8:5]];

// The block read packet has an extra data field at the end, which contains timing information.
// We detect this address when read_board repeats. Note that the first conditional could instead
// be (multNQ != NUM_QUADS). The implementation could easily be extended to return up to NUM_QUADS
// extra fields.
wire is_extra;
assign is_extra = ((offset != 9'd0) && (read_board == read_index[0])) ? 1'b1 : 1'b0;

wire[8:0] read_addr;
assign read_addr = { read_board, reg_raddr_offset[4:0] };

wire[31:0] reg_rdata_mem;

assign reg_rdata_hub = is_extra ? { 2'b0, bcReadStart, 2'b0, bcTimer }
                        : reg_rdata_mem;

// When writing first board quadlet, replace lowest 16 bits as follows:
//   Bits 15:14 are not currently used (0)
//   Bits 13:0  indicate the time when the board was updated (relative to the query command)
wire[31:0] reg_wdata_mem;
assign reg_wdata_mem = (reg_waddr[4:0] == 5'd0) ? { reg_wdata[31:16], 2'b00, bcTimer }
                                                : reg_wdata;

//********************************* Hub memory **************************************
// NOTE
//   port a: write port
//   port b: read port
hub_mem_gen hub_mem(
    .clka(sysclk),
    .wea(hub_mem_wen),
    .addra(reg_waddr[8:0]),
    .dina(reg_wdata_mem),
    .clkb(sysclk),
    .addrb(read_addr),
    .doutb(reg_rdata_mem)
);

endmodule
