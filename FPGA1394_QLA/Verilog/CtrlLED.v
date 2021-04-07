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

reg[31:0] ROM_PWM[0:1023];    // pwm period lookup table

// Initialization
integer i;
initial begin
    // initialize lookup table here
    for (i=  0; i<  1; i=i+1) ROM_PWM[i] = 20; // first element
    for (i=  1; i<100; i=i+1) ROM_PWM[i] = ROM_PWM[i-1] + 20;
    for (i=100; i<200; i=i+1) ROM_PWM[i] = ROM_PWM[i-1] - 20;
    for (i=200; i<300; i=i+1) ROM_PWM[i] = 0;
    for (i=300; i<400; i=i+1) ROM_PWM[i] = 0;
    for (i=400; i<500; i=i+1) ROM_PWM[i] = ROM_PWM[i-1] + 20;
    for (i=500; i<600; i=i+1) ROM_PWM[i] = ROM_PWM[i-1] - 20;
    for (i=600; i<700; i=i+1) ROM_PWM[i] = ROM_PWM[i-1] + 20;
    for (i=700; i<800; i=i+1) ROM_PWM[i] = ROM_PWM[i-1] - 20;
    for (i=800; i<900; i=i+1) ROM_PWM[i] = 0;
    for (i=900; i<=1023; i=i+1) ROM_PWM[i] = 0;
end

// generate clocks
wire clk_768khz;  // clk 768khz
ClkDiv div768khz(sysclk, clk_768khz); defparam div768khz.width = 6;
wire clk_pwm;  // pwm signal 187.5 Hz, 4096 cnts clk_768khz
ClkDiv divpwm(sysclk, clk_pwm); defparam divpwm.width = 18;
wire clk_pwm_width;  // clk for pwm width update 93.75 Hz
ClkDiv divpw(sysclk, clk_pwm_width); defparam divpw.width = 19;

// show green 1, red 1, green 2, red 2 leds using pwm
wire led1_grn_pwm;
wire[9:0] led1_grn_period;
wire[31:0] led1_grn_pwm_value;
assign led1_grn_pwm_value = ROM_PWM[led1_grn_period];
LEDPWM led_green_pwm_1(clk_768khz, clk_pwm, clk_pwm_width, led1_grn_pwm, led1_grn_period, led1_grn_pwm_value);
defparam led_green_pwm_1.start_phase = 250;

wire led1_red_pwm;
wire[9:0] led1_red_period;
wire[31:0] led1_red_pwm_value;
assign led1_red_pwm_value = ROM_PWM[led1_red_period];
LEDPWM led_red_pwm_1(clk_768khz, clk_pwm, clk_pwm_width, led1_red_pwm, led1_red_period, led1_red_pwm_value);
defparam led_red_pwm_1.start_phase = 700;

wire led2_grn_pwm;
wire[9:0] led2_grn_period;
wire[31:0] led2_grn_pwm_value;
assign led2_grn_pwm_value = ROM_PWM[led2_grn_period];
LEDPWM led_green_pwm_2(clk_768khz, clk_pwm, clk_pwm_width, led2_grn_pwm, led2_grn_period, led2_grn_pwm_value);
defparam led_green_pwm_2.start_phase = 0;

wire led2_red_pwm;
wire[9:0] led2_red_period;
wire[31:0] led2_red_pwm_value;
assign led2_red_pwm_value = ROM_PWM[led2_red_period];
LEDPWM led_red_pwm_2(clk_768khz, clk_pwm, clk_pwm_width, led2_red_pwm, led2_red_period, led2_red_pwm_value);
defparam led_red_pwm_2.start_phase = 200;

// output to led using mux
assign led1_grn = (led_reset_mode) ? 1'b0 : led1_grn_pwm;
assign led1_red = (led_reset_mode) ? led_reset_signal : led1_red_pwm;
assign led2_grn = (led_reset_mode) ? 1'b0 : led2_grn_pwm;
assign led2_red = (led_reset_mode) ? led_reset_signal : led2_red_pwm;

endmodule
