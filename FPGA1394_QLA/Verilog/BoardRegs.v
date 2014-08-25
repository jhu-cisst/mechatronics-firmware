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
 *     05/08/13    Zihan Chen          Fix watchdog 
 *     05/19/13    Zihan Chen          Add mv_good 40 ms sleep
 */


// device register file offset
`include "Constants.v" 

// watchdog
`define WIDTH_WATCHDOG 8           // period = 5.208333 us (2^8 / 49.152 MHz) 

module BoardRegs(
    // glocal clock & reset 
    input  wire sysclk, 
    input  wire clkaux,
    output reg  reset,
    
    // board input (PC writes)
    output wire[4:1] amp_disable,
    output reg[4:1]  dout,          // digital outputs
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
    input  wire mv_good,            // motor voltage good 
    input  wire v_fault,           
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
    
    // Safety amp_disable
    input  wire[4:1] safety_amp_disable
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
    reg wdog_timeout;           // watchdog timeout status flag
    reg[15:0] wdog_period;      // watchdog period, user writable
    reg[15:0] wdog_count;       // watchdog timer counter
    reg[4:1] wdog_amp_disable;  // watchdog amp_disable
    
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

// mv_amp_disable for 40 ms sleep after board pwr enable
assign amp_disable = (reg_disable[3:0] | mv_amp_disable[4:1]);

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
        dout <= 0;               // clear digital outputs 
        reset_soft_trigger <= 1'b0;  // clear reset_soft_trigger
        eth1394 <= 1'b0;    // clear eth1394 mode (i.e. normal FireWire mode)
     end

    // set register values for writes
    else if (reg_waddr[15:12]==`ADDR_MAIN && reg_waddr[7:4]==0 && reg_wen) begin
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
        `REG_DIGIOUT: begin
            dout[1] <= reg_wdata[8] ? reg_wdata[0] : dout[1];
            dout[2] <= reg_wdata[9] ? reg_wdata[1] : dout[2];
            dout[3] <= reg_wdata[10] ? reg_wdata[2] : dout[3];
            dout[4] <= reg_wdata[11] ? reg_wdata[3] : dout[4];
        end
        // Write to PROM command register (8) is handled in M25P16.v
        endcase
    end

    // return register data for reads
    else begin
        case (reg_raddr[3:0])
        `REG_STATUS: reg_rdata <= { 
                // Byte 3: num channels (4), board id
                4'd4, board_id,
                // Byte 2: wdog timeout, eth1394 mode
                wdog_timeout, eth1394, 2'd0,
                // mv_good, power enable, safety relay state, safety relay control      
                mv_good, pwr_enable, ~relay, relay_on,   
                // Byte 1: 1 -> amplifier on, 0 -> fault (up to 8 axes)
                4'd0, fault,
                // Byte 0: 1 -> amplifier enabled, 0 -> disabled (up to 8 axes)                   
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
        `REG_DIGIN: reg_rdata <= {v_fault, 3'd0, enc_a, enc_b, enc_i, dout, neg_limit, pos_limit, home};

        // `REG_SAFETY: reg_rdata <= { 28'd0, safety_amp_disable};
        // `REG_WDOG: reg_rdata <= {28'd0, wdog_amp_disable};
        // `REG_REGDISABLE: reg_rdata <= {28'd0, amp_disable};
        
        default:  reg_rdata <= 32'd0;
        endcase
            
        // disable all axis when wdog timeout     
        if ( (wdog_amp_disable != 4'd0) || (safety_amp_disable != 4'd0) ) 
        begin
            reg_disable[3:0] <= (reg_disable[3:0] | wdog_amp_disable[4:1] | safety_amp_disable[4:1]);
        end
    end
end

// --------------------------------------------------------------------------
// Reset module
// --------------------------------------------------------------------------
// derive watchdog clock
ClkDiv divWdog(sysclk, wdog_clk);
defparam divWdog.width = `WIDTH_WATCHDOG;

// watchdog timer and flag, resets via any register write
always @(posedge(wdog_clk) or negedge(reset) or posedge(reg_wen))
begin
    // reset counter/flag on reg write
    if (reset==0 || reg_wen ) begin
        wdog_count <= 0;                        // reset the timer counter
        wdog_timeout <= 0;                      // clear the timeout flag
        wdog_amp_disable <= 4'b0000;            // clear wdog_amp_disable 
    end

    // watchdog only works when period is set
    else if (wdog_period) begin
        if (wdog_count < wdog_period) begin     // time between reg writes
            wdog_count <= wdog_count + 1'b1;    // increment timer counter
        end
        else begin
            wdog_timeout <= 1'b1;               // raise flag
            wdog_amp_disable <= 4'b1111;        // set wdog_amp_disable
        end
    end
end

// to save resoure use wdog_clk, period = 5.208333 us
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