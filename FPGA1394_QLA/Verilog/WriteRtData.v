/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2020-2023 Johns Hopkins University.
 *
 * This module writes the real-time block data to the DAC and power control
 * register. It is shared between the Ethernet and Firewire modules.
 *
 * Revision history
 *
 *     12/5/20     Peter Kazanzides    Initial revision
 */

`include "Constants.v"

module WriteRtData
#(parameter NUM_MOTORS = 4)           // Warning: some code only supports 4 or 8
(
    input wire       clk,             // system clock
    // Following signals are provided by the communication module
    // (Firewire or Ethernet) to store the block data in local memory
    input wire       rt_write_en,     // Write enable
    input wire[3:0]  rt_write_addr,   // Write address (0-NUM_MOTORS)
    input wire[31:0] rt_write_data,   // Write data
    // Following signals are used to write to the DAC and power control
    output reg       bw_write_en,
    output reg       bw_reg_wen,
    output reg       bw_blk_wen,
    output reg       bw_blk_wstart,
    output reg[7:0]  bw_reg_waddr,
    output reg[31:0] bw_reg_wdata
    );

localparam[2:0]
   RT_IDLE = 0,
   RT_WSTART = 1,
   RT_WRITE = 2,
   RT_WRITE_GAP = 3,
   RT_BLK_WEN = 4,
   RT_WQUAD_GAP = 5,
   RT_WQUAD = 6;

reg[2:0] rtState = RT_IDLE;
reg[1:0] rtCnt;

function integer log2;
   input integer value;
   begin
      value = value - 1;
      for (log2 = 0; value > 0; log2 = log2 + 1)
         value = value >> 1;
   end
endfunction
localparam integer DACBIT = log2(NUM_MOTORS) - 1;

reg[DACBIT:0] dac_addr;

// For storing DAC values
reg[31:0] RtDAC[0:(NUM_MOTORS-1)];

wire anyDacValid;
wire anyAmpEnMask;
wire rt_write_end;    // indicates that last rt write is in process

// Warning: following generate code only supports 4, 8, or 10 NUM_MOTORS
generate
if (NUM_MOTORS == 4) begin
    assign anyDacValid  = RtDAC[0][31]|RtDAC[1][31]|RtDAC[2][31]|RtDAC[3][31];
    assign anyAmpEnMask = RtDAC[0][29]|RtDAC[1][29]|RtDAC[2][29]|RtDAC[3][29];
    assign rt_write_end = rt_write_addr[2];
end
else if (NUM_MOTORS == 8) begin
    assign anyDacValid  = RtDAC[0][31]|RtDAC[1][31]|RtDAC[2][31]|RtDAC[3][31]|
                          RtDAC[4][31]|RtDAC[5][31]|RtDAC[6][31]|RtDAC[7][31];
    assign anyAmpEnMask = RtDAC[0][29]|RtDAC[1][29]|RtDAC[2][29]|RtDAC[3][29]|
                          RtDAC[4][29]|RtDAC[5][29]|RtDAC[6][29]|RtDAC[7][29];
    assign rt_write_end = rt_write_addr[3];
end
else if (NUM_MOTORS == 10) begin
   assign anyDacValid = RtDAC[0][31]|RtDAC[1][31]|RtDAC[2][31]|RtDAC[3][31]|
                        RtDAC[4][31]|RtDAC[5][31]|RtDAC[6][31]|RtDAC[7][31]|
                        RtDAC[8][31]|RtDAC[3][31]|RtDAC[9][31];
   assign anyAmpEnMask= RtDAC[0][29]|RtDAC[1][29]|RtDAC[2][29]|RtDAC[3][29]|
                        RtDAC[4][29]|RtDAC[5][29]|RtDAC[6][29]|RtDAC[7][29]|
                        RtDAC[8][29]|RtDAC[3][29]|RtDAC[9][29];
   assign rt_write_end = rt_write_addr == NUM_MOTORS;
end
endgenerate

// For storing power control quadlet. Note that we only save the lowest 20 bits, so
// that we do not accidentally make other changes, such as requesting an FPGA reboot.
reg[19:0] RtCtrl;

always @(posedge clk)
begin

   rtCnt <= (rtState == RT_IDLE)  ? 2'd0 : (rtCnt + 2'd1);

   case (rtState)

   RT_IDLE:
   begin
      bw_write_en <= 0;
      bw_reg_wen <= 0;
      bw_blk_wen <= 0;
      bw_blk_wstart <= 0;
      // Could check if rt_write_en is asserted when we are not in the idle state
      // and flag an error in that case
      if (rt_write_en) begin
         if (rt_write_end) begin
            RtCtrl <= rt_write_data[19:0];
            // Now, start writing to the DAC and/or control register
            if (anyDacValid|anyAmpEnMask) begin
               // Assert bw_blk_wstart for 80 ns before starting local block write
               // (same timing as in Firewire module).
               bw_write_en <= 1;
               bw_blk_wstart <= 1;
               rtState <= RT_WSTART;
            end
            else begin
               // No DAC valid, only write RtCtrl quadlet
               bw_write_en <= 1;
               rtState <= RT_WQUAD;
            end
         end
         else begin
            RtDAC[rt_write_addr[DACBIT:0]] <= rt_write_data;
         end
      end
   end

   RT_WSTART:
   begin
      if (rtCnt == 2'd3) begin
         bw_blk_wstart <= 0;
         bw_reg_waddr <= {4'd0, `OFF_DAC_CTRL};
         rtState <= RT_WRITE;
      end
   end

   RT_WRITE:
   begin
      bw_reg_waddr[7:4] <= bw_reg_waddr[7:4] + 4'd1;
      bw_reg_wdata <= RtDAC[bw_reg_waddr[7:4]];
      bw_reg_wen <= 1'b1;
      rtState <= RT_WRITE_GAP;
   end

   RT_WRITE_GAP:
   begin
      // hold reg_wen low for 60 nsec (3 cycles)
      bw_reg_wen <= 1'b0;
      // clear valid bit and amp enable mask
      RtDAC[bw_reg_waddr[7:4]-4'd1][31] <= 1'b0;
      RtDAC[bw_reg_waddr[7:4]-4'd1][29] <= 1'b0;
      if (rtCnt == 2'd3) begin
         if (bw_reg_waddr[7:4] == NUM_MOTORS)  // end of DAC block
            rtState <= RT_BLK_WEN;
         else
            rtState <= RT_WRITE;
      end
   end

   RT_BLK_WEN:
   begin
      // Wait 60 nsec before asserting blk_wen
      if (rtCnt == 2'd3) begin
         bw_blk_wen <= 1'b1;
         // Write quadlet if non-zero (here, we know that at
         // least one DAC or Amp Enable was valid)
         if (RtCtrl == 20'd0)
            rtState <= RT_IDLE;
         else
            rtState <= RT_WQUAD_GAP;
      end
   end

   RT_WQUAD_GAP:
   begin
      // Wait a little between DAC block write and
      // power control quadlet write
      bw_blk_wen <= 1'b0;
      if (rtCnt == 2'd3)
         rtState <= RT_WQUAD;
   end

   RT_WQUAD:
   begin
      // Status write
      bw_reg_waddr <= 8'd0;
      bw_reg_wdata <= {12'd0, RtCtrl};
      bw_reg_wen <= 1;
      bw_blk_wen <= 1;
      RtCtrl <= 20'd0;   // Clear RtCtrl
      rtState <= RT_IDLE;
   end
        
   default:
   begin
      // Could note this as an error
      rtState <= RT_IDLE;
   end

   endcase // case (rtState)
end

endmodule
