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
#(parameter[3:0] CHANNEL = 4'd1)
(
    input wire clk,                  // system clock (49.152 MHz)
    input wire delay_clk,            // clock to use for delay (0.192 MHz)

    input  wire[15:0] reg_waddr,     // write address
    input  wire[31:0] reg_wdata,     // register write data
    input  wire reg_wen,             // reg write enable
    output wire[31:0] motor_status,  // motor status feedback
    output reg[31:0] motor_config,   // motor configuration register

    input wire ioexp_present,        // whether I/O expander present

    output wire safety_amp_disable,  // from SafetyCheck module
    input wire amp_fault,            // amplifier fault feedback
    input wire cur_ctrl_error,       // 1 -> error in cur_ctrl output
    input wire disable_f_error,      // 1 -> error in disable_f output
    input wire amp_disable,          // from BoardRegs (set by host PC)
    output wire amp_disable_pin,     // signal to drive FPGA pin
    output wire force_disable_f,     // 1 -> force disable_f to 0 (follower amp enabled)

    output reg[15:0] cur_cmd,        // Commanded current (or voltage)
    output reg[3:0] ctrl_mode,       // Control mode
    output wire cur_ctrl,            // 1 -> current control, 0 -> voltage control

    input wire[15:0] cur_fb,         // Measured current
    input wire clr_safety_disable    // 1 -> clear disable due to safety check
);

// Motor configuration register
//    17:   disable_safety
//    16:   force_disable_f
//   7-0:   delay
initial motor_config = 32'd20;   // 20 --> 104.2 us delay

assign force_disable_f = motor_config[16];

wire disable_safety;             // 1 -> disable motor current safety check
assign disable_safety = motor_config[17];

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
// Based on oscilloscope measurements, using a resistive load, it takes about 45 us
// for the follower op amp to reach Vm/2 after it is enabled. Thus, we set a nominal
// delay of 100 us.
reg[7:0] amp_enable_cnt;

// Specified delay, resolution is 5.21 us
// With 8 bits, maximum possible delay is 1.3 ms
wire[7:0] delay_cnt;
assign delay_cnt = motor_config[7:0];

// Write to DAC register
wire dac_reg_wen;
assign dac_reg_wen = (reg_waddr[15:0] == {`ADDR_MAIN, 4'd0, CHANNEL, `OFF_DAC_CTRL}) ? reg_wen : 1'd0;

// Write to motor configuration register
wire motor_reg_wen;
assign motor_reg_wen = (reg_waddr[15:0] == {`ADDR_MAIN, 4'd0, CHANNEL, `OFF_MOTOR_CONFIG}) ? reg_wen : 1'd0;

assign motor_status = { 3'b000, ~amp_disable, ctrl_mode, 3'd0, cur_ctrl,
                        cur_ctrl_error, disable_f_error, safety_amp_disable, amp_fault_fb,
                        cur_cmd};

// Flag to indicate whether I/O expander needs a one-time fix
reg[11:0] ioexp_cfg_hack;

always @(posedge clk)
begin
    if (dac_reg_wen) begin
        cur_cmd <= reg_wdata[15:0];
        // Save the current control mode; note that the I/O expander must be
        // present to select anything other than current control (0).
        // This restriction could be removed if other control modes are created
        // that do not require QLA 1.5+.
        if ((ioexp_cfg_hack != 12'hfff) && (cur_ctrl_error || (ioexp_cfg_hack != 12'd0))
            && (reg_wdata[27:24] == 4'd0)) begin
            // Temporary fix for startup problem. If cur_ctrl_error, temporarily
            // switch to voltage control.
            ioexp_cfg_hack <= ioexp_cfg_hack + 12'd1;
            ctrl_mode <= 4'd1;
        end
        else begin
            ctrl_mode <= ioexp_present ? reg_wdata[27:24] : 4'd0;
        end
    end
    else if (motor_reg_wen) begin
        motor_config <= reg_wdata;
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
    .enable_check((~disable_safety) & cur_ctrl),
    .clear_disable(clr_safety_disable),
    .amp_disable(safety_amp_disable)
);

endmodule
