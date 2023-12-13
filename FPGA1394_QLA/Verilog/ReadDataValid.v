/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2023 Johns Hopkins University.
 *
 * This module generates the reg_rvalid flag to indicate that the read data
 * is valid, based on reg_rwait:
 *   (reg_rwait == 0) --> read data available immediately (no wait)
 *                        (e.g., read from register)
 *   (reg_rwait == 1) --> read data available one clock after address change
 *                        (e.g., read from memory)
 *
 * Revision history
 *     12/12/23    Peter Kazanzides    Initial revision
 */

module ReadDataValid
(
   input wire sysclk,

   input wire[15:0] reg_raddr,
   input wire reg_rwait,
   output wire reg_rvalid
);
 
reg[15:0] reg_raddr_latched;

always @(posedge sysclk)
begin
   reg_raddr_latched <= reg_raddr;
end   

wire reg_rvalid_1;
assign reg_rvalid_1 = (reg_raddr == reg_raddr_latched) ? 1'b1 : 1'b0;

assign reg_rvalid = reg_rwait ? reg_rvalid_1 : 1'b1;

endmodule
