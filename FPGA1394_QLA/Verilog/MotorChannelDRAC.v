/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2022-2023 Johns Hopkins University.
 *
 * This module handles a motor channel for the dRAC
 */

`include "Constants.v"

module MotorChannelDRAC
#(parameter CHANNEL = 1, COUNTER_WIDTH = 10)
(
    input             sysclk,
    input             pwmclk,
    // CPU interface
    input  wire[15:0] reg_raddr, 	// register read address
    input  wire[15:0] reg_waddr, 	// register write address
    input  wire[31:0] reg_wdata,  	// register write data
    output reg[31:0] reg_rdata,  	// register read data
    input  wire       reg_wen,      //  Reg write enable when High write, when Low Read
    output wire[15:0] cur_fb,
    output reg[15:0] cur_fb_filtered,
    output reg[15:0] cur_cmd_fb,

    //ADC control interface
    input  wire       adc_sck,
    input wire adc_sdo,
    input  wire       adc_cnv,
    input  wire       adc_data_ready,
    input wire feedback_calculation_start,

    // drv84x2 faults
    input otw_n,
    input fault_n,

    // safety
    input wire clear_disable,
    output reg safety_amp_disable = 0,

    // motor status block read
    input enable_pin,
    input enable_requested,
    output wire[31:0] motor_status,

    //pwm interface
    input wire [COUNTER_WIDTH:0] counter_unfolded,
    input wire pwm_cycle_start,
    output wire  pwm_p,
    output wire  pwm_n
);

reg [15:0] measured_motor_current = 'hbbbb;

reg signed [COUNTER_WIDTH:0] duty_cycle = 0;
reg signed [COUNTER_WIDTH:0] duty_cycle_sysclk;
reg [15:0] tuning_counter = 0;
reg [15:0] tuning_pulse_width = 0;
wire tuning_mode = | tuning_pulse_width;
reg tuning_req = 0;
reg tuning_ack = 0;

reg [3:0] fault_code;
assign motor_status = {2'b0, // 31:30 unused
    enable_pin, // 29 actual enable
    enable_requested, // 28 requested enable
    control_mode, // 27:24 control mode
    3'b0, // 23:21 unused
    1'b0, // 20 cur_ctrl=0 no analog current loop
    fault_code, // 19:16 fault code
    duty_cycle_sysclk, 5'b0}; // 15:0 DAC output


PWM PWM_instance
(
    .clk(pwmclk),
    .counter_unfolded(counter_unfolded),
    .pwm_cycle_start(pwm_cycle_start),
    .duty_cycle(duty_cycle),
    .pwm_p(pwm_p),
    .pwm_n(pwm_n)
);

reg [10:0] v_cmd = 'sh0;
reg [15:0] cur_cmd_normal = 16'h8000;
reg [15:0] cur_cmd_tuning = 16'h8000;
wire [15:0] cur_cmd = tuning_mode ? cur_cmd_tuning : cur_cmd_normal;

reg [17:0] kp = 2000;
reg [17:0] ki = 200;
reg [17:0] kd = 0;
reg [17:0] ff_resistive = 0;

reg [15:0] i_term_limit = 'd1000;
reg [15:0] output_limit = 'd1000;

wire [31:0] adc_out;
reg [31:0] adc_debug;
assign cur_fb = measured_motor_current;
reg pid_input_ready = 0;

wire signed [16:0] error_out;
wire [35:0] i_term_out;
wire [10:0] ap_return;
wire ap_done;
reg [3:0] control_mode = 3'h0;
reg ap_rst = 1'b1;

pi_controller pi_controller_instance (
    .ap_clk(pwmclk),
    .ap_rst(ap_rst),
    .ap_start(pid_input_ready),
    .ap_done(ap_done),
    //.ap_idle(),
    //.ap_ready(),
    .feedback_V(measured_motor_current),
    .setpoint_V(cur_cmd),
    .kp_V(kp),
    .ki_V(ki),
    .kd_V(kd),
    .ff_resistive_V(ff_resistive),
    .i_term_limit_V(i_term_limit),
    .output_limit_V(output_limit),
    .error_out_V(error_out),
    .i_term_out_V(i_term_out),
    .ap_return(ap_return)
);

AD4008 AD4008_instance
(
    .sck(adc_sck),
    .sdo(adc_sdo),
    .data_ready(adc_data_ready),
    .out(adc_out)
);

wire signed [15:0] offseted_cur_cmd = $signed({cur_cmd}) - 16'sh8000;

always @(posedge pwmclk)
begin
    pid_input_ready <= feedback_calculation_start;
    if (adc_data_ready) begin
        measured_motor_current <= adc_out[15:0];
    end
    if (~enable_pin) begin
        duty_cycle <= 11'sb0;
    end else begin
        case (control_mode)
            `MOTOR_CONTROL_MODE_VOLTAGE: duty_cycle <= v_cmd; // Truncate the smaller bits: 0xffff = full forward. 0x8000 = no output. 0x0000 = full reverse.
            `MOTOR_CONTROL_MODE_CURRENT: if (ap_done) duty_cycle <= ap_return;
            default: duty_cycle <= 11'sb0;
        endcase
    end
    if (control_mode != `MOTOR_CONTROL_MODE_CURRENT || clear_disable || ~enable_pin) begin
        ap_rst <= 1;
    end else begin
        ap_rst <= 0;
    end
