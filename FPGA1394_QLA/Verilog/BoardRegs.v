/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2008-2023 ERC CISST, Johns Hopkins University.
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
 *     12/14/22    Peter Kazanzides    Separated into BoardRegs.v and BoardRegs-QLA.v
 */


// device register file offset
`include "Constants.v" 

module BoardRegs
(
    // global clock
    input  wire sysclk, 
    output reg  reboot,
    
    // register file interface
    input  wire[15:0] reg_raddr,     // register read address
    input  wire[15:0] reg_waddr,     // register write address
    output reg[31:0] reg_rdata,      // register read data
    output wire reg_rwait,           // register read wait state
    input  wire[31:0] reg_wdata,     // register write data
    input  wire reg_wen,             // write enable from FireWire module

    output reg wdog_period_led,    // 1 -> LED1 displays wdog_period_status
    output reg[2:0] wdog_period_status,
    output reg wdog_timeout,       // watchdog timeout status flag
    input  wire wdog_clear         // clear watchdog timeout (e.g., on powerup)
);

    // -------------------------------------------------------------------------
    // define wires and registers
    //

    // Interface to Firewire PHY. The host PC writes phy_ctrl, which is
    // actually processed in Firewire.v or EthernetIO.v. The data saved here
    // is only for readback purposes.
    // The Firewire.v module actually issues the write to store the value
    // in phy_data, which can then be read by the host PC.
    reg[15:0] phy_ctrl;         // for phy request bitstream
    reg[15:0] phy_data;         // for phy register transfer data

    // watchdog timer
    reg[15:0] wdog_period;      // watchdog period, user writable
    initial wdog_period = 16'h1680;  // 0x1680 == 30 msec
    reg[23:0] wdog_count;       // watchdog timer counter (check upper 16 bits)

    // Git describe
    wire[31:0] git_desc;
    assign git_desc[31:4] = `GIT_SHA;
    assign git_desc[3] = `GIT_DIRTY;
    generate

        if (`GIT_COMMITS == 0)
            assign git_desc[2] = 1'b0;
        else
            assign git_desc[2] = 1'b1;

        // Lowest 2 bits compare FW_VERSION (F) to GIT_FW_VERSION (G)
        //   2'd0: F == G      Actual release (FW_VERSION) or post release update (FW_VERSION+),
        //                     if `GIT_DIRTY or `GIT_COMMITS
        //   2'd1: F == G+1    New firmware preview (FW_VERSION-)
        //   2'd2: F > G+1     Should not happen (FW_VERSION?)
        //   2'd3: F < G       Should not happen (FW_VERSION?)
        if (`FW_VERSION == `GIT_FW_VERSION)
            assign git_desc[1:0] = 2'd0;
        else if (`FW_VERSION == `GIT_FW_VERSION+1)
            assign git_desc[1:0] = 2'd1;
        else if (`FW_VERSION > `GIT_FW_VERSION+1)
            assign git_desc[1:0] = 2'd2;
        else // (`FW_VERSION < `GIT_FW_VERSION)
            assign git_desc[1:0] = 2'd3;

    endgenerate

//------------------------------------------------------------------------------
// hardware description
//

wire write_main;
assign write_main = ((reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4]==4'd0) && reg_wen) ? 1'b1 : 1'b0;

// return register data for reads
//    REG_PROMSTAT, REG_PROMRES, REG_IPADDR and REG_ETHSTAT handled elsewhere in FPGA module
always @(*) begin
    case (reg_raddr[3:0])
        `REG_PHYCTRL: reg_rdata = {16'd0, phy_ctrl};
        `REG_PHYDATA: reg_rdata = {16'd0, phy_data};
        `REG_TIMEOUT: reg_rdata = {wdog_period_led, 15'd0, wdog_period};
        `REG_FVERSION: reg_rdata = `FW_VERSION;
        `REG_GIT_DESC: reg_rdata = git_desc;
        default: reg_rdata = 32'd0;
    endcase
end

// Register reads have 0 wait
assign reg_rwait = 1'b0;

// write register data
always @(posedge(sysclk))
  begin
    // Set register values for writes
    // For REG_STATUS we only care about the FPGA reboot request bits [21:20]
    if (write_main) begin
        case (reg_waddr[3:0])
        `REG_STATUS:  reboot <= reg_wdata[21] ? reg_wdata[20] : 1'b0;
        `REG_PHYCTRL: phy_ctrl <= reg_wdata[15:0];
        `REG_PHYDATA: phy_data <= reg_wdata[15:0];
        `REG_TIMEOUT: {wdog_period_led, wdog_period} <= {reg_wdata[31], reg_wdata[15:0]};
        endcase
    end
end

// --------------------------------------------------------------------------
// Watchdog
// --------------------------------------------------------------------------

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

// watchdog timer and flag
//    timer (wdog_count) is cleared by any register write
//    timeout flag (wdog_timeout) is cleared by wdog_clear (powerup_cmd)
//
// The watchdog clock resolution is 5.208333 us (2^8 / 49.152 MHz), since
// we use a 24-bit counter and compare the upper 16 bits to wdog_period
// (previous implementations used ClkDiv to create wdog_clk).

always @(posedge(sysclk))
begin
    if (wdog_clear) begin
        wdog_count <= 24'd0;                    // clear the timer counter
        wdog_timeout <= 1'd0;                   // clear wdog_timeout
    end
    else if (reg_wen) begin
        // clear counter on any reg write
        wdog_count <= 24'd0;                    // clear the timer counter
    end
    else if (wdog_period != 16'd0) begin
        // watchdog only works when period is set
        if (wdog_count[23:8] == wdog_period) begin  // time between reg writes
            wdog_timeout <= 1'b1;                   // raise flag
        end
        else begin
            wdog_count <= wdog_count + 24'b1;       // increment timer counter
        end
    end
end

endmodule
