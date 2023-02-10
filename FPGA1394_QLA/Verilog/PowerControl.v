/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2022 ERC CISST, Johns Hopkins University.
 *
 * Handles board and per-motor power control.
 * All signals in `interlocks` must be asserted for axis power to be enabled.
 *
 * Conventions:
 *   interlocks[0] fw/eth WDT good.
 *   interlocks[1] MV WDT good.
 *   interlocks[2] ESPM comm WDT good.
 *   interlocks[3] ESII/ESCC WDT good.
 */
`include "Constants.v"

module PowerControl
#(parameter NUM_INTERLOCKS = 4, NUM_MOTORS = 10)
(
    input sysclk,
    input [NUM_INTERLOCKS - 1:0] interlocks, // Any cleared bit disables all channels.

    input [1:NUM_MOTORS] motor_channel_fault, // Each motor channel can request disable due to fault
    output wire [1:NUM_MOTORS] motor_channel_clear_fault, // Reset fault in each motor channel

    output reg [1:NUM_MOTORS] motor_channel_enable_pin, // Final motor enable state, connect to hardware
    output wire [1:NUM_MOTORS] motor_channel_enable_requested, // Commanded motor channel enable state 
    output reg pwr_enable, // motor power supply state, connect to hardware
    output wire wdog_clear,

    // register file interface
    input  wire[15:0] reg_raddr,     // register read address
    input  wire[15:0] reg_waddr,     // register write address
    output reg[31:0] reg_rdata,      // register read data
    input  wire[31:0] reg_wdata,     // register write data
    input  wire reg_wen              // write enable from FireWire module
);

wire write_main;
assign write_main = ((reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4]==4'd0) && reg_wen) ? 1'b1 : 1'b0;
wire write_status;
assign write_status = (write_main && (reg_waddr[3:0] == `REG_STATUS)) ? 1'b1 : 1'b0;
wire pwr_enable_cmd;
// pwr_enable_cmd indicates that the host is attempting to enable board power.
// This is used to clear error flags, such as wdog_timeout and safety_amp_disable.
assign pwr_enable_cmd = write_status ? (reg_wdata[19]&reg_wdata[18]) : 1'd0;
wire [3:0] wchannel = reg_waddr[7:4];

reg [NUM_INTERLOCKS - 1:0] bypass_interlocks;

reg [1:NUM_MOTORS] reg_enable;
reg [1:NUM_MOTORS] amp_enable_cmd;
reg [1:NUM_MOTORS] amp_enable_pending;
assign motor_channel_enable_requested = reg_enable;

assign wdog_clear = pwr_enable_cmd || |amp_enable_cmd;


assign motor_channel_clear_fault = amp_enable_cmd | (pwr_enable_cmd ? 'hFFFF : 'h0000);
integer i;

always @(posedge sysclk) begin
    motor_channel_enable_pin <= (motor_channel_enable_pin | amp_enable_pending) &
        reg_enable & ~motor_channel_fault &
        ((&(interlocks | bypass_interlocks)) ? 'hFFFF : 'h0000); 
    for (i=1; i<=NUM_MOTORS; i=i+1) begin
        if (amp_enable_cmd[i]) amp_enable_pending[i] <= 'b1;
        if (motor_channel_enable_pin[i]) amp_enable_pending[i] <= 'b0;
    end
       
    if (write_main && reg_waddr[3:0] == `REG_STATUS) begin
        pwr_enable <= reg_wdata[19] ? reg_wdata[18] : pwr_enable;
    end

    if (reg_waddr[15:12]==`ADDR_MAIN && reg_waddr[3:0]==`OFF_DAC_CTRL && reg_wen) begin
        reg_enable[wchannel] <= pwr_enable && (reg_wdata[29] ? reg_wdata[28] : reg_enable[wchannel]);
        if (reg_wdata[28] & reg_wdata[29]) amp_enable_cmd[wchannel] <= 'b1;
    end else begin
        amp_enable_cmd <= 'h0;
    end

    if (reg_waddr[15:12]==`ADDR_BOARD_SPECIFIC && reg_wen) begin
        case (reg_waddr[11:0])
            'h100: bypass_interlocks <= reg_wdata;
        endcase
    end
end


endmodule