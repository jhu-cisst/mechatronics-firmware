`timescale 1ns / 1ps
/*******************************************************************************
 *
 * Copyright(C) 2013-2021 ERC CISST, Johns Hopkins University.
 *
 * This module drives the QLA LEDs. By default, it generates a characteristic
 * flashing pattern. If wdog_period_led is set (when writing wdog_period),
 * LED1 output indicates the watchdog status.
 *
 * Revision history
 *    08/21/13                         Initial revision
 *    10/16/19   Jintan Zhang          Add watchdog period led feedback 
 *    04/14/21   Peter Kazanzides      Added wdog_period_led to switch display modes
*/

`include "Constants.v"

module CtrlLED(
    input wire sysclk,
    input wire clk_12hz,
    input wire wdog_period_led,
    input wire[2:0] wdog_period_status,
    input wire  wdog_timeout,
    output wire led1_grn,
    output wire led1_red,
    output wire led2_grn,
    output wire led2_red
    );


//**************** Generate LED flash to indicate initialization *****************
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

//********************** Generate PWM signals for LEDs ****************************
// This is the default LED pattern that was originally created to indicate that the
// boards are functioning. If wdog_period_led is set, the LEDs will instead indicate
// watchdog period status.

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

//*************** Generate signals to flash LEDs (used for wdog_period display) ********************

//  Set up signals to flash LEDs
reg[2:0] led_blink_counter;    // Counts from 0-5 to divide clk_12hz by 6
reg[2:0] led_signals;          // Counts from 0-7, incremented at clk_12hz/6
wire led_2hz_signal;           // 1.0 Hz flashing, since output toggled at 2 Hz
wire led_1hz_signal;           // 0.5 Hz flashing, since output toggled at 1 Hz
wire led_500mhz_signal;        // 0.25 Hz flashing, since output toggled at 0.5 Hz

assign led_2hz_signal = led_signals[0];
assign led_1hz_signal = led_signals[1];
assign led_500mhz_signal = led_signals[2];

always @(posedge(clk_12hz))
begin
    if (led_blink_counter == 3'd5) begin
       led_signals <= led_signals + 3'd1;
       led_blink_counter <= 3'd0;
    end
    else begin
       led_blink_counter <= led_blink_counter + 3'd1;
    end
end

wire[2:0] led_mode;
assign led_mode = wdog_timeout ? `WDOG_TIMEOUT : wdog_period_status;

// Output to led using mux
// Behavior:
//   Watchdog timeout:  Red LED on, Green LED off (overrides watchdog period display)
//
//   Watchdog period, p
//        p == 0x0000 (0.00 ms)           WDOG_DISABLE     Red LED flashing at 1.0 Hz, Green LED off
//        0x0000 < p <= 0x2580 (0.05 ms)  WDOG_PHASE_ONE   Green LED on, Red LED off
//        0x2580 < p <= 0x4B00 (0.10 ms)  WDOG_PHASE_TWO   Green LED flashing at 1.0 Hz,  Red LED off
//        0x4B00 < p <= 0x7080 (0.15 ms)  WDOG_PHASE_THREE Green LED flashing at 0.5 Hz,  Red LED off
//        0x7080 < p <= 0x9600 (0.20 ms)  WDOG_PHASE_FOUR  Green LED flashing at 0.25 Hz, Red LED off
//        p > 0x9600                      WDOG_PHASE_FIVE  Green LED off, Red LED off

wire   wdog_led1_grn;
assign wdog_led1_grn = (led_mode == `WDOG_PHASE_ONE) ? 1'b1 :
                       ((led_mode == `WDOG_PHASE_TWO) ? led_2hz_signal :
                       ((led_mode == `WDOG_PHASE_THREE) ? led_1hz_signal :
                       ((led_mode == `WDOG_PHASE_FOUR) ? led_500mhz_signal : 1'b0)));

wire   wdog_led1_red;
assign wdog_led1_red = (led_mode == `WDOG_TIMEOUT) ? 1'b1 :
                       ((led_mode == `WDOG_DISABLE) ? led_2hz_signal : 1'b0);

//****************************** Mux to drive LEDs **************************************
// Priority order:
//     1) Reset flash (always occurs when boards initialize)
//     2) Watchdog period display, if wdog_period_led active (LED1 only)
//     3) PWM display

assign led1_grn = (led_reset_mode) ? 1'b0 :
                  (wdog_period_led) ? wdog_led1_grn : led1_grn_pwm;
assign led1_red = (led_reset_mode) ? led_reset_signal :
                  (wdog_period_led) ? wdog_led1_red : led1_red_pwm;

assign led2_grn = (led_reset_mode) ? 1'b0 : led2_grn_pwm;
assign led2_red = (led_reset_mode) ? led_reset_signal : led2_red_pwm;

endmodule
