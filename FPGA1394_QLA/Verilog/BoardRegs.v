/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2008-2019 ERC CISST, Johns Hopkins University.
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
 */


// device register file offset
`include "Constants.v" 

// watchdog
`define WIDTH_WATCHDOG 8           // period = 5.208333 us (2^8 / 49.152 MHz) 

module BoardRegs(
    // global clock & reset
    input  wire sysclk, 
    input  wire clkaux,
    output reg  reset,
    
    // board input (PC writes)
    output wire[4:1] amp_disable,   // hardware connection to op amps
    input  wire[4:1] dout,          // digital outputs
    input  wire dout_cfg_valid,     // digital output configuration valid
    input  wire dout_cfg_bidir,     // whether digital outputs are bidirectional (also need to be inverted)
    output reg pwr_enable,          // enable motor power
    output reg relay_on,            // enable relay for safety loop-through
    output reg eth1394,             // 0: firewire mode 1: ethernet-1394 mode
    
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
    input  wire[3:0] board_id,      // board id (rotary switch)
    input  wire[15:0] temp_sense,   // temperature sensor reading
    
    // register file interface
    input  wire[15:0] reg_raddr,     // register read address
    input  wire[15:0] reg_waddr,     // register write address
    output reg[31:0] reg_rdata,     // register read data
    input  wire[31:0] reg_wdata,    // register write data
    input  wire reg_wen,            // write enable from FireWire module
    
    // PROM feedback
    input  wire[31:0] prom_status,
    input  wire[31:0] prom_result,

    // Ethernet IP address
    input  wire[31:0] ip_address,

    // Ethernet feedback
    input  wire[31:0] eth_result,

    // Dallas chip status
    input  wire[31:0] ds_status,

    // Safety amp_disable
    input  wire[4:1] safety_amp_disable,

    // Signals used to clear error flags
    output wire pwr_enable_cmd,
    output wire[4:1] amp_enable_cmd,

    output reg[31:0] reg_debug     // for debug purpose only
);

    // -------------------------------------------------------------------------
    // define wires and registers
    //

    // registered data
    reg[3:0] reg_disable;       // register the disable signals
    reg[15:0] phy_ctrl;         // for phy request bitstream
    reg[15:0] phy_data;         // for phy register transfer data

    // watchdog timer
    wire wdog_clk;              // watchdog clock
    reg  wdog_timeout;          // watchdog timeout status flag
    reg[15:0] wdog_period;      // watchdog period, user writable
    reg[15:0] wdog_count;       // watchdog timer counter
    
    // mv good timer                                                                                                                                       
    reg[15:0] mv_good_counter;  // mv_good counter 
    reg[4:1] mv_amp_disable;    // mv good amp_disable

    // reset signal generation
    reg[6:0] reset_shift;       // counts number of clocks after reset
    reg reset_soft_trigger;     // trigger global reset when set
    initial begin
        reset_shift = 0;
        reset = 1;
    end

//------------------------------------------------------------------------------
// hardware description
//
initial reg_debug = 32'h2000;

// mv_amp_disable for 40 ms sleep after board pwr enable
assign amp_disable = (reg_disable[3:0] | mv_amp_disable[4:1]);

