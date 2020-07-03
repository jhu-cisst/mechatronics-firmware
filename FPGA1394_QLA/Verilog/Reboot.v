/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2020 ERC CISST, Johns Hopkins University.
 *
 * This module provides the capability to reboot the FPGA (e.g., after programming).
 *
 * Note that the ICAP_SPARTAN6 clock is limited to 20 MHz.
 */

module Reboot(
  input wire clk,
  input wire reboot
  );

reg[15:0] RebootProgram[0:14];
initial begin
   RebootProgram[0]  = 16'hffff;   // dummy word
   RebootProgram[1]  = 16'haa99;   // sync word
   RebootProgram[2]  = 16'h5566;   // sync word
   RebootProgram[3]  = 16'h3261;   // write GENERAL1
   RebootProgram[4]  = 16'h0000;   // start address
   RebootProgram[5]  = 16'h3281;   // write GENERAL2
   RebootProgram[6]  = 16'h0b00;   // op code and address
   RebootProgram[7]  = 16'h32a1;   // write GENERAL3
   RebootProgram[8]  = 16'h0000;   // start address
   RebootProgram[9]  = 16'h32c1;   // write GENERAL4
   RebootProgram[10] = 16'h0b00;   // op code and address
   RebootProgram[11] = 16'h30a1;   // write CMD
   RebootProgram[12] = 16'h000e;   // IPROG
   RebootProgram[13] = 16'h2000;   // NOP
   RebootProgram[14] = 16'hffff;   // dummy word
end

reg[3:0] count;
reg      write;

wire[15:0] data;
assign data = RebootProgram[count];

// Need to bit-reverse data to ICAP_SPARTAN6
wire[15:0] icap_input;
assign icap_input = {data[8],  data[9],  data[10], data[11], data[12], data[13], data[14], data[15],
                     data[0],  data[1],  data[2],  data[3],  data[4],  data[5],  data[6],  data[7]};

ICAP_SPARTAN6 #(
   .DEVICE_ID(32'h04008093),   // 6SLX45 Device ID
   .SIM_CFG_FILE_NAME("NONE")
)
icap_reboot (
  .BUSY      (),           // Busy/Ready output
  .O         (),           // 16-bit data output
  .CE        (~write),     // Active low enable input
  .CLK       (clk),        // Clock input
  .I         (icap_input), // 16-bit data input
  .WRITE     (~write)      // Read(1)/Write(0) control input
);

always @(posedge clk)
begin
   if (reboot) begin
      count <= (count == 4'd14) ? count : count + 4'd1;
      write <= (count == 4'd14) ? 0 : 1;
   end
   else begin
      count <= 4'd0;
      write <= 0;
   end
end

endmodule
