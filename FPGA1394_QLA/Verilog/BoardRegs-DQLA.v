/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2008-2022 ERC CISST, Johns Hopkins University.
 *
 * This module contains a register file dedicated to general board parameters
 * for the DQLA (dual QLA)
 *
 * Revision history
 *     07/17/08    Paul Thienphrapa    Initial revision - SnakeFPGA-rev2
 *     12/21/11    Paul Thienphrapa    Adapted for FPGA1394_QLA
 *     02/22/12    Paul Thienphrapa    Minor fixes for power enable and reset
 *     05/08/13    Zihan Chen          Fix watchdog 
 *     05/19/13    Zihan Chen          Add mv_good 40 ms sleep
 *     09/23/15    Peter Kazanzides    Moved DOUT code to CtrlDout.v
 *     10/15/19    Jintan Zhang        Implemented watchdog period led feedback 
 *     07/03/20    Peter Kazanzides    Changing reset to reboot
 *     06/27/22    Peter Kazanzides    Added isQuadDac
 *     12/16/22    Peter Kazanzides    Created from code in BoardRegs-QLA.v
 */


// device register file offset
`include "Constants.v" 

module BoardRegsDQLA
    #(parameter[3:0] NUM_CHAN = 4'd8,
      parameter[31:0] VERSION = 32'h44514C41)       // "DQLA"
(
    // global clock
    input  wire sysclk, 
    
    // board input (PC writes)
    input  wire[31:0] dout,             // digital outputs
    input  wire[2:1] dout_cfg_valid,    // digital output configuration valid
    input  wire[2:1] dout_cfg_bidir,    // whether digital outputs are bidirectional (also need to be inverted)
    output reg dout_cfg_reset,          // reset dout_cfg_valid
    output reg[2:1] pwr_enable,         // enable motor power
    output reg relay_on,                // enable relay for safety loop-through
    input  wire[2:1] isQuadDac,         // type of DAC: 0 = 4xLTC2601, 1 = 1xLTC2604
    output reg dac_test_reset,          // repeat DAC test
    output reg ioexp_cfg_reset,         // redetect I/O expander (MAX7317)
    input  wire[2:1] ioexp_present,     // 1 -> I/O expander (MAX7317) detected
    input  wire[2:1] dqla_exp_ok,       // 1 -> DQLA I/O expander (MAX7301) detected

    // board output (PC reads)
    input  wire[7:0] neg_limit,         // digi input negative limit
    input  wire[7:0] pos_limit,         // digi input positive limit
    input  wire[7:0] home,              // digi input home position
    
    input  wire[2:1] mv_good,           // motor voltage good 
    input  wire[2:1] safety_fb,         // whether voltage present on safety line
    input  wire[2:1] mv_fb,             // comparator feedback used to measure motor supply voltage
    input  wire[3:0] board_id,          // board id (rotary switch)
    input  wire[31:0] temp_sense,       // temperature sensor reading
    
    // register file interface
    input  wire[15:0] reg_raddr,        // register read address
    input  wire[15:0] reg_waddr,        // register write address
    output reg[31:0] reg_rdata,         // register read data
    input  wire[31:0] reg_wdata,        // register write data
    input  wire reg_wen,                // write enable from FireWire module
    
    // Dallas chip status
    input  wire[31:0] ds_status,

    // Signal used to clear error flags
    output wire pwr_enable_cmd,
    // Signal used to delay amplifier enable after board power detected
    output reg[2:1] mv_amp_disable,

    output wire[31:0] reg_status,  // Status register (for reading)
    output wire[31:0] reg_digin,   // Digital I/O register (for reading)
    input wire wdog_timeout        // Watchdog timeout status flag
);

    // -------------------------------------------------------------------------
    // define wires and registers
    //

    // PROGRAMMER NOTE: The higher-level software requires board_id to be in bits [27:24]
    //                  and wdog_timeout to be bit 23. By convention, bits [31:28] specify
    //                  the number of channels. Other bits are board-specific.
    assign reg_status = {
                // Byte 3: num channels, board id
                NUM_CHAN, board_id,
                // Byte 2: wdog timeout, isQuadDac[2:1], 0, mv_good, pwr_enable, 0, safety relay control
                wdog_timeout, isQuadDac, 1'b0, (mv_good[1]&mv_good[2]), (pwr_enable[1]&pwr_enable[2]), 1'b0, relay_on,
                // Byte 1: mv_good[2:1], dqla_exp_ok[2:1], dout_cfg_valid[2:1], dout_cfg_bidir[2:1],
                mv_good, dqla_exp_ok, dout_cfg_valid, dout_cfg_bidir,
                // Byte 0: safety_fb[2:1], mv_fb[2:1], dout[31], 0, ioexp_present[2:1]
                // dout[31] indicates that waveform table is driving at least one DOUT
                safety_fb, mv_fb, dout[31], 1'b0, ioexp_present };

    assign reg_digin = {dout[7:0], neg_limit, pos_limit, home};

//------------------------------------------------------------------------------
// hardware description
//

wire write_main;
assign write_main = ((reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4]==4'd0) && reg_wen) ? 1'b1 : 1'b0;
wire write_status;
assign write_status = (write_main && (reg_waddr[3:0] == `REG_STATUS)) ? 1'b1 : 1'b0;

