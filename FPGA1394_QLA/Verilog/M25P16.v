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
 */

module M25P16(
    input  clk,                   // input clock
    input  reset,                 // global reset signal
    input[31:0]  prom_cmd,        // command input (from Firewire)
    output[31:0] prom_status,     // PROM interface status
    output reg[31:0] prom_result, // result (to Firewire)
    input[5:0] prom_blk_addr,     // address of data for block write
    input  prom_reg_wen,          // write enable for quadlet write
    input  prom_blk_start,        // start of block write
    input  prom_blk_wen,          // write enable for each quadlet in block write
    input  prom_blk_end,          // end of block write
    output prom_mosi,             // Serial out to M25P16
    input  prom_miso,             // Serial in from M25P16
    output prom_sclk,             // CLK to M25P16
    output reg prom_cs            // /CS to M25P16
);

// State machine
parameter PROM_IDLE = 0,
          PROM_CHIP_SELECT = 1,
          PROM_WRITE = 2,
          PROM_READ = 3,
          PROM_CHIP_DESELECT = 4,
          PROM_IO_DISABLE = 5;

reg       io_disabled;
reg[2:0]  state;
reg[6:0]  seqn;            // 7-bit counter for sequencing operation
reg[6:0]  SendCnt;         // 2*NumBits-1
reg[6:0]  RecvCnt;         // 2*NumBits-1 (0 if no bits to receive)
reg[31:0] prom_data;       // data to write to PROM
reg[8:0]  next_blk_addr;   // next address of data being programmed (block write)
reg       blk_wrt;         // true if a block write is in progress (and hasn't been aborted due to an error)

assign prom_status[31:10] = 23'd0;
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
        blk_wrt     <= 1'b0;
        state <= PROM_IDLE;
    end

    else begin
        case (state)

        PROM_IDLE: begin
           
          if (prom_reg_wen) begin
            seqn <= 7'd0;
            prom_data <= prom_cmd;
            blk_wrt <= 1'b0;
            case (prom_cmd[31:24])
               8'h00: begin    // Do nothing
               end
               8'h06: begin    // Write Enable
                  SendCnt <= 7'd15;
                  RecvCnt <= 7'd0;
                  state <= PROM_CHIP_SELECT;
               end
               8'h04: begin    // Write Disable
                  SendCnt <= 7'd15;
                  RecvCnt <= 7'd0;
                  state <= PROM_CHIP_SELECT;
               end
               8'h9f: begin    // Read ID (only first 3 bytes)
                  SendCnt <= 7'd15;
                  RecvCnt <= 7'd47;
                  state <= PROM_CHIP_SELECT;
               end
               8'h05: begin    // Read Status Register
                  SendCnt <= 7'd15;
                  RecvCnt <= 7'd15;
                  state <= PROM_CHIP_SELECT;
               end
               8'h01: begin    // Write Status Register
                  SendCnt <= 7'd31;
                  RecvCnt <= 7'd0;
                  state <= PROM_CHIP_SELECT;
               end
               8'h03: begin    // Read Data (for now, just 4 bytes)
                  SendCnt <= 7'd63;
                  RecvCnt <= 7'd63;
                  state <= PROM_CHIP_SELECT;
               end
               8'h0B: begin    // Fast Read Data (for now, just 4 bytes)
                  SendCnt <= 7'd97;   // needs a dummy byte
                  RecvCnt <= 7'd63;
                  state <= PROM_CHIP_SELECT;
               end
               8'hD8: begin    // Sector Erase
                  SendCnt <= 7'd63;
                  RecvCnt <= 7'd0;
                  state <= PROM_CHIP_SELECT;
               end
               8'hC7: begin    // Bulk Erase
                  SendCnt <= 7'd15;
                  RecvCnt <= 7'd0;
                  state <= PROM_CHIP_SELECT;
               end
               8'hB9: begin    // Deep Power Down
                  SendCnt <= 7'd15;
                  RecvCnt <= 7'd0;
                  state <= PROM_CHIP_SELECT;
               end
               8'hAB: begin    // Release from deep power down
                  SendCnt <= 7'd63;     // 3 dummy bytes
                  RecvCnt <= 7'd15;     // "old style" ID = 0x14
                  state <= PROM_CHIP_SELECT;
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
              next_blk_addr <= 9'd0;
              state <= PROM_CHIP_SELECT;
          end

          else if (prom_blk_wen && blk_wrt) begin       // write one quadlet of the block
              if (prom_blk_addr == next_blk_addr[5:0]) begin
                  // SendCnt and RecvCnt already set at start
                  prom_data <= prom_cmd;
                  seqn <= 7'd0;
                  state <= PROM_WRITE;
              end
              else begin
                  // Error -- we must have missed one; abort the write
                  blk_wrt <= 1'b0;
                  prom_result <= { 8'b1, 7'b0, next_blk_addr, 2'b0, prom_blk_addr };
                  state <= PROM_CHIP_DESELECT;
              end
          end

          else if (prom_blk_end) begin       // finish the block write
              if (blk_wrt) begin
                  blk_wrt <= 1'b0;
                  prom_result <= { 23'd0, next_blk_addr };
                  state <= PROM_CHIP_DESELECT;
              end
              else begin
                  state <= PROM_CHIP_DESELECT;
              end
          end
        end // case: PROM_IDLE

        PROM_CHIP_SELECT: begin
           io_disabled <= 1'b0;
           prom_cs     <= 1'b0;
           prom_result <= 32'd0;
           state <= blk_wrt ? PROM_IDLE : PROM_WRITE;
        end
           
        PROM_WRITE: begin
            if (prom_sclk == 1'b1) begin     // update data on falling sclk
                prom_data <= prom_data<<1;
            end
            if (seqn == SendCnt) begin
               if (blk_wrt) begin      // if block write
                  state <= PROM_IDLE;
                  next_blk_addr <= next_blk_addr + 1'd1;
               end
               else begin                            // all other commands
                  state <= (RecvCnt == 7'd0) ? PROM_CHIP_DESELECT : PROM_READ;
               end
               seqn <= 7'd0;
            end
            else seqn <= seqn + 1'b1;             // counter, also creates sclk
        end // case: PROM_WRITE

        PROM_READ: begin
            seqn <= seqn + 1'b1;
            if (prom_sclk == 1'b0) begin
               prom_result <= { prom_result[30:0], prom_miso };
            end
            if (seqn == RecvCnt) begin
               state <= PROM_CHIP_DESELECT;
            end
        end
          
        PROM_CHIP_DESELECT: begin
           prom_cs <= (prom_cs == 1'bz) ? 1'bz : 1'b1;   // deselect chip if not tri-state
           state <= PROM_IO_DISABLE;
        end

        PROM_IO_DISABLE: begin
           io_disabled <= 1'b1;
           prom_cs <= 1'bz;
           state <= PROM_IDLE;
        end

        endcase // case (state)
    end // else: !if(reset == 0)
end

endmodule
