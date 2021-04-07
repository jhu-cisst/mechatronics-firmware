`timescale 1ns / 1ps
/*******************************************************************************
 *
 * Copyright(C) 2013-2020 ERC CISST, Johns Hopkins University.
 *
 * This module sets the blink pattern for the QLA LEDs.
 *
 * Revision history
 *     08/20/13    Zihan Chen    Initial revision
 */

module LEDPWM(
    input wire clk_768khz,
    input wire clk_pwm,
    input wire clk_pwm_width,
    output reg led_drive,
    output reg[9:0] period,      // for cycling through lookup table
    input wire[31:0] pwm_value   // PWM value from lookup table
    );

// define parameter
parameter start_phase = 0;   // pwm param, 0 to 1023 
// initialize period to start_phase
initial period = start_phase;

// variable
reg[31:0] pulse_width;  // current pwm width
reg[31:0] count_width;  // pulse width counter

// Update led_drive based on pwm width
always @(posedge(clk_768khz) or posedge(clk_pwm))
begin
    if (clk_pwm)
        count_width <= 0;
    else begin
        count_width <= count_width + 1'b1;
        led_drive <= (count_width < pulse_width);
    end
end

// update pwm width at 93.75 Hz
always @(posedge(clk_pwm_width))
begin
    period <= period + 10'd1;  // 0-1023
    pulse_width <= pwm_value;  // pwm_value = ROM_PWM[period]
end

endmodule
