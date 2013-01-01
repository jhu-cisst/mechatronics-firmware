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
    output reg prom_cmd_clear,    //  request to clear command input
    output reg[31:0] prom_result, // result (to Firewire)
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
          PROM_WAIT_CLEAR = 5;

reg       io_disabled;
reg[2:0]  state;
reg[6:0]  seqn;            // 7-bit counter for sequencing operation
reg[5:0]  SendBits;
reg[5:0]  RecvBits;
reg[31:0] prom_data;     // data to write to PROM
   
   
assign prom_mosi = io_disabled ? 1'bz : prom_data[31];
assign prom_sclk = io_disabled ? 1'bz : seqn[0];

always @(posedge(clk) or negedge(reset))
begin
    if (reset == 0) begin
        io_disabled <= 1'b1;
        prom_cs     <= 1'bz;
        prom_result <= 32'd0;
        prom_cmd_clear <= 1'b0;
        state <= PROM_IDLE;
    end

    else begin
        case (state)

        // idle state
        PROM_IDLE: begin
            seqn <= 6'd0;
            prom_data <= prom_cmd;
            case (prom_cmd[31:24])
               8'h00: begin    // Do nothing
                  end
               8'h03: begin    // Read data (for now, just 4 bytes)
                  SendBits <= 6'd32;
                  RecvBits <= 6'd32;
                  state <= PROM_CHIP_SELECT;
               end
               8'h05: begin    // Read Status
                  SendBits <= 6'd8;
                  RecvBits <= 6'd8;
                  state <= PROM_CHIP_SELECT;
               end
               8'h9f: begin    // Read ID
                  SendBits <= 6'd8;
                  RecvBits <= 6'd24;
                  state <= PROM_CHIP_SELECT;
               end
               8'hD8: begin    // Sector Erase
                  SendBits <= 6'd32;
                  RecvBits <= 6'd0;
                  state <= PROM_CHIP_SELECT;
               end
               default: begin
                  prom_cmd_clear <= 1'b1;
                  state <= PROM_WAIT_CLEAR;
               end
            endcase // case (prom_cmd[31:24])
        end // case: PROM_IDLE

        PROM_CHIP_SELECT: begin
           io_disabled <= 1'b0;
           prom_cs     <= 1'b0;
           prom_result <= 32'd0;
           state <= PROM_WRITE;
        end
           
        PROM_WRITE: begin
            seqn <= seqn + 1'b1;             // counter, also creates sclk
            if (prom_sclk == 1'b1) begin     // update data on falling sclk
                prom_data <= prom_data<<1;
            end
            if (seqn[6:1] == SendBits) begin
               state <= (RecvBits == 6'd0) ? PROM_CHIP_DESELECT : PROM_READ;
            end
        end

        PROM_READ: begin
            seqn <= seqn + 1'b1;
            if (prom_sclk == 1'b0) begin
               prom_result <= { prom_result[30:0], prom_miso };
            end
            if (seqn[6:1] == RecvBits) begin
               state <= PROM_CHIP_DESELECT;
            end
        end
          
        PROM_CHIP_DESELECT: begin
           prom_cs <= 1'b1;   // deselect chip
           prom_cmd_clear <= 1'b1;
           state <= PROM_WAIT_CLEAR;
        end

        PROM_WAIT_CLEAR: begin
            if (prom_cmd == 32'd0) begin
                prom_cmd_clear <= 1'b0;
                io_disabled <= 1'b1;
                prom_cs <= 1'bz;
                state <= PROM_IDLE;
            end
        end
        
        endcase // case (state)
    end // else: !if(reset == 0)
end

endmodule
