/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2012-2013 ERC CISST, Johns Hopkins University.
 *
 * Module: M25P16
 *
 * Purpose: Program the M25P16 PROM
 * 
 * Revision history
 *     12/31/12    Peter Kazanzides    Initial revision
 *     10/24/13    Zihan Chen          Revised for 25AA128 SPI PROM
 */

module QLA25AA128(
    input  clk,                   // input clock
    input  reset,                 // global reset signal
    input[31:0]  prom_cmd,        // command input (from Firewire)
    output[31:0] prom_status,     // PROM interface status
    output reg[31:0] prom_result, // result (to Firewire)
    output reg[31:0] prom_rdata,  // result (to Firewire)
    input[5:0] prom_blk_addr,     // address of data for block write
    input  prom_blk_enable,       // if block read/write is enabled
    input  prom_reg_wen,          // write enable for quadlet write
    input  prom_blk_start,        // start of block write
    input  prom_blk_wen,          // write enable for each quadlet in block write
    input  prom_blk_end,          // end of block write
    output prom_mosi,             // Serial out to 25AA128
    input  prom_miso,             // Serial in from 25AA128
    output prom_sclk,             // CLK to 25AA128
    output reg prom_cs            // /CS to 25AA128
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
reg[6:0]  seqn;            // 7-bit counter for sequencing operation
reg[6:0]  SendCnt;         // 2*NumBits-1
reg[6:0]  RecvCnt;         // 2*NumBits-1 (0 if no bits to receive)
reg[5:0]  RecvQuadCnt;     // Number of quadlets to read, minus 1
reg[31:0] prom_data;       // data to write to PROM
reg       blk_wrt;         // true if a block write is in progress (and hasn't been aborted due to an error)
reg[15:0] prom_debug;

reg[31:0] data_block[0:65];  // Up to 65 quadlets of data, received via block write
reg [6:0] wr_index;          // Current write index (7-bit), set from prom_blk_addr (6-bit),
                             // with wrap-around allowed
reg [6:0] rd_index;          // Current read index (7-bit), incremented in this module
   
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
assign prom_sclk = io_disabled ? 1'bz : seqn[0];

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

        if (prom_blk_wen && blk_wrt) begin       // receive one quadlet of the block write
            if (prom_blk_addr == wr_index[5:0]) begin
                data_block[wr_index] <= prom_cmd;
                // Update write index
                wr_index <= wr_index + 1'b1;
            end
            else  begin // error, unexpected block write address
                prom_debug <= { 2'b0, prom_blk_addr, 1'b0, wr_index };
            end
        end

        else if (prom_blk_end) begin 
            // finish receiving data from block write; will still be writing to PROM
            blk_wrt <= 1'b0;
        end

        else if (prom_blk_enable && !prom_reg_wen && !prom_blk_start) begin   // handle block reads
            prom_rdata <= data_block[prom_blk_addr];
        end

        case (state)

        ST_IDLE: begin
           
          if (prom_reg_wen) begin
            seqn <= 7'd0;
            prom_data <= prom_cmd;
            blk_wrt <= 1'b0;
            wr_index <= 7'd0;
            case (prom_cmd[31:24])
               8'h00: begin    // Do nothing
               end
               8'h06: begin    // Write Enable
                  SendCnt <= 7'd15;
                  RecvCnt <= 7'd0;
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               8'h04: begin    // Write Disable
                  SendCnt <= 7'd15;
                  RecvCnt <= 7'd0;
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               8'h9f: begin    // Read ID (only first 3 bytes)
                  SendCnt <= 7'd15;
                  RecvCnt <= 7'd47;
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               8'h05: begin    // Read Status Register
                  SendCnt <= 7'd15;
                  RecvCnt <= 7'd15;
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               8'h01: begin    // Write Status Register
                  SendCnt <= 7'd31;
                  RecvCnt <= 7'd0;
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               8'h03: begin    // Read Data (256 bytes)
                  SendCnt <= 7'd63;
                  RecvCnt <= 7'd63;
                  RecvQuadCnt <= 6'h3f;
                  state <= ST_CHIP_SELECT;
               end
               8'h0B: begin    // Fast Read Data (256 bytes)
                  SendCnt <= 7'd97;   // needs a dummy byte
                  RecvCnt <= 7'd63;
                  RecvQuadCnt <= 6'h3f;
                  state <= ST_CHIP_SELECT;
               end
               8'hD8: begin    // Sector Erase
                  SendCnt <= 7'd63;
                  RecvCnt <= 7'd0;
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               8'hC7: begin    // Bulk Erase
                  SendCnt <= 7'd15;
                  RecvCnt <= 7'd0;
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               8'hB9: begin    // Deep Power Down
                  SendCnt <= 7'd15;
                  RecvCnt <= 7'd0;
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               8'hAB: begin    // Release from deep power down
                  SendCnt <= 7'd63;     // 3 dummy bytes
                  RecvCnt <= 7'd15;     // "old style" ID = 0x14
                  RecvQuadCnt <= 6'd0;
                  state <= ST_CHIP_SELECT;
               end
               8'hFF: begin    // Bit I/O for debugging
                  // Format (d) (mmmm) (bbbb)   (m=mask, b=bit)
                  // Enable I/O if either mask (XMOSI or XCCLK) is set
                  io_disabled <= (prom_cmd[6:4] == 3'b0x0) ? 1'b1 : 1'b0;
                  prom_data[31] <= prom_cmd[4] ? prom_cmd[0] : prom_data[31];        // XMOSI
                  seqn[0] <= prom_cmd[6] ? prom_cmd[2] : seqn[0];                    // XCCLK
                  prom_cs <= prom_cmd[7] ? prom_cmd[3] : prom_cs;                    // XCSn
               end
            endcase // case (prom_cmd[31:24])
          end // if (prom_reg_wen)
           
          else if (prom_blk_start && !blk_wrt) begin     // start of block write
              SendCnt <= 7'd63;
              RecvCnt <= 7'd0;
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
              rd_index <= 7'd1;
              seqn <= 7'd0;
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
            if (prom_sclk == 1'b1) begin     // update data on falling sclk
                prom_data <= prom_data<<1;
            end
            if (seqn == SendCnt) begin
               state <= (RecvCnt == 7'd0) ? ST_CHIP_DESELECT : ST_READ;
               seqn <= 7'd0;
            end
            else seqn <= seqn + 1'b1;        // counter, also creates sclk
        end // case: ST_WRITE

        ST_WRITE_BLOCK: begin
            if (prom_sclk == 1'b1) begin     // update data on falling sclk
                prom_data <= prom_data<<1;
            end
            if (seqn == SendCnt) begin
               seqn <= 7'd0;
               // Because the writer (Firewire block) is much faster than the reader,
               // we assume we are done when the reader catches up to the writer.
               if (rd_index == wr_index) begin
                  // Return number of characters written
                  prom_result <= { 25'd0, rd_index };
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
            if (prom_sclk == 1'b0) begin
               prom_result <= { prom_result[30:0], prom_miso };
            end
            if (seqn == RecvCnt) begin
               if (RecvQuadCnt != 6'd0) begin   // if reading more than one quad
                   seqn <= 7'd0;
                   data_block[wr_index[5:0]] <= prom_result;
                   prom_result <= { 25'd0, (wr_index + 1'b1) };  // number of bytes stored
                   wr_index[5:0] <= wr_index[5:0] + 1'b1;
               end
               if (wr_index[5:0] == RecvQuadCnt)
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

endmodule
