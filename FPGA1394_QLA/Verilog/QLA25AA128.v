/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2012-2013 ERC CISST, Johns Hopkins University.
 *
 * Module: QLA25AA128
 *
 * Purpose: Program the 25AA138 PROM on QLA board
 * 
 * NOTE: 
 *   - only supports byte read/write 
 *   - block read/write may be supported base on
 *   - 25AA128 address space (16-bit)
 *     - bit 15:12 == `ADDR_PROM_QLA 
 *     - bit 11:8 == 0: byte wise operation
 *         - 0x3000: quadlet command (write)
 *         - 0x3001: prom_status (read)
 *         - 0x3002: prom_result (read)
 *     - bit 11:8 == 1: block read/write 
 *         - since 1 page is 64 bytes, we only support 64 bytes read/write
 *   - Clock
 *     - 25AA128 Max 10 Mhz
 *     - sysclk 49.125 Mhz / 8 
 * 
 * Revision history
 *     12/31/12    Peter Kazanzides    Initial revision from M25P16
 *     10/24/13    Zihan Chen          Revised for 25AA128 SPI PROM
 */


// ---------------------------------------------------
// 25AA128 PROM SPI Command (Datasheet P7 Table 2-1)
// 

`include "Constants.v"

// ---------------------------------------------------
// 25AA128 PROM SPI Command (Datasheet P7 Table 2-1)
// 
`define CMD_READ_25AA128   8'h03    // Read
`define CMD_WRIT_25AA128   8'h02    // Write
`define CMD_WRDI_25AA128   8'h04    // Write Disable
`define CMD_WREN_25AA128   8'h06    // Write Enable
`define CMD_RDSR_25AA128   8'h05    // Read STATUS register
`define CMD_WRSR_25AA128   8'h01    // Write STATUS register
`define CMD_IDLE_25AA128   8'h00    // IDLE N/A cmd 

`define REG_PROM_CMD       12'h000  // prom command (write)
`define REG_PROM_STATUS    12'h001  // prom status (read)  
`define REG_PROM_RESULT    12'h002  // prom result (read)


module QLA25AA128(
    input  clk,                    // input clock
    input  reset,                  // global reset signal    

    input  wire[15:0] reg_raddr,   // read address
    input  wire[15:0] reg_waddr,   // write address
    output reg[31:0]  reg_rdata,   // register read data
    input  wire[31:0] reg_wdata,   // register write data 
    input  wire reg_wen,           // reg write enable
    input  wire blk_wen,           // block write enable
    input  wire blk_wstart,        // block write start

    // spi pins
    output prom_mosi,              // Serial out to 25AA128
    input  prom_miso,              // Serial in from 25AA128
    output prom_sclk,              // CLK to 25AA128
    output reg prom_cs             // /CS to 25AA128
);

// State machine
parameter ST_IDLE = 0,
          ST_CHIP_SELECT = 1,
          ST_WRITE = 2,
          ST_WRITE_BLOCK = 3,
          ST_READ = 4,
          ST_CHIP_DESELECT = 5,
          ST_IO_DISABLE = 6;


reg       io_disabled;
reg[2:0]  state;
reg[9:0]  seqn;            // 10-bit counter for sequencing operation (clock)
reg[9:0]  SendCnt;         // (2*NumBits)*8-1
reg[9:0]  RecvCnt;         // (2*NumBits)*8-1 (0 if no bits to receive)
reg[5:0]  RecvQuadCnt;     // Number of quadlets to read, minus 1
reg[31:0] prom_data;       // data to write to PROM (shift register)
reg       blk_wrt;         // true if a block write is in progress (and hasn't been aborted due to an error)
reg[15:0] prom_debug;

reg[31:0] data_block[0:17];  // Up to 17 quadlets of data, received via block write
reg [4:0] wr_index;          // Current write index (5-bit), set from prom_blk_addr (6-bit),
                             // with wrap-around allowed
reg [4:0] rd_index;          // Current read index (5-bit), incremented in this module


// local wires
wire prom_reg_wen;       // main quadlet reg interface
wire prom_blk_enable;    // prom block interface
wire prom_blk_wen;
wire prom_blk_start;  
wire prom_blk_end;
wire[3:0] prom_blk_raddr;   // data block read address
wire[3:0] prom_blk_waddr;   // data block write address

assign prom_reg_wen = (reg_waddr == {`ADDR_PROM_QLA, `REG_PROM_CMD}) ? reg_wen : 1'b0;
assign prom_blk_enable = (reg_waddr[15:12] == `ADDR_PROM_QLA) ? 1'b1 : 1'b0;
assign prom_blk_wen = (reg_waddr[15:12] == `ADDR_PROM_QLA) ? reg_wen : 1'b0;
assign prom_blk_start = (reg_waddr[15:12] == `ADDR_PROM_QLA) ? blk_wstart : 1'b0;
assign prom_blk_end = (reg_waddr[15:12] == `ADDR_PROM_QLA) ? blk_wen : 1'b0;
assign prom_blk_raddr = reg_raddr[3:0];
assign prom_blk_waddr = reg_waddr[3:0];


