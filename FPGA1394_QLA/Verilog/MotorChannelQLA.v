/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2022 ERC CISST, Johns Hopkins University.
 *
 * This module handles a motor channel for the QLA
 *
 * Revision history
 *     08/15/22                        Initial version
 */

module MotorChannelQLA
#(parameter CHANNEL = 4'd1)
(
    input wire clk,                  // system clock (49.152 MHz)
    input wire delay_clk,            // clock to use for delay (1.536 MHz)

    input  wire[15:0] reg_waddr,     // write address
    input  wire[31:0] reg_wdata,     // register write data
    input  wire reg_wen,             // reg write enable

    input wire ioexp_present,        // whether I/O expander present

    input wire safety_amp_disable,   // from SafetyCheck module
    input wire amp_disable,          // from BoardRegs (set by host PC)
    output wire amp_disable_pin,     // signal to drive FPGA pin

    output reg[15:0] cur_cmd,        // Commanded current (or voltage)
    output reg[3:0] ctrl_mode,       // Control mode
    output wire cur_ctrl             // 1 -> current control, 0 -> voltage control
);

// Current or voltage control
//   (ctrl_mode == 0) --> current control, set cur_ctrl = 1
//   (ctrl_mode == 1) --> voltage control, set cur_ctrl = 0
// For any other value of ctrl_mode, assume current control.
// Also, can only have voltage control if ioexp_present (QLA 1.5+).
assign cur_ctrl = (ioexp_present && (ctrl_mode == 4'd1)) ? 1'b0 : 1'b1;

// Delay counter
// Based on oscilloscope measurements, using a resistive load, it takes about 45 us
// for the follower op amp to reach Vm/2 after it is enabled. Thus, we set a nominal
// delay of 100 us.
reg[7:0] amp_enable_cnt;

// Specified delay
reg[7:0] delay_cnt;
initial delay_cnt = 8'd154;   // 154 --> 100 us

// Write to DAC register
wire dac_reg_wen;
assign dac_reg_wen = ((reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4] == CHANNEL) &&
                      (reg_waddr[3:0]==`OFF_DAC_CTRL)) ? reg_wen : 1'd0;

// PK TEMP: For now write to OFF_MOTOR_STATUS to set delay_cnt
wire motor_reg_wen;
assign motor_reg_wen = ((reg_waddr[15:12]==`ADDR_MAIN) && (reg_waddr[7:4] == CHANNEL) &&
                        (reg_waddr[3:0]==`OFF_MOTOR_STATUS)) ? reg_wen : 1'd0;

always @(posedge clk)
begin
    if (dac_reg_wen) begin
        cur_cmd <= reg_wdata[15:0];
        // Save the current control mode; note that the I/O expander must be
        // present to select anything other than current control (0).
        // This restriction could be removed if other control modes are created
        // that do not require QLA 1.5+.
        ctrl_mode <= ioexp_present ? reg_wdata[27:24] : 4'd0;
    end
    else if (motor_reg_wen) begin
        delay_cnt <= reg_wdata[7:0];
    end
end

always @(posedge delay_clk)
begin
    if (amp_disable) begin
        amp_enable_cnt <= 8'd0;
    end
    else if (amp_enable_cnt != delay_cnt) begin
        amp_enable_cnt <= amp_enable_cnt + 8'd1;
    end
end

// Only delay the enable (i.e., amp_disable == 0)
assign amp_disable_pin = (amp_enable_cnt == delay_cnt) ? amp_disable : 1'b1;

endmodule
