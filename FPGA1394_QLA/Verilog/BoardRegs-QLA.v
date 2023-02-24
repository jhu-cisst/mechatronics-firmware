/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2008-2023 ERC CISST, Johns Hopkins University.
 *
 * This module contains a register file dedicated to general board parameters
 * for the QLA.
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

module BoardRegsQLA
    #(parameter[3:0] NUM_CHAN = 4'd4,
      parameter[31:0] VERSION = 32'h514C4131)       // "QLA1" = 0x514C4131
(
    // global clock
    input  wire sysclk, 
    
    // board input (PC writes)
    input  wire[31:0] dout,         // digital outputs
    input  wire dout_cfg_valid,     // digital output configuration valid
    input  wire dout_cfg_bidir,     // whether digital outputs are bidirectional (also need to be inverted)
    output reg  dout_cfg_reset,     // reset dout_cfg_valid
    output reg pwr_enable,          // enable motor power
    output reg relay_on,            // enable relay for safety loop-through
    input  wire isQuadDac,          // type of DAC: 0 = 4xLTC2601, 1 = 1xLTC2604
    output reg dac_test_reset,      // repeat DAC test
    output reg ioexp_cfg_reset,     // redetect I/O expander (MAX7317)
    input  wire ioexp_present,      // 1 -> I/O expander (MAX7317) detected

    // board output (PC reads)
    input  wire[4:1] enc_a,         // encoder a  
    input  wire[4:1] enc_b,         // encoder b 
    input  wire[4:1] enc_i,         // encoder index 
    input  wire[4:1] neg_limit,     // digi input negative limit
    input  wire[4:1] pos_limit,     // digi input positive limit
    input  wire[4:1] home,          // digi input home position
    
    input  wire relay,              // relay signal
    input  wire mv_faultn,          // motor power fault (active low) from LT4356, over-voltage or over-current
    input  wire mv_good,            // motor voltage good 
    output reg  mv_amp_disable,     // mv good amp_disable (disable for 40 ms after mv_good detected)
    input  wire v_fault,            // encoder supply voltage fault
    input  wire safety_fb,          // whether voltage present on safety line
    input  wire mv_fb,              // comparator feedback used to measure motor supply voltage
    input  wire[3:0] board_id,      // board id (rotary switch)
    input  wire[15:0] temp_sense,   // temperature sensor reading
    input  wire[11:0] reg_status12, // lowest 12-bits of status register (amplifier-related)

    // register file interface
    input  wire[15:0] reg_raddr,     // register read address
    input  wire[15:0] reg_waddr,     // register write address
    output reg[31:0] reg_rdata,      // register read data
    input  wire[31:0] reg_wdata,     // register write data
    input  wire reg_wen,             // write enable from FireWire module
    
    // Dallas chip status
    input  wire[31:0] ds_status,

    // Signals used to clear error flags
    output wire pwr_enable_cmd,

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
                // Byte 2: wdog timeout, isQuadDac (was eth1394), dout_cfg_valid, dout_cfg_bidir
                wdog_timeout, isQuadDac, dout_cfg_valid, dout_cfg_bidir,
                // mv_good, power enable, safety relay state, safety relay control
                mv_good, pwr_enable, ~relay, relay_on,
                // mv_fault, unused (00), ioexp_present
                ~mv_faultn, safety_fb, 1'b0, ioexp_present,
                // lowest 12-bits are for amplifier feedback
                reg_status12 };

    // dout[31] indicates that waveform table is driving at least one DOUT
    assign reg_digin = {v_fault, 1'b0, dout[31], mv_fb, enc_a, enc_b, enc_i, dout[3:0], neg_limit, pos_limit, home};

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
            // amplifier enable bits now handled in MotorChannelQLA
            // mask reg_wdata[17] with [16] for safety relay control
            relay_on <= reg_wdata[17] ? reg_wdata[16] : relay_on;
            // mask reg_wdata[19] with [18] for pwr_enable
            pwr_enable <= reg_wdata[19] ? reg_wdata[18] : pwr_enable;
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
    //    REG_PROMSTAT, REG_PROMRES, REG_IPADDR and REG_ETSTAT handled by FPGA module
    else begin
        case (reg_raddr[3:0])
        `REG_STATUS: reg_rdata <= reg_status;
        `REG_VERSION: reg_rdata <= VERSION;
        `REG_TEMPSNS: reg_rdata <= {16'd0, temp_sense};
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