// prom_status
wire[31:0] prom_status; 
reg[31:0] prom_result; 
assign prom_status[31:16] = prom_debug;
assign prom_status[15:9] = 7'd0;
assign prom_status[8] = io_disabled;
assign prom_status[7] = prom_cs;
assign prom_status[6] = prom_sclk;
assign prom_status[5] = prom_miso;
assign prom_status[4] = prom_mosi;
assign prom_status[3] = blk_wrt;
assign prom_status[2:0] = state;

assign prom_mosi = io_disabled ? 1'bz : prom_data[31];
assign prom_sclk = io_disabled ? 1'bz : seqn[3];    // sysclk/8




// -----------------------------------------
// read request
// ------------------------------------------
always @(posedge(clk) or negedge(reset))
begin
    if (reset == 0) begin
        reg_rdata <= 32'd0;                
    end
    else if (reg_raddr[11:8] == 4'h1) begin
        // block read, data is muxed in top module
        reg_rdata <= data_block[prom_blk_raddr];
    end
    else if (reg_raddr[11:8] == 4'h0) begin
        case (reg_raddr[11:0])
        `REG_PROM_RESULT: reg_rdata <= prom_result;
        `REG_PROM_STATUS: reg_rdata <= prom_status;
        // return 32'd0 by default
        default: reg_rdata <= 32'd0;
        endcase
    end
    else begin
        reg_rdata <= 32'd0;
    end
end



// -----------------------------------------
// processing 
// ------------------------------------------
always @(posedge(clk) or negedge(reset))
begin
    if (reset == 0) begin
        io_disabled <= 1'b1;
        prom_cs     <= 1'bz;
        prom_result <= 32'd0;
        prom_debug  <= 16'd0;
        blk_wrt     <= 1'b0;
        wr_index    <= 7'd0;
        rd_index    <= 7'd0;
        state       <= ST_IDLE;
    end

    else begin

        // handle block write
        if (prom_blk_wen && blk_wrt) begin       // receive one quadlet of the block write
            if (prom_blk_waddr == wr_index[3:0]) begin
                data_block[wr_index] <= reg_wdata;
                // Update write index
                wr_index <= wr_index + 1'b1;
            end
            else  begin // error, unexpected block write address
                prom_debug <= { 4'h0, prom_blk_waddr[3:0], 3'h0, wr_index[4:0] };
            end
        end
        else if (prom_blk_end) begin 
            // finish receiving data from block write; will still be writing to PROM
            blk_wrt <= 1'b0;
        end

        case (state)

        ST_IDLE: begin
           
          if (prom_reg_wen) begin
            seqn <= 7'd0;
            prom_data <= reg_wdata;
            blk_wrt <= 1'b0;
            wr_index <= 7'd0;
            case (reg_wdata[31:24])
               `CMD_IDLE_25AA128: begin    // Do nothing
               end
               `CMD_WREN_25AA128: begin    // Write Enable
                  SendCnt <= 10'd127;      // 2*8*8-1
                  RecvCnt <= 10'd0;
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               `CMD_WRDI_25AA128: begin    // Write Disable
                  SendCnt <= 10'd127;
                  RecvCnt <= 10'd0;
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               `CMD_RDSR_25AA128: begin    // Read Status Register
                  SendCnt <= 10'd127;      // 1-byte cmd
                  RecvCnt <= 10'd127;      // 1-byte SR
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               `CMD_WRSR_25AA128: begin    // Write Status Register
                  SendCnt <= 10'd255;      // 1-byte cmd + 1-byte SR
                  RecvCnt <= 10'd0;   
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               `CMD_READ_25AA128: begin    // Read Data (64 bytes)
                  SendCnt <= 10'd383;      // 1-byte cmd + 2-byte addr
                  RecvCnt <= 10'd127;      // 1-bype data 
                  RecvQuadCnt <= 6'd0;     
                  state <= ST_CHIP_SELECT;
               end
               `CMD_WRIT_25AA128: begin   // Write 1 byte data 
                  SendCnt <= 10'd511;     // 1 cmd 2 addr 1 data
                  RecvCnt <= 10'd0;
                  RecvQuadCnt <= 6'd0;     
                  state <= ST_CHIP_SELECT;  
               end

               8'hFF: begin    // Bit I/O for debugging
                  // Format (d) (mmmm) (bbbb)   (m=mask, b=bit)
                  // Enable I/O if either mask (XMOSI or XCCLK) is set
                  io_disabled <= (reg_wdata[6:4] == 3'b0x0) ? 1'b1 : 1'b0;
                  prom_data[31] <= reg_wdata[4] ? reg_wdata[0] : reg_wdata[31];        // XMOSI
                  seqn[0] <= reg_wdata[6] ? reg_wdata[2] : seqn[0];                    // XCCLK
                  prom_cs <= reg_wdata[7] ? reg_wdata[3] : prom_cs;                    // XCSn
               end
            endcase // case (prom_cmd[31:24])
          end // if (prom_reg_wen)
           
          else if (prom_blk_start && !blk_wrt) begin     // start of block write
              SendCnt <= 10'd511;
              RecvCnt <= 10'd0;
              blk_wrt <= 1'b1;
              wr_index <= 7'd0;
              prom_debug <= 16'd0;
              // Select the chip, then stay in IDLE state until data
              // is available to be written to PROM
              io_disabled <= 1'b0;
              prom_cs     <= 1'b0;
              prom_result <= 32'd0;
          end
          else if (blk_wrt && (wr_index != 7'd0)) begin
              // Data is available, so start writing to PROM
              prom_data <= data_block[0];
              rd_index <= 7'd1;   // 0 is cmd
              seqn <= 10'd0;
              state <= ST_WRITE_BLOCK;
          end

        end // case: ST_IDLE

        ST_CHIP_SELECT: begin
           io_disabled <= 1'b0;
           prom_cs     <= 1'b0;
           prom_result <= 32'd0;
           state <= ST_WRITE;
        end
           
        ST_WRITE: begin
            if (seqn[3:0] == 4'b1111) begin  // update data on falling sclk
                prom_data <= prom_data<<1;
            end
            if (seqn == SendCnt) begin
                state <= (RecvCnt == 10'd0) ? ST_CHIP_DESELECT : ST_READ;
                seqn <= 10'd0;
            end
            else seqn <= seqn + 1'b1;        // counter, also creates sclk
        end // case: ST_WRITE

        ST_WRITE_BLOCK: begin
            if (seqn[3:0] == 4'b1111) begin  // update data on falling sclk
                prom_data <= prom_data<<1;
            end
            if (seqn == SendCnt) begin
               seqn <= 10'd0;
               // Because the writer (Firewire block) is much faster than the reader,
               // we assume we are done when the reader catches up to the writer.
               if (rd_index == wr_index) begin
                  // Return number of characters written
                  prom_result <= { 27'd0, rd_index };
                  state <= ST_CHIP_DESELECT;
               end
               else begin
                  prom_data <= data_block[rd_index];
                  rd_index <= rd_index + 1'd1;
               end
            end
            else seqn <= seqn + 1'b1;             // counter, also creates sclk
        end // case: ST_WRITE_BLOCK

        ST_READ: begin
            if (seqn[3:0] == 4'b0111) begin  // latch data on rising sclk
                prom_result <= { prom_result[30:0], prom_miso };
            end
            if (seqn == RecvCnt) begin
               if (RecvQuadCnt != 6'd0) begin   // if reading more than one quad
                   seqn <= 10'd0;
                   data_block[wr_index[3:0]] <= prom_result;
                   prom_result <= { 27'd0, (wr_index + 1'b1) };  // number of bytes stored
                   wr_index[3:0] <= wr_index[3:0] + 1'b1;
               end
               if (wr_index[3:0] == RecvQuadCnt)
                   state <= ST_CHIP_DESELECT;
            end
            else
                seqn <= seqn + 1'b1;
        end
          
        ST_CHIP_DESELECT: begin
           prom_cs <= 1'b1;
           state <= ST_IO_DISABLE;
        end

        ST_IO_DISABLE: begin
           io_disabled <= 1'b1;
           prom_cs <= 1'bz;
           state <= ST_IDLE;
        end

        endcase // case (state)
    end // else: !if(reset == 0)
end


//------------------------------
// chipscope
//------------------------------
wire[35:0] control_prom;

icon_prom icon_p(
    .CONTROL0(control_prom)
);

wire[3:0] spi_debug;
assign spi_debug = { prom_mosi, prom_miso, prom_sclk, prom_cs };

ila_prom ila_p(
    .CONTROL(control_prom),
    .CLK(clk),
    .TRIG0(spi_debug),         // 4-bit
    .TRIG1(reg_raddr[15:0]),   // 16-bit
    .TRIG2(reg_wdata),         // 32-bit
    .TRIG3(prom_result)        // 32-bit
);



endmodule


// 4 x 64 quad = 256 bytes 
// 2^8 = 256 
// 128 kbits = 16 kbytes --> 14-bit addr space 
// 1 page = 64 bytes = 16 quads = 2^4 quads 
