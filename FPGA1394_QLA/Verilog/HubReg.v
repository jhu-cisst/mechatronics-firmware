/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2013-2024 ERC CISST, Johns Hopkins University.
 *
 * Module: HubReg
 *
 * Purpose: Register Space for Hub Capability
 * 
 * Revision history
 *     09/14/13    Zihan Chen         Initial revision - ICRA14
 *     07/23/20    Peter Kazanzides   Added sequence/board_mask registers
 *     06/13/22    Peter Kazanzides   V8 implementation
 */

`include "Constants.v"

module HubReg
    #(parameter USE_FW = 1)        // Whether or not to trigger Firewire transactions
(
    input  wire sysclk,            // system clk
    input  wire reg_wen,           // hub memory write enable
    input  wire[15:0] reg_raddr,   // hub reg addr 9-bit
    input  wire[15:0] reg_waddr,   // hub reg addr 9-bit
    output wire[31:0] reg_rdata,   // hub outgoing read data
    input  wire[31:0] reg_wdata,   // hub incoming write data
    output wire reg_rwait,         // hub read wait state
    output reg[15:0]  sequence,    // sequence number received via read request
    input wire[3:0]   board_id,    // board id
    output reg        write_trig,  // request to broadcast this board's info via FireWire
    input wire        write_trig_reset, // reset write_trig
    input wire        fw_idle,     // whether Firewire state machine is idle
    output wire       updated      // hub has been updated since last query (write to 0x1800)
);

// Writing to hub register or memory
wire hub_wen;
assign hub_wen = (reg_wen && (reg_waddr[15:12]==`ADDR_HUB));

