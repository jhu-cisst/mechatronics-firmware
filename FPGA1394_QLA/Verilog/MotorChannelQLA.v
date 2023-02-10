/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2022-2023 Johns Hopkins University.
 *
 * This module handles a motor channel for the QLA
 *
 * Revision history
 *     08/15/22                        Initial version
 */

module MotorChannelQLA
#(parameter[3:0] CHANNEL = 4'd1,
  parameter USE_STATUS_REG = 0)
(
    input wire clk,                  // system clock (49.152 MHz)
    input wire delay_clk,            // clock to use for delay (48 kHz)

    input  wire[15:0] reg_waddr,     // write address
    input  wire[31:0] reg_wdata,     // register write data
    input  wire reg_wen,             // reg write enable
    output wire[31:0] motor_status,  // motor status feedback
    output wire[31:0] motor_config,  // motor configuration register

    input wire ioexp_present,        // whether I/O expander present

    input wire pwr_enable,           // power enable requested state
    input wire pwr_enable_cmd,       // 1 -> host attempting to enable board power
    output wire amp_enable_cmd,      // 1 -> host attempting enable amplifier power
    input wire mv_amp_disable,       // disable amp for short time after mv_good
    input wire wdog_timeout,         // 1 -> watchdog timeout
    input wire amp_fault,            // amplifier fault feedback
    input wire amp_disable_error,    // 1 -> error in amp_disable output (DQLA only)
    input wire cur_ctrl_error,       // 1 -> error in cur_ctrl output
    input wire disable_f_error,      // 1 -> error in disable_f output
    output wire amp_disable_pin,     // signal to drive FPGA pin
    output wire amp_disable_f,       // disable follower op amp (QLA Rev 1.5+)

    output reg[15:0] cur_cmd,        // Commanded current (or voltage)
    output reg[3:0] ctrl_mode,       // Control mode
    output wire cur_ctrl,            // 1 -> current control, 0 -> voltage control

    input wire[15:0] cur_fb          // Measured current
);

initial cur_cmd = 16'h8000;

// Specified delay, resolution is 20.83 us
// With 8 bits, maximum possible delay is 5.3 ms
// Based on oscilloscope measurements, using a resistive load, it takes about 45 us
// for the follower op amp to reach Vm/2 after it is enabled. However, testing on a
// dVRK MTM indicates that the delay must be greater than 1 ms to avoid jerks when
// powering up the motors.
reg[7:0] delay_cnt;
initial delay_cnt = 8'd120;  // 120 --> 2.5 ms delay

// Motor current limit
reg[15:0] cur_lim;
initial cur_lim = 16'h8418;  // 200mA

reg force_disable_f;

// Following disables motor safety check, which checks that measured current is
// consistent with commanded current. It does not disable the motor current limit,
// which (at present) is only active when the QLA is in voltage control mode (QLA 1.5+).
reg disable_safety;

// Motor configuration register (some bits are read-only)
//    31:   disable_safety
//    30:   force_disable_f
// 29-26:   0 (R/O)
//    25:   1 -> voltage control available (R/O)
//    24:   1 -> (analog) current control available (R/O)
// 23-16:   delay (20.83 us resolution)
//  15-0:   motor current limit

assign motor_config = { disable_safety, force_disable_f, 4'd0, ioexp_present, 1'b1,
                        delay_cnt, cur_lim };

