/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2020-2022 Johns Hopkins University.
 *
 * This module samples the feedback data for the real-time block read packet.
 *
 * Revision history
 *     01/26/20    Peter Kazanzides    Initial revision
 *     01/27/21    Peter Kazanzides    Removed write to hub
 */

`include "Constants.v"

module SampleData(
    input wire        clk,         // system clock
    input wire        doSample,    // signal to trigger sampling
    output wire       isBusy,      // 1 -> busy sampling
    input wire[31:0]  reg_status,  // Status register
    input wire[31:0]  reg_digio,   // Digital I/O feedback
    input wire[31:0]  reg_temp,    // Temperature feedback
    output reg[3:0]   chan,        // Channel index (1-4)
    input wire[31:0]  adc_in,      // ADC feedback (motor current, pot)
    input wire[31:0]  enc_pos,     // Encoder quadrature position
    input wire[31:0]  enc_period,  // Encoder velocity (period)
    input wire[31:0]  enc_qtr1,    // Encoder quarter period (last cycle)
    input wire[31:0]  enc_qtr5,    // Encoder quarter period (5 cycles ago)
    input wire[31:0]  enc_run,     // Encoder running counter
    input wire[31:0]  motor_status, // Motor status feedback
    input wire[5:0]   blk_addr,    // Address for accessing RT_Feedback
    output wire[31:0] blk_data,    // Currently selected block data
    output reg[31:0]  timestamp,   // timestamp counter register
    input wire[15:0]  bc_sequence, // broadcast sequence number
    input wire[15:0]  bc_board_mask // broadcast board mask
    );

// Number of quadlets in block response:
//   1 (timestamp) + 3 (global regs) + num_channels*num_offsets
//     num_channels: 4 (QLA)
//     num_offsets: 4 (Rev 1-6), 6 (Rev 7), 7 (Rev 8+)
//   Thus, num_quadlets = 20 (Rev 1-6), 28 (Rev 7), or 32 (Rev 8+)
// We allocate the full address of 32 quadlets

reg[31:0] RT_Feedback[0:31];

localparam[1:0]
   SD_IDLE = 2'd0,
   SD_SAMPLING = 2'd1;

reg[1:0] state;

assign blk_data = RT_Feedback[blk_addr[4:0]];
assign isBusy = (state != SD_IDLE);

// -------------------------------------------------------
// Sample data for block read
// -------------------------------------------------------

// Having a separate always block to sample the data has several advantages:
// 1) It minimizes the amount of time that the Ethernet/Firewire module takes control over the
//    internal bus (i.e., because it does not have to read the data from the registers).
// 2) The data are better synchronized.
// 3) It simplifies the Ethernet/Firewire state machine.

always @(posedge clk)
begin
   timestamp <= (isBusy && (chan == 4'd1)) ? 32'd0 : timestamp + 1'b1;
   case (state)

      SD_IDLE:
      begin
         if (doSample) begin
            chan <= 4'd1;
            state <= SD_SAMPLING;
         end
      end

      SD_SAMPLING:
      begin
         chan <= chan + 4'd1;
         if (chan == 4'd1) begin
            RT_Feedback[0] <= timestamp;
            RT_Feedback[1] <= reg_status;
            RT_Feedback[2] <= reg_digio;
            RT_Feedback[3] <= reg_temp;
         end
         if (chan == 4'd5) begin
            state <= SD_IDLE;
         end
         else begin
            // For chan = 1,2,3,4
            RT_Feedback[3+chan] <= adc_in;
            RT_Feedback[7+chan] <= enc_pos;
            RT_Feedback[11+chan] <= enc_period;
            RT_Feedback[15+chan] <= enc_qtr1;
            RT_Feedback[19+chan] <= enc_qtr5;
            RT_Feedback[23+chan] <= enc_run;
            RT_Feedback[27+chan] <= motor_status;
         end
      end

      default:
         state <= SD_IDLE;

   endcase
end    

endmodule