// pwr_enable_cmd indicates that the host is attempting to enable board power.
// This is used to clear error flags, such as wdog_timeout and safety_amp_disable.
assign pwr_enable_cmd = write_status ? (reg_wdata[19]&reg_wdata[18]) : 1'd0;

// clocked process simulating a register file
always @(posedge(sysclk))
  begin
    // set register values for writes
    if (write_main) begin
        case (reg_waddr[3:0])
        `REG_STATUS: begin
            // *** Following are same as QLA ***
            // mask reg_wdata[17] with [16] for safety relay control
            relay_on <= reg_wdata[17] ? reg_wdata[16] : relay_on;
            // mask reg_wdata[19] with [18] for pwr_enable
            pwr_enable <= reg_wdata[19] ? {reg_wdata[18], reg_wdata[18]} : pwr_enable;
            // mask reg_wdata[21] with [20] for reboot (was reset prior to Rev 7)
            // (this is now in BoardRegs.v)
            // Previously, masked reg_wdata[23] with [22] for eth1394 mode
            // use reg_wdata[22] to reset isQuadDac
            dac_test_reset <= reg_wdata[22];
            // use reg_wdata[23] to redetect I/O expander (MAX7317)
            ioexp_cfg_reset <= reg_wdata[23];
            // use reg_wdata[24] to reset dout_cfg_valid
            dout_cfg_reset <= reg_wdata[24];
        end
        endcase
    end

    // return register data for reads
    //    REG_PROMSTAT, REG_PROMRES, REG_IPADDR and REG_ETHRES handled by FPGA module
    else begin
        case (reg_raddr[3:0])
        `REG_STATUS: reg_rdata <= reg_status;
        `REG_VERSION: reg_rdata <= VERSION;
        `REG_TEMPSNS: reg_rdata <= temp_sense;
        `REG_DIGIOUT: reg_rdata <= dout;
        `REG_DSSTAT: reg_rdata <= ds_status;
        `REG_DIGIN: reg_rdata <= reg_digin;

        default:  reg_rdata <= 32'd0;
        endcase

        // Turn off dout_cfg_reset in case it was previously set
        dout_cfg_reset <= 1'b0;
        // Turn off ioexp_cfg_reset in case it was previously set
        ioexp_cfg_reset <= 1'b0;
        // Turn off dac_test_reset in case it was previously set
        dac_test_reset <= 1'b0;
    end
end

// The clock resolution is 5.208333 us (2^8 / 49.152 MHz), since
// we use a 24-bit counter and compare the upper 16 bits to 7680
// (previous implementations used ClkDiv to create wdog_clk).

genvar i;
generate
for (i = 1; i <= 2; i = i+1) begin : mv_loop
    reg[23:0] mv_good_counter;  // mv_good counter
    always @(posedge(sysclk))
    begin
        if ((mv_good[i] == 1'b1) && (mv_good_counter[23:8] < 16'd7680)) begin
            mv_good_counter <= mv_good_counter + 24'd1;
            mv_amp_disable[i] <= 1'b1;
        end 
        else if (mv_good == 1'b1) begin
            mv_amp_disable[i] <= 1'b0;
        end
        else begin
            mv_amp_disable[i] <= 1'b1;
            mv_good_counter <= 24'd0;
        end
    end
end
endgenerate

endmodule