// Currently, only writable register is at 0x1800
wire hub_reg_wen;
assign hub_reg_wen = (hub_wen && (reg_waddr[11:0] == 12'b100000000000));

// Memory write is 0x10NN, where NN is the quadlet index (up to 256 quadlets, though
// current implementation requires fewer quadlets)
wire hub_mem_wen;
assign hub_mem_wen = (reg_wen & (reg_waddr[15:12]==`ADDR_HUB) && (reg_waddr[11:8]==4'd0));

// Address offset when writing to memory. This is initialized when writing to the hub register
// (i.e., by the broadcast query command).
reg[8:0] reg_waddr_offset;
reg[7:0] last_reg_waddr;
reg      offset_updated;

// Current block size being written
reg[7:0] block_size;

wire[8:0] write_addr;
assign write_addr = ((reg_waddr[7:0] == 8'd0) && !offset_updated) ? (reg_waddr_offset + {1'b0, block_size})
                                                                  : (reg_waddr_offset + {1'b0, reg_waddr[7:0]});

// Saves last write address (last_write_addr+1 is the number of quadlets written)
reg[8:0] last_write_addr;

wire[8:0] num_written;
assign num_written = last_write_addr + 9'd1;

// For timing measurements. Cleared when broadcast query command received (i.e., quadlet write to 0x1800).
// Firmware Rev 9 increased timer from 14-bits to 16-bits
// 16 bits measures up to 1333.3 us when sysclk is 49.152 MHz and up to 524.3 us when sysclk is 125 MHz
// Note that the update times (times when data written to Hub memory) are the lower 15 bits
reg[15:0] bcTimer;
reg[15:0] bcReadStart;

// Whether write_trig has been asserted for this broadcast read cycle
reg write_trig_done;

// board mask received via read request
reg[15:0] board_mask;

// Indicates whether board has been updated
reg[15:0] board_updated;

assign updated = (board_updated == board_mask) ? 1'b1 : 1'b0;

wire[15:0] board_mask_lower;  // only boards with lower board ids
assign board_mask_lower = ((16'b1 << board_id) - 16'b1) & board_mask;

assign board_selected = board_mask[board_id];

wire hub_reg_raddr;
// Hub register read address space is 0x1800 - 0x1803
assign hub_reg_raddr = (reg_raddr[15:12]==`ADDR_HUB) && (reg_raddr[11:2] == 10'b1000000000);

wire[31:0] reg_rdata_hub;
wire reg_rwait_hub;
assign {reg_rdata, reg_rwait} =
                   !hub_reg_raddr ? {reg_rdata_hub, reg_rwait_hub} :
                   (reg_raddr[1:0] == 2'b00) ? {sequence, board_mask, 1'b0} :                           // 0x1800
                   (reg_raddr[1:0] == 2'b01) ? { 8'd0, last_reg_waddr, 7'd0, reg_waddr_offset, 1'b0} :  // 0x1801
                   (reg_raddr[1:0] == 2'b10) ? { 23'd0, num_written, 1'b0} :                            // 0x1802
                   { 12'd0, board_id, board_mask_lower, 1'b0 };                                         // 0x1803

always @(posedge(sysclk))
begin
    bcTimer <=  bcTimer + 16'd1;
    if (hub_reg_wen) begin
        sequence <= reg_wdata[31:16];
        board_mask <= reg_wdata[15:0];
        bcTimer <=  16'd0;
        board_updated <= 16'd0;
        write_trig <= 0;
        write_trig_done <= 0;
        // Initialize for writing to memory
        reg_waddr_offset <= 9'd0;
        last_reg_waddr <= 8'hff;
        last_write_addr <= 9'h1ff;
        block_size <= 8'd0;
        offset_updated <= 0;
    end
    else if (hub_mem_wen) begin
        if (reg_waddr[7:0] != last_reg_waddr) begin
            last_reg_waddr <= reg_waddr[7:0];
            last_write_addr <= write_addr;
            offset_updated <= 0;
            if (reg_waddr[7:0] == 8'd0) begin
                // Writing of header. Get block size from bits 7:0
                block_size <= reg_wdata[7:0];
                // Update address offset
                reg_waddr_offset <= reg_waddr_offset + {1'b0, block_size};
                offset_updated <= 1;
            end
            else if (reg_waddr[7:0] == 8'd2) begin
                // Writing of status field. Get board number from bits 27:24
                board_updated[reg_wdata[27:24]] <= 1'b1;
            end
        end
    end

    if (reg_raddr == {`ADDR_HUB, 12'd0}) begin
        bcReadStart <= bcTimer;
    end

    if (USE_FW) begin
        if (write_trig_reset) begin
            write_trig <= 0;
        end
        else if (board_selected && !write_trig_done) begin
            // write_trig is sent to Firewire module to start broadcast write of real-time block data from this board to all
            // other boards; while doing this, the Firewire module also writes the real-time block data to the hub memory (hub_mem).
            // Note that writing is done sequentially, by board number.
            if (board_mask_lower == 16'd0) begin
                // First board: wait 150 cycles (~3 usec)
                if (bcTimer == 16'd150) begin
                    write_trig <= 1;
                    write_trig_done <= 1;
                end
            end
            else if ((board_updated == board_mask_lower) && fw_idle) begin
                write_trig <= 1;
                write_trig_done <= 1;
            end
        end
    end
end


// The block read packet has an extra data field at the end, which contains timing information.
// We only provide this field if the broadcast read completed successfully (updated).
wire is_extra;
assign is_extra = (updated && (reg_raddr[8:0] == num_written)) ? 1'b1 : 1'b0;

wire read_addr_ok;
assign read_addr_ok = (reg_raddr[8:0] < num_written) ? 1'b1 : 1'b0;

wire[31:0] reg_rdata_mem;

assign {reg_rdata_hub, reg_rwait_hub} =
                       is_extra ? { bcReadStart, bcTimer, 1'b0 } :
                       read_addr_ok ? {reg_rdata_mem, 1'b1} : {32'd0, 1'b0};

// When writing first board quadlet, rearrange bits to obtain following:
//      | Block Size (8) | Sequence LSB (8) | Seq Error (1) | 0 | Update Time (14) |
// Block Size (bits 31:24) is the size of the block in quadlets (including this header quadlet)
// Sequence LSB (bits 23:16) is the lowest byte of the 16-bit sequence number sent by the PC
// Seq Error (bit 15) is 1 if the full 16-bit sequence numbers do not match
// Update Time (bits 14:0) indicate the time when the board was updated (relative to the query command)
wire[31:0] reg_wdata_mem;
wire sequence_error;
assign sequence_error = (sequence == reg_wdata[31:16]) ? 1'b0 : 1'b1;
assign reg_wdata_mem = (reg_waddr[7:0] == 8'd0) ? { reg_wdata[7:0], reg_wdata[23:16], sequence_error, bcTimer[14:0] }
                                                : reg_wdata;

//********************************* Hub memory **************************************
// NOTE
//   port a: write port
//   port b: read port
DPRAM_32x512_sclk hub_mem(
    .clka(sysclk),
    .wea(hub_mem_wen),
    .addra(write_addr),
    .dina(reg_wdata_mem),
    .clkb(sysclk),
    .addrb(reg_raddr[8:0]),
    .doutb(reg_rdata_mem)
);

endmodule
