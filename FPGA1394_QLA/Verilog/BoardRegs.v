/*******************************************************************************
 *
 * Copyright(C) 2008-2012 ERC CISST, Johns Hopkins University.
 *
 * This module contains a register file dedicated to general board parameters.
 * Separate register files are maintained for each I/O channel (SpiCtrl).
 *
 * Revision history
 *     07/17/08    Paul Thienphrapa    Initial revision - SnakeFPGA-rev2
 *     12/21/11    Paul Thienphrapa    Adapted for FPGA1394_QLA
 *     02/22/12    Paul Thienphrapa    Minor fixes for power enable and reset
 */

// channel 0 (board) registers
`define REG_STATUS 4'd0            // board id (8), fault (8), enable/masks (16)
`define REG_PHYCTRL 4'd1           // phy request bitstream (to request reg r/w)
`define REG_PHYDATA 4'd2           // holder for phy register read contents
`define REG_TIMEOUT 4'd3           // watchdog timer period register
`define REG_VERSION 4'd4           // read-only version number address
`define REG_TEMPSNS 4'd5           // temperature sensors (2x 8 bits concatenated)
`define REG_DIGIOUT 4'd6           // programmable digital outputs
`define REG_FIRMWARE_VERSION 4'd7  // firmware version
`define REG_PROMSTAT 4'd8          // PROM interface status
`define REG_PROMRES 4'd9           // PROM result (from M25P16)
`define REG_DIGIN 4'd10            // Digital inputs (home, neg lim, pos lim)

`define VERSION 32'h514C4131       // hard-wired version number "QLA1" = 0x514C4131 
`define FW_VERSION 32'h01          // firmware version = 1  
`define WIDTH_WATCHDOG 8           // period = 5.208333 us (2^8 / 49.152 MHz)

module BoardRegs(
    sysclk, clkaux, reset,
    amp_disable, dout, pwr_enable, relay_on,
    neg_limit, pos_limit, home, fault,
    relay, mv_good, v_fault,
    board_id, temp_sense,
    reg_addr, reg_rdata,
    reg_wdata, wr_en,
    prom_status, prom_result
);

    // -------------------------------------------------------------------------
    // define I/Os
    //

    // global clock and reset signals
    input sysclk;
    input clkaux;
    output reset;

    // board inputs (PC writes)
    output[4:1] amp_disable;
    output[4:1] dout;
    output pwr_enable;
    output relay_on;

    // board outputs (PC reads)
    input[4:1] neg_limit, pos_limit, home, fault;
    input relay, mv_good, v_fault;
    input[3:0] board_id;
    input[15:0] temp_sense;

    // register file interface
    input wr_en;
    input[7:0] reg_addr;
    output[31:0] reg_rdata;
    input[31:0] reg_wdata;

    // PROM feedback
    input[31:0]  prom_status;
    input[31:0]  prom_result;

    // -------------------------------------------------------------------------
    // define wires and registers
    //

    // registered data
    reg[31:0] reg_rdata;        // register the data output
    reg[15:0] reg_disable;      // register the disable signals
    reg[15:0] phy_ctrl;         // for phy request bitstream
    reg[15:0] phy_data;         // for phy register transfer data

    // board inputs (PC writes)
    reg[4:1] dout;              // digital outputs
    reg pwr_enable;             // enable motor power
    reg relay_on;               // enable relay for safety loop-through

    // watchdog timer
    wire wdog_clk;              // watchdog clock
    reg wdog_timeout;           // watchdog timeout status flag
    reg[15:0] wdog_period;      // watchdog period, user writable
    reg[15:0] wdog_count;       // watchdog timer counter

    // reset signal generation
    reg reset;                  // global reset signal
    reg[6:0] reset_shift;       // counts number of clocks after reset
    initial begin
        reset_shift = 0;
        reset = 1;
    end

//------------------------------------------------------------------------------
// hardware description
//

assign amp_disable = wdog_timeout ? 4'b1111 : reg_disable[3:0];

