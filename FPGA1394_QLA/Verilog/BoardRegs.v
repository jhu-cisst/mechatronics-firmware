/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2008-2022 ERC CISST, Johns Hopkins University.
 *
 * This module contains a register file dedicated to general board parameters.
 * Separate register files are maintained for each I/O channel (SpiCtrl).
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
 */


// device register file offset
`include "Constants.v" 

// watchdog
`define WIDTH_WATCHDOG 8           // period = 5.208333 us (2^8 / 49.152 MHz) 

module BoardRegs(
    // global clock
    input  wire sysclk, 
    output reg  reboot,
    
    // board input (PC writes)
    output wire[4:1] amp_disable,   // hardware connection to op amps
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
    input  wire[4:1] fault,
    
    input  wire relay,              // relay signal
    input  wire mv_faultn,          // motor power fault (active low) from LT4356, over-voltage or over-current
    input  wire mv_good,            // motor voltage good 
    input  wire v_fault,            // encoder supply voltage fault
    input  wire safety_fb,          // whether voltage present on safety line
    input  wire mv_fb,              // comparator feedback used to measure motor supply voltage
    input  wire[3:0] board_id,      // board id (rotary switch)
    input  wire[15:0] temp_sense,   // temperature sensor reading
    
    // register file interface
    input  wire[15:0] reg_raddr,     // register read address
    input  wire[15:0] reg_waddr,     // register write address
    output reg[31:0] reg_rdata,     // register read data
    input  wire[31:0] reg_wdata,    // register write data
    input  wire reg_wen,            // write enable from FireWire module
    
    // Dallas chip status
    input  wire[31:0] ds_status,

    // Safety amp_disable
    input  wire[4:1] safety_amp_disable,

    // Signals used to clear error flags
    output wire pwr_enable_cmd,
    output wire[4:1] amp_enable_cmd,

    output wire[31:0] reg_status,  // Status register (for reading)
    output wire[31:0] reg_digin,   // Digital I/O register (for reading)
    output reg      wdog_period_led,    // 1 -> LED1 displays wdog_period_status
    output reg[2:0] wdog_period_status,
    output reg wdog_timeout,       // watchdog timeout status flag
    output reg[31:0] reg_debug     // for debug purpose only
);

    // -------------------------------------------------------------------------
    // define wires and registers
    //

    // registered data
    reg[3:0] reg_disable;       // register the disable signals
    initial reg_disable = 4'hf; // start up all disabled
    reg[15:0] phy_ctrl;         // for phy request bitstream
    reg[15:0] phy_data;         // for phy register transfer data

    // watchdog timer
    wire wdog_clk;              // watchdog clock
    reg[15:0] wdog_period;      // watchdog period, user writable
    initial wdog_period = 16'h1680;  // 0x1680 == 30 msec
    reg[15:0] wdog_count;       // watchdog timer counter

    // mv good timer
    reg[15:0] mv_good_counter;  // mv_good counter
    reg[4:1] mv_amp_disable;    // mv good amp_disable

    assign reg_status = {
                // Byte 3: num channels (4), board id
                4'd4, board_id,
                // Byte 2: wdog timeout, isQuadDac (was eth1394), dout_cfg_valid, dout_cfg_bidir
                wdog_timeout, isQuadDac, dout_cfg_valid, dout_cfg_bidir,
                // mv_good, power enable, safety relay state, safety relay control
                mv_good, pwr_enable, ~relay, relay_on,
                // mv_fault, unused (00), ioexp_present
                ~mv_faultn, safety_fb, 1'b0, ioexp_present,
                // amplifier: 1 -> amplifier on, 0 -> fault (4 axes)
                fault,
                // Byte 0: 1 -> amplifier enabled, 0 -> disabled
                safety_amp_disable[4:1], ~reg_disable[3:0] };

    // dout[31] indicates that waveform table is driving at least one DOUT
    assign reg_digin = {v_fault, 1'b0, dout[31], mv_fb, enc_a, enc_b, enc_i, dout[3:0], neg_limit, pos_limit, home};

//------------------------------------------------------------------------------
// hardware description
//
initial reg_debug = 32'h2000;

// mv_amp_disable for 40 ms sleep after board pwr enable
assign amp_disable = (reg_disable[3:0] | mv_amp_disable[4:1]);

wire write_main;
assign write_main = ((reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4]==4'd0) && reg_wen) ? 1'b1 : 1'b0;
wire write_status;
assign write_status = (write_main && (reg_waddr[3:0] == `REG_STATUS)) ? 1'b1 : 1'b0;

// pwr_enable_cmd indicates that the host is attempting to enable board power.
// This is used to clear error flags, such as wdog_timeout and safety_amp_disable.
assign pwr_enable_cmd = write_status ? (reg_wdata[19]&reg_wdata[18]) : 1'd0;

// amp_enable_cmd indicates that the host is attempting to enable amplifier power.
// This is used to clear error flags, such as wdog_timeout and safety_amp_disable.
assign amp_enable_cmd = write_status ? {reg_wdata[11]&reg_wdata[3], reg_wdata[10]&reg_wdata[2], 
                                        reg_wdata[ 9]&reg_wdata[1], reg_wdata[ 8]&reg_wdata[0]}
                                     : 4'd0;

// powerup_cmd is true if the host is attempting to enable board power or any amplifier.
wire powerup_cmd;
assign powerup_cmd = pwr_enable_cmd | amp_enable_cmd[4] | amp_enable_cmd[3] | amp_enable_cmd[2] | amp_enable_cmd[1];

// clocked process simulating a register file
always @(posedge(sysclk))
  begin
    // set register values for writes
    if (write_main) begin
        case (reg_waddr[3:0])
        `REG_STATUS: begin
            // mask reg_wdata[15:8] with [7:0] for disable (~enable) control
            // ([15:12] and [7:4] are for an 8-axis system)
            reg_disable[3] <= ~pwr_enable || (reg_wdata[11] ? ~reg_wdata[3] : reg_disable[3]);
            reg_disable[2] <= ~pwr_enable || (reg_wdata[10] ? ~reg_wdata[2] : reg_disable[2]);
            reg_disable[1] <= ~pwr_enable || (reg_wdata[9] ? ~reg_wdata[1] : reg_disable[1]);
            reg_disable[0] <= ~pwr_enable || (reg_wdata[8] ? ~reg_wdata[0] : reg_disable[0]);
            // mask reg_wdata[17] with [16] for safety relay control
            relay_on <= reg_wdata[17] ? reg_wdata[16] : relay_on;
            // mask reg_wdata[19] with [18] for pwr_enable
            pwr_enable <= reg_wdata[19] ? reg_wdata[18] : pwr_enable;
            // mask reg_wdata[21] with [20] for reboot (was reset prior to Rev 7)
            reboot <= reg_wdata[21] ? reg_wdata[20] : 1'b0;
            // Previously, masked reg_wdata[23] with [22] for eth1394 mode
            // use reg_wdata[22] to reset isQuadDac
            dac_test_reset <= reg_wdata[22];
            // use reg_wdata[23] to redetect I/O expander (MAX7317)
            ioexp_cfg_reset <= reg_wdata[23];
            // use reg_wdata[24] to reset dout_cfg_valid
            dout_cfg_reset <= reg_wdata[24];
        end
        `REG_PHYCTRL: phy_ctrl <= reg_wdata[15:0];
        `REG_PHYDATA: phy_data <= reg_wdata[15:0];
        `REG_TIMEOUT: {wdog_period_led, wdog_period} <= {reg_wdata[31], reg_wdata[15:0]};
        // Write to DOUT is handled in CtrlDout.v
        // Write to PROM command register (8) is handled in M25P16.v
        // Write to IP address is handled in EthernetIO.v
        `REG_DEBUG:   reg_debug <= reg_wdata[31:0];
        endcase
    end

    // return register data for reads
    //    REG_PROMSTAT, REG_PROMRES, REG_IPADDR and REG_ETHRES handled by FPGA module
    else begin
        case (reg_raddr[3:0])
        `REG_STATUS: reg_rdata <= reg_status;
        `REG_PHYCTRL: reg_rdata <= {16'd0, phy_ctrl};
        `REG_PHYDATA: reg_rdata <= {16'd0, phy_data};
        `REG_TIMEOUT: reg_rdata <= {wdog_period_led, 15'd0, wdog_period};
        `REG_VERSION: reg_rdata <= `VERSION;
        `REG_TEMPSNS: reg_rdata <= {16'd0, temp_sense};
        `REG_DIGIOUT: reg_rdata <= dout;
        `REG_FVERSION: reg_rdata <= `FW_VERSION;
        `REG_DSSTAT: reg_rdata <= ds_status;
        `REG_DIGIN: reg_rdata <= reg_digin;
        `REG_DEBUG:  reg_rdata <= reg_debug;

        default:  reg_rdata <= 32'd0;
        endcase

        // Disable axes when wdog timeout or safety amp disable. Note the minor efficiency gain
        // below by combining safety_amp_disable with !wdog_timeout.
        reg_disable[3:0] <= reg_disable[3:0] | (wdog_timeout ? 4'b1111 : safety_amp_disable[4:1]);
        // Turn off dout_cfg_reset in case it was previously set
        dout_cfg_reset <= 1'b0;
        // Turn off ioexp_cfg_reset in case it was previously set
        ioexp_cfg_reset <= 1'b0;
        // Turn off dac_test_reset in case it was previously set
        dac_test_reset <= 1'b0;
    end
end

// --------------------------------------------------------------------------
// Watchdog
// --------------------------------------------------------------------------
// derive watchdog clock
ClkDiv divWdog(sysclk, wdog_clk);
defparam divWdog.width = `WIDTH_WATCHDOG;

// assign phase states to wdog_period_status
always @(wdog_period)                           // executes if wdog_period is updated
begin
    if (wdog_period == 16'h0) begin
        wdog_period_status <= `WDOG_DISABLE;      // watchdog period = 0ms
    end
    else if (wdog_period <= 16'h2580) begin
        wdog_period_status <= `WDOG_PHASE_ONE;    // watchdog period between 0ms and 50 ms
    end
    else if (wdog_period <= 16'h4B00) begin
        wdog_period_status <= `WDOG_PHASE_TWO;    // watchdog period between 50ms and 100 ms
    end
    else if (wdog_period <= 16'h7080) begin
        wdog_period_status <= `WDOG_PHASE_THREE;  // watchdog period between 100ms and 150 ms
    end
    else if (wdog_period <= 16'h9600) begin
        wdog_period_status <= `WDOG_PHASE_FOUR;   // watchdog period between 150ms and 200 ms
    end
    else begin
        wdog_period_status <= `WDOG_PHASE_FIVE;   // watchdog period larger than 200ms
    end
end

// watchdog timer and flag, cleared via any register write
always @(posedge(wdog_clk) or posedge(reg_wen) or posedge(powerup_cmd))
begin
    if (powerup_cmd) begin
        wdog_count <= 0;                        // clear the timer counter
        wdog_timeout <= 0;                      // clear wdog_timeout
    end
    else if (reg_wen) begin
        // clear counter on any reg write
        wdog_count <= 0;                        // clear the timer counter
    end
    else if (wdog_period) begin
        // watchdog only works when period is set
        if (wdog_count < wdog_period) begin     // time between reg writes
            wdog_count <= wdog_count + 1'b1;    // increment timer counter
        end
        else begin
            wdog_timeout <= 1'b1;               // raise flag
        end
    end
end

// to save resources use wdog_clk, period = 5.208333 us
// 40 ms = 7680 cnts
always @(posedge(wdog_clk))
begin
    if ((mv_good == 1'b1) && (mv_good_counter < 16'd7680)) begin
        mv_good_counter <= mv_good_counter + 1'b1;
        mv_amp_disable <= 4'b1111;
    end 
    else if (mv_good == 1'b1) begin
        mv_amp_disable <= 4'b0000;
    end
    else begin
        mv_amp_disable <= 4'b1111;
        mv_good_counter <= 16'd0;
    end
end

endmodule
