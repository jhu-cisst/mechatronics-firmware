`timescale 1ns / 1ps
/*******************************************************************************
 *
 * Copyright(C) 2013-2020 ERC CISST, Johns Hopkins University.
 *
 * This module drives the QLA LEDs. Currently, it only generates a characteristic
 * flashing pattern
 *
 */

module CtrlLED(
    input wire sysclk,
    input wire clk_12hz,
    output wire led1_grn,
    output wire led1_red,
    output wire led2_grn,
    output wire led2_red
    );


// set reset_mode and generate flash led
reg led_reset_mode;
reg led_reset_signal;
reg[4:0] led_reset_mode_counter;
always @(posedge(clk_12hz))
begin
    if (led_reset_mode_counter < 5'd15) begin
        led_reset_mode_counter <= led_reset_mode_counter + 1'b1;
        led_reset_mode <= 1'b1;
        led_reset_signal <= ~led_reset_signal;
    end
    else begin
        led_reset_mode <= 1'b0;
    end
end

// show green 1, red 1, green 2, red 2 leds using pwm
wire led1_grn_pwm;
LEDPWM led_green_pwm_1(sysclk, led1_grn_pwm);
defparam led_green_pwm_1.start_phase = 250;

wire led1_red_pwm;
LEDPWM led_red_pwm_1(sysclk, led1_red_pwm);
defparam led_red_pwm_1.start_phase = 700;

wire led2_grn_pwm;
LEDPWM led_green_pwm_2(sysclk, led2_grn_pwm);
defparam led_green_pwm_2.start_phase = 0;

wire led2_red_pwm;
LEDPWM led_red_pwm_2(sysclk, led2_red_pwm);
defparam led_red_pwm_2.start_phase = 200;

// output to led using mux
assign led1_grn = (led_reset_mode) ? 1'b0 : led1_grn_pwm;
assign led1_red = (led_reset_mode) ? led_reset_signal : led1_red_pwm;
assign led2_grn = (led_reset_mode) ? 1'b0 : led2_grn_pwm;
assign led2_red = (led_reset_mode) ? led_reset_signal : led2_red_pwm;

endmodule