// clocked process simulating a register file
always @(posedge(sysclk) or negedge(reset))
begin
    // what to do on reset/startup
    if (reset == 0) begin
        reg_rdata <= 0;          // clear read output register
        reg_disable <= 8'hff;    // start up all disabled
        //pwr_enable <= 0;         // start up with power off
        pwr_enable <= 1;         // start up with power on
        phy_ctrl <= 0;           // clear phy command register
        phy_data <= 0;           // clear phy data output register
        wdog_period <= 0;        // disables watchdog by default
        relay_on <= 0;           // start with safety relay off
        dout <= 0;               // clear digital outputs
    end

    // set register values for writes
    else if (reg_addr[7:4]==0 && wr_en) begin
        case (reg_addr[3:0])
        `REG_STATUS: begin
            // mask reg_wdata[15:8] with [7:0] for disable (~enable) control
            reg_disable[15:8] <= reg_wdata[15:8];
            reg_disable[7] <= reg_wdata[15] ? ~reg_wdata[7] : reg_disable[7];
            reg_disable[6] <= reg_wdata[14] ? ~reg_wdata[6] : reg_disable[6];
            reg_disable[5] <= reg_wdata[13] ? ~reg_wdata[5] : reg_disable[5];
            reg_disable[4] <= reg_wdata[12] ? ~reg_wdata[4] : reg_disable[4];
            reg_disable[3] <= reg_wdata[11] ? ~reg_wdata[3] : reg_disable[3];
            reg_disable[2] <= reg_wdata[10] ? ~reg_wdata[2] : reg_disable[2];
            reg_disable[1] <= reg_wdata[9] ? ~reg_wdata[1] : reg_disable[1];
            reg_disable[0] <= reg_wdata[8] ? ~reg_wdata[0] : reg_disable[0];
            // pwr_enable is always on
            relay_on <= reg_wdata[16];
        end
        `REG_PHYCTRL: phy_ctrl <= reg_wdata[15:0];
        `REG_PHYDATA: phy_data <= reg_wdata[15:0];
        `REG_TIMEOUT: wdog_period <= reg_wdata[15:0];
        `REG_DIGIOUT: dout <= reg_wdata[3:0];
        // Write to PROM command register (8) is handled in M25P16.v
        endcase
    end

    // return register data for reads
    else begin
        case (reg_addr[3:0])
        //// TODO: return neg_limit/pos_limit/home[4:1], temp_sense in status?
        `REG_STATUS: reg_rdata <= { 2'd0, pwr_enable, relay_on, board_id, wdog_timeout, 3'd0, fault, reg_disable[15:8], ~reg_disable[7:0] };
        `REG_PHYCTRL: reg_rdata <= phy_ctrl;
        `REG_PHYDATA: reg_rdata <= phy_data;
        `REG_TIMEOUT: reg_rdata <= wdog_period;
        `REG_VERSION: reg_rdata <= `VERSION;
        `REG_TEMPSNS: reg_rdata <= temp_sense;
        `REG_DIGIOUT: reg_rdata <= dout;
        `REG_FIRMWARE_VERSION: reg_rdata <= `FW_VERSION;
        `REG_PROMSTAT: reg_rdata <= prom_status;
        `REG_PROMRES: reg_rdata <= prom_result;
        `REG_DIGIN: reg_rdata <= { 16'd0, 1'b0, relay, mv_good, v_fault, neg_limit, pos_limit, home };
         default:  reg_rdata <= 32'd0;
        endcase
    end

end

// derive watchdog clock
ClkDiv divWdog(sysclk, wdog_clk);
defparam divWdog.width = `WIDTH_WATCHDOG;

// watchdog timer and flag, resets via any register write
always @(posedge(wdog_clk) or negedge(reset) or posedge(wr_en))
begin
    // reset counter/flag on reg write
    if (reset==0 || wr_en) begin
        wdog_count <= 0;                        // reset the timer counter
        wdog_timeout <= 0;                      // clear the timeout flag
    end

    // watchdog only works when period is set
    else if (wdog_period) begin
        if (wdog_count < wdog_period)           // time between reg writes
            wdog_count <= wdog_count + 1'b1;    // increment timer counter
        else
            wdog_timeout <= 1'b1;               // raise flag
    end
end

// generate global reset signal, assumes reset_shift = 0 at power up per spec
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
    else
        reset <= 1;
end

endmodule
