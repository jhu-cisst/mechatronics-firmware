/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2023 Johns Hopkins University.
 *
 * This module performs address translation for read address, which is necessary
 * to support the real-time block read.
 * It replaces code originally in SampleData.v and SampleDataAddressTranslation.v.
 *
 * Revision history
 *     12/02/23    Peter Kazanzides    Initial revision
 */

`include "Constants.v"

module ReadAddressTranslation
    #(parameter NUM_MOTORS = 4,
      parameter NUM_ENCODERS = 4)
(
    input  wire[15:0] reg_raddr_in,   // reg_raddr from host (Firewire, Ethernet, or EMIO)
    output wire[15:0] reg_raddr_out,  // reg_raddr to FPGA registers
    input  wire       blk_rt_rd       // 1 -> real-time block read
);

localparam MAX_RT_READ_INDEX = 3 + 2*NUM_MOTORS + 5*NUM_ENCODERS;

// Address map for RT block read
wire[7:0] addr_map[0:MAX_RT_READ_INDEX];

assign addr_map[0] = 8'd0;   // timestamp (special case)
assign addr_map[1] = {4'd0, `REG_STATUS};
assign addr_map[2] = {4'd0, `REG_DIGIN};
assign addr_map[3] = {4'd0, `REG_TEMPSNS};

generate
    genvar i;
    for (i = 1; i <= NUM_MOTORS; i = i+1) begin : mot
        assign addr_map[3+i]                           = { i, `OFF_ADC_DATA };
        assign addr_map[3+NUM_MOTORS+5*NUM_ENCODERS+i] = { i, `OFF_MOTOR_STATUS };
    end
    for (i = 1; i <= NUM_ENCODERS; i = i+1) begin : enc
        assign addr_map[3+NUM_MOTORS+i]                = { i, `OFF_ENC_DATA };
        assign addr_map[3+NUM_MOTORS+NUM_ENCODERS+i]   = { i, `OFF_PER_DATA };
        assign addr_map[3+NUM_MOTORS+2*NUM_ENCODERS+i] = { i, `OFF_QTR1_DATA };
        assign addr_map[3+NUM_MOTORS+3*NUM_ENCODERS+i] = { i, `OFF_QTR5_DATA };
        assign addr_map[3+NUM_MOTORS+4*NUM_ENCODERS+i] = { i, `OFF_RUN_DATA };
    end
endgenerate   

// reg_raddr_in[5:0] handles up to 64 quadlets. A more elegant solution is to
// define and use a clogb2 function.
assign reg_raddr_out = blk_rt_rd ? {8'd0, addr_map[reg_raddr_in[5:0]]} : reg_raddr_in;

endmodule