end


// safety disable
wire current_regulation_fault;
reg adc_fault = 0;
wire h_bridge_overcurrent_fault = (~fault_n) & otw_n;
wire h_bridge_overtemperature_fault = (~fault_n) & (~otw_n);
wire [31:0] fault = {28'b0,
    h_bridge_overtemperature_fault,
    h_bridge_overcurrent_fault,
    current_regulation_fault & (control_mode == `MOTOR_CONTROL_MODE_CURRENT) & ~enable_pin,
    adc_fault};
reg [31:0] fault_latched = 0;
reg [31:0] fault_latched_sysclk;

// safety check - current adc is broken
always @(posedge pwmclk) begin
    if (adc_data_ready) begin
        if (adc_out[15:0] == 16'h0000 || adc_out[15:0] == 16'hffff) begin
            adc_fault <= 1;
        end else begin
            adc_fault <= 0;
        end
    end
end

// safety check - current error
localparam current_error_counter_top = 12'hfff;
reg [11:0] current_error_counter = current_error_counter_top; // 51.2 ms
assign current_regulation_fault = (current_error_counter == 12'h0);
wire [15:0] error_out_abs = error_out[16] ? -error_out : error_out;
reg current_bad = 0;
always @(posedge pwmclk) begin
    current_bad <= error_out_abs > (CHANNEL < 3 ? 16'h0200 : 16'h0800); // +- 0.128 A
    if (control_mode != `MOTOR_CONTROL_MODE_CURRENT || clear_disable || ~enable_pin) begin
        current_error_counter <= current_error_counter_top;
    end else if (ap_done) begin
        case (current_error_counter)
        0: current_error_counter <= current_bad ? 0 : 1'b1;
        current_error_counter_top: current_error_counter <= current_bad ? current_error_counter_top - 1 : current_error_counter_top;
        default: current_error_counter <= current_bad ? current_error_counter - 1 : current_error_counter + 1;
        endcase
    end
end

always @(posedge pwmclk)
begin
    safety_amp_disable <= | fault_latched;
    if (clear_disable) begin
        fault_latched <= 0;
    end else begin
        fault_latched <= fault_latched | fault;
    end
end



always @(posedge pwmclk) begin
    if (feedback_calculation_start) begin
        if (tuning_req && !tuning_ack) begin
            tuning_ack <= 1;
            tuning_counter <= tuning_pulse_width;
            cur_cmd_tuning <= cur_cmd_normal;
        end else begin
            if (tuning_counter != 0) begin
                tuning_counter <= tuning_counter - 1;
            end else begin
            cur_cmd_tuning <= 16'h8000;
            if (!tuning_req) tuning_ack <= 0;
            end
        end
    end
end

// pc interface
always @(posedge sysclk)
begin
    duty_cycle_sysclk <= duty_cycle;
    fault_latched_sysclk <= fault_latched;
    fault_code <=
        fault_latched[0] ? 1 :
        fault_latched[1] ? 2 :
        fault_latched[2] ? 3 : 0;
    cur_cmd_fb <= cur_cmd;
    if (~enable_pin) begin
        cur_cmd_normal <= 'h8000;
    end
    if (reg_raddr[7:4]== CHANNEL) begin
        case (reg_raddr[3:0])
            `OFF_MOTOR_CONTROL_MODE: reg_rdata <= {12'b0, control_mode};
            `OFF_MOTOR_CONTROL_CURRENT_KP: reg_rdata <= kp;
            `OFF_MOTOR_CONTROL_CURRENT_KI: reg_rdata <= ki;
            `OFF_MOTOR_CONTROL_CURRENT_KD: reg_rdata <= kd;
            `OFF_MOTOR_CONTROL_CURRENT_FF_RESISTIVE: reg_rdata <= ff_resistive;
            `OFF_MOTOR_CONTROL_CURRENT_I_TERM_LIMIT: reg_rdata <= i_term_limit;
            `OFF_MOTOR_CONTROL_CURRENT_OUTPUT_LIMIT: reg_rdata <= output_limit;
            `OFF_MOTOR_CONTROL_DUTY_CYCLE: reg_rdata <= duty_cycle_sysclk;
            `OFF_MOTOR_CONTROL_FAULT: reg_rdata <= fault_latched_sysclk;
            `OFF_MOTOR_CONTROL_TUNE: reg_rdata <= {16'b0, tuning_pulse_width};
            default: reg_rdata <= 32'hcccccccc;
        endcase
    end
    else begin
        reg_rdata <= 32'b0;
    end

    if (reg_waddr[15:12]==`ADDR_MOTOR_CONTROL && reg_waddr[7:4]== CHANNEL && reg_wen) begin
        case (reg_waddr[3:0])
            `OFF_MOTOR_CONTROL_CURRENT_KP: kp <= reg_wdata[17:0];
            `OFF_MOTOR_CONTROL_CURRENT_KI: ki <= reg_wdata[17:0];
            `OFF_MOTOR_CONTROL_CURRENT_KD: kd <= reg_wdata[17:0];
            `OFF_MOTOR_CONTROL_CURRENT_FF_RESISTIVE: ff_resistive <= reg_wdata[17:0];
            `OFF_MOTOR_CONTROL_CURRENT_I_TERM_LIMIT: i_term_limit <= reg_wdata[15:0];
            `OFF_MOTOR_CONTROL_CURRENT_OUTPUT_LIMIT: output_limit <= reg_wdata[15:0];
            `OFF_MOTOR_CONTROL_TUNE: begin
                tuning_pulse_width <= reg_wdata[15:0];
            end
        endcase
    end

    if (tuning_mode && reg_waddr[15:12]==`ADDR_MAIN && reg_waddr[7:4]== CHANNEL && reg_waddr[3:0] == `OFF_DAC_CTRL && reg_wen && !tuning_ack) begin
        tuning_req <= 1;
    end else if (tuning_ack) begin
        tuning_req <= 0;
    end

    if (reg_waddr[15:12]==`ADDR_MAIN && reg_waddr[7:4]== CHANNEL && reg_waddr[3:0] == `OFF_DAC_CTRL && reg_wen) begin
        if (reg_wdata[31]) begin
            case (reg_wdata[27:24])
                'h0: cur_cmd_normal <= reg_wdata[15:0];
                'h1: v_cmd <= reg_wdata[23:13];
            endcase
            control_mode <= reg_wdata[27:24];
        end
    end
end

// Decimate the current reading by averaging. To be replaced with a proper filter.

reg [5:0] decimate_counter = 0;
reg [21:0] decimate_sum;
reg adc_data_latched;
reg[15:0] cur_fb_filtered_pwmclk;

always @ (posedge pwmclk) begin
    adc_data_latched <= adc_data_ready;
    if (adc_data_latched) begin
        decimate_counter <= decimate_counter + 1;
        if (decimate_counter == 0) begin
            decimate_sum <= measured_motor_current;
        end
        else if (decimate_counter == 63) begin
            cur_fb_filtered_pwmclk <= (decimate_sum + measured_motor_current) >> 6;
        end
        else begin
            decimate_sum <= decimate_sum + measured_motor_current;
        end
    end
end

always @ (posedge sysclk) begin
    cur_fb_filtered <= cur_fb_filtered_pwmclk;
end

endmodule