// Current or voltage control
//   (ctrl_mode == 0) --> current control, set cur_ctrl = 1
//   (ctrl_mode == 1) --> voltage control, set cur_ctrl = 0
// For any other value of ctrl_mode, assume current control.
// Also, can only have voltage control if ioexp_present (QLA 1.5+).
assign cur_ctrl = (ioexp_present && (ctrl_mode == 4'd1)) ? 1'b0 : 1'b1;

// If we are attempting to enable power (amp_disable == 0) and an amplifier fault
// has occurred (amp_fault == 0)
wire amp_fault_fb;
assign amp_fault_fb = ~(amp_disable|amp_fault);

// Delay counter
reg[7:0] amp_enable_cnt;

// Amp enable from bits [29:28] written to DAC.
// For the QLA, this can also be written via the status register (USE_STATUS_REG parameter);
// this may be eliminated in the future.
// For historical reasons, it is more convenient to invert the signal to become reg_disable.
reg reg_disable;
initial reg_disable = 1'b1;

wire safety_amp_disable;   // from SafetyCheck module

// Safety-related disable (updates reg_disable)
assign safety_disable = wdog_timeout | safety_amp_disable;

wire amp_disable;
assign amp_disable = reg_disable|mv_amp_disable;

// Signal to disable follower op amp (QLA Rev 1.5+)
//    (if force_disable_f, then output is 0)
assign amp_disable_f = (~force_disable_f)&amp_disable;

wire clr_safety_disable;
assign clr_safety_disable = pwr_enable_cmd | amp_enable_cmd;

// Write to board register (for QLA backward compability)
wire status_reg_wen;

// Write to DAC register
wire dac_reg_wen;
assign dac_reg_wen = (reg_waddr[15:0] == {`ADDR_MAIN, 4'd0, CHANNEL, `OFF_DAC_CTRL}) ? reg_wen : 1'd0;

// Write to motor configuration register
wire motor_reg_wen;
assign motor_reg_wen = (reg_waddr[15:0] == {`ADDR_MAIN, 4'd0, CHANNEL, `OFF_MOTOR_CONFIG}) ? reg_wen : 1'd0;

generate
if (USE_STATUS_REG) begin
    assign status_reg_wen = (reg_waddr[15:0] == {`ADDR_MAIN, 8'd0, `REG_STATUS}) ? reg_wen : 1'd0;
    assign amp_enable_cmd = status_reg_wen ? (reg_wdata[CHANNEL+7]&reg_wdata[CHANNEL-1]) :
                            dac_reg_wen ? (reg_wdata[29]&reg_wdata[28]) : 1'b0;
end
else begin
    assign status_reg_wen = 1'b0;
    assign amp_enable_cmd = dac_reg_wen ? (reg_wdata[29]&reg_wdata[28]) : 1'b0;
end
endgenerate

// Motor Status
//
//      31   0
//      30   amp_disable_error (1 -> error with amp_disable output, DQLA only)
//      29   amp_fault (active low, 1 -> amplifier on)
//      28   ~reg_disable
//   27:24   ctrl_mode
//   23:21   000
//      20   cur_ctrl (1-> current control)
//      19   cur_ctrl_error (I/O expander error)
//      18   disable_f_error (I/O expander error)
//      17   safety_amp_disable
//      16   amp_fault_fb
//    15:0   cur_cmd (last setpoint)
//
// NOTE: if bit assignments changed, check if QLA.v needs to be updated
assign motor_status = { 1'b0, amp_disable_error, amp_fault, ~reg_disable, ctrl_mode, 3'd0, cur_ctrl,
                        cur_ctrl_error, disable_f_error, safety_amp_disable, amp_fault_fb,
                        cur_cmd};

// Valid control modes:
//    0: current control (always)
//    1: voltage control (if ioexp_present)
wire valid_ctrl_mode;
assign valid_ctrl_mode = (reg_wdata[27:24] == 4'd0) ||
                         (ioexp_present && (reg_wdata[27:24] == 4'd1));

always @(posedge clk)
begin
    if (dac_reg_wen) begin
        // If the valid bit (reg_wdata[31]) is set AND the specified control mode
        // (reg_wdata[27:24]) is valid, save the commanded value (reg_wdata[15:0])
        // and control mode.
        if (reg_wdata[31] && valid_ctrl_mode) begin
            cur_cmd <= reg_wdata[15:0];
            ctrl_mode <= reg_wdata[27:24];
        end
        reg_disable <= (~pwr_enable) | safety_disable | (reg_wdata[29] ? ~reg_wdata[28] : reg_disable);
    end
    else if (motor_reg_wen) begin
        disable_safety <= reg_wdata[31];
        force_disable_f <= reg_wdata[30];
        delay_cnt <= reg_wdata[23:16];
        cur_lim <= reg_wdata[15:0];
    end
    else if (status_reg_wen) begin
        reg_disable <= (~pwr_enable) | safety_disable | (reg_wdata[CHANNEL+7] ? ~reg_wdata[CHANNEL-1] : reg_disable);
    end
    else begin
        reg_disable <= reg_disable | safety_disable;
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
assign amp_disable_pin = ((amp_enable_cnt == delay_cnt) || !ioexp_present) ? amp_disable : 1'b1;

SafetyCheck safe(
    .clk(clk),
    .cur_in(cur_fb),
    .dac_in(cur_cmd),
    .cur_lim(cur_lim),
    .enable_check((~disable_safety) & cur_ctrl),
    .enable_limit(~cur_ctrl),             // Check current limit in voltage mode
    .clear_disable(clr_safety_disable),
    .amp_disable(safety_amp_disable)
);

endmodule
