/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2008-2023 ERC CISST, Johns Hopkins University.
 *
 * This module contains a register file dedicated to general board parameters
 * for the DRAC.
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
 *     12/14/22    Peter Kazanzides    Created from code in BoardRegs.v
 */


// device register file offset
`include "Constants.v" 

module BoardRegsDRAC
    #(parameter[3:0] NUM_CHAN = 4'd10,
      parameter[31:0] VERSION = 32'h64524131)       // "dRA1"
(
    // global clock
    input  wire sysclk, 
    
    // board input (PC writes)
    output reg relay_on,            // enable relay for safety loop-through
    input wire pwr_enable,

    // board output (PC reads)
    input  wire relay,              // relay signal
    input  wire mv_good,            // motor voltage good 
    output reg  mv_amp_disable,     // mv good amp_disable (disable for 40 ms after mv_good detected)
    input  wire safety_fb,          // whether voltage present on safety line
    input  wire[3:0] board_id,      // board id (rotary switch)
    input  wire[31:0] temp_sense,   // temperature sensor reading
    input  wire[11:0] reg_status12, // lowest 12-bits of status register (amplifier-related)
    input  wire[31:0] reg_digin,
    input  wire is_ecm,

    // register file interface
    input  wire[15:0] reg_raddr,     // register read address
    input  wire[15:0] reg_waddr,     // register write address
    output reg[31:0] reg_rdata,      // register read data
    output wire reg_rwait,           // register read wait state
    input  wire[31:0] reg_wdata,     // register write data
    input  wire reg_wen,             // write enable from FireWire module

    output wire[31:0] reg_status,  // Status register (for reading)
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
                // Byte 2: wdog timeout, is ecm, unused (0), unused (0)
                wdog_timeout, is_ecm, 1'b0, 1'b0,
                // mv_good, power enable, safety relay state, safety relay control
                mv_good, pwr_enable, ~relay, relay_on,
                // unused (0000)
                1'b0, 1'b0, 1'b0, 1'b0,
                // lowest 12-bits are for amplifier feedback
                reg_status12 };


//------------------------------------------------------------------------------
// hardware description
//

wire write_main;
assign write_main = ((reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4]==4'd0) && reg_wen) ? 1'b1 : 1'b0;

// clocked process simulating a register file
always @(posedge(sysclk))
  begin
    // set register values for writes
    if (write_main) begin
        case (reg_waddr[3:0])
        `REG_STATUS: begin
            // mask reg_wdata[17] with [16] for safety relay control
            relay_on <= reg_wdata[17] ? reg_wdata[16] : relay_on;
        end
        endcase
    end
end

// return register data for reads
//    REG_PROMSTAT, REG_PROMRES, REG_IPADDR and REG_ETHRES handled by FPGA module
always @(*) begin
    case (reg_raddr[3:0])
        `REG_STATUS: reg_rdata = reg_status;
        `REG_VERSION: reg_rdata = VERSION;
        `REG_TEMPSNS: reg_rdata = temp_sense;
        `REG_DIGIN: reg_rdata = reg_digin;
        default:  reg_rdata = 32'd0;
    endcase
end

// Register reads have 0 wait
assign reg_rwait = 1'b0;

// The clock resolution is 5.208333 us (2^8 / 49.152 MHz), since
// we use a 24-bit counter and compare the upper 16 bits to 7680
// (previous implementations used ClkDiv to create wdog_clk).

// mv good timer
reg[23:0] mv_good_counter;  // mv_good counter

always @(posedge(sysclk))
begin
    if ((mv_good == 1'b1) && (mv_good_counter[23:8] < 16'd7680)) begin
        mv_good_counter <= mv_good_counter + 24'd1;
        mv_amp_disable <= 1'b1;
    end 
    else if (mv_good == 1'b1) begin
        mv_amp_disable <= 1'b0;
    end
    else begin
        mv_amp_disable <= 1'b1;
        mv_good_counter <= 24'd0;
    end
end

endmodule