wire write_main;
assign write_main = ((reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4]==0) && reg_wen) ? 1'b1 : 1'b0;
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
always @(posedge(sysclk) or negedge(reset))
  begin
     // what to do on reset/startup
     if (reset == 0) begin
        reg_rdata <= 0;          // clear read output register
        reg_disable <= 4'hf;     // start up all disabled
        pwr_enable <= 0;         // start up with power off
        phy_ctrl <= 0;           // clear phy command register
        phy_data <= 0;           // clear phy data output register
        wdog_period <= 16'hffff; // disables watchdog by default
        relay_on <= 0;           // start with safety relay off
        reset_soft_trigger <= 1'b0;  // clear reset_soft_trigger
        eth1394 <= 1'b0;    // clear eth1394 mode (i.e. normal FireWire mode)
     end

    // set register values for writes
    else if (write_main) begin
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
            // mask reg_wdata[21] with [20] for soft_reset
            reset_soft_trigger <= reg_wdata[21] ? reg_wdata[20] : 1'b0; 
            // mask reg_wdata[23] with [22] for eth1394 mode 
            eth1394 <= reg_wdata[23] ? reg_wdata[22] : eth1394;
        end
        `REG_PHYCTRL: phy_ctrl <= reg_wdata[15:0];
        `REG_PHYDATA: phy_data <= reg_wdata[15:0];
        `REG_TIMEOUT: wdog_period <= reg_wdata[15:0];
        // Write to DOUT is handled in CtrlDout.v
        // Write to PROM command register (8) is handled in M25P16.v
        // Write to IP address is handled in EthernetIO.v
        `REG_DEBUG:   reg_debug <= reg_wdata[31:0];
        endcase
    end

    // return register data for reads
    else begin
        case (reg_raddr[3:0])
        `REG_STATUS: reg_rdata <= { 
                // Byte 3: num channels (4), board id
                4'd4, board_id,
                // Byte 2: wdog timeout, eth1394 mode, dout_cfg_valid, dout_cfg_bidir
                wdog_timeout, eth1394, dout_cfg_valid, dout_cfg_bidir,
                // mv_good, power enable, safety relay state, safety relay control      
                mv_good, pwr_enable, ~relay, relay_on,   
                // mv_fault, unused (0)
                ~mv_faultn, 3'd0,
                // amplifier: 1 -> amplifier on, 0 -> fault (4 axes)
                fault,
                // Byte 0: 1 -> amplifier enabled, 0 -> disabled
                safety_amp_disable[4:1], ~reg_disable[3:0] };     
        `REG_PHYCTRL: reg_rdata <= phy_ctrl;
        `REG_PHYDATA: reg_rdata <= phy_data;
        `REG_TIMEOUT: reg_rdata <= wdog_period;
        `REG_VERSION: reg_rdata <= `VERSION;
        `REG_TEMPSNS: reg_rdata <= {16'd0, temp_sense};
        `REG_DIGIOUT: reg_rdata <= dout;
        `REG_FVERSION: reg_rdata <= `FW_VERSION;
        `REG_PROMSTAT: reg_rdata <= prom_status;
        `REG_PROMRES: reg_rdata <= prom_result;
        `REG_DSSTAT: reg_rdata <= ds_status;
        `REG_DIGIN: reg_rdata <= {v_fault, 3'd0, enc_a, enc_b, enc_i, dout, neg_limit, pos_limit, home};
        `REG_IPADDR: reg_rdata <= ip_address;
        `REG_ETHRES: reg_rdata <= eth_result;
        `REG_DEBUG:  reg_rdata <= reg_debug;

        default:  reg_rdata <= 32'd0;
        endcase

        // Disable axes when wdog timeout or safety amp disable. Note the minor efficiency gain
        // below by combining safety_amp_disable with !wdog_timeout.
        reg_disable[3:0] <= reg_disable[3:0] | (wdog_timeout ? 4'b1111 : safety_amp_disable[4:1]);
    end
end

// --------------------------------------------------------------------------
// Reset module
// --------------------------------------------------------------------------
// derive watchdog clock
ClkDiv divWdog(sysclk, wdog_clk);
defparam divWdog.width = `WIDTH_WATCHDOG;

// watchdog timer and flag, resets via any register write
always @(posedge(wdog_clk) or negedge(reset) or posedge(reg_wen) or posedge(powerup_cmd))
begin
    if (reset==0 || powerup_cmd) begin
        wdog_count <= 0;                        // reset the timer counter
        wdog_timeout <= 0;                      // clear wdog_timeout
    end
    else if (reg_wen) begin
        // reset counter on any reg write
        wdog_count <= 0;                        // reset the timer counter
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
always @(posedge(wdog_clk) or negedge(reset))
begin
    if (reset == 0) begin
        mv_amp_disable <= 4'b0000;
        mv_good_counter <= 16'd0;
    end
    else if ((mv_good == 1'b1) && (mv_good_counter < 16'd7680)) begin
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

   
// --------------------------------------------------------------------------
// Reset module
//   - generate global reset signal, 
//     assumes reset_shift = 0 at power up per spec
// --------------------------------------------------------------------------
always @(posedge(clkaux))
begin
    // power up with /reset inactive
    if (reset_shift < 24) begin
        reset_shift <= reset_shift + 1'b1;
        reset <= 1;
    end
    // falling edge activates system reset
    else if (reset_shift < 49) begin
        reset_shift <= reset_shift + 1'b1;
        reset <= 0;
    end
    // deactivate /reset to let system run
    else if (reset_soft_trigger) begin
        reset_shift <= 0;
        reset <= 1;
    end 
    else
        reset <= 1;
end

endmodule
