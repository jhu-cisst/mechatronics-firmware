`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    21:37:11 08/21/2013 
// Design Name: 
// Module Name:    CtrlLED 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
// ***      Revision:  10/16/19   Jintan Zhang   Add watchdog period led feedback    ***
/////////////////////////////////////////////////////////////////////////////////

`include "Constants.v"

module CtrlLED(
    input wire sysclk,
    input wire clk_12hz,
    input wire reset,
    input wire[2:0] wdog_period_status,
    input wire wdog_timeout_led,
    output wire led1_grn,
    output wire led1_red,
    output wire led2_grn,
    output wire led2_red
    );


// set reset_mode and generate flash led
reg[2:0] led_mode;
reg led_2hz_signal;
reg led_1hz_signal;
reg led_500mhz_signal;
reg[4:0] led_2hz_reset_mode_counter;
reg[4:0] led_1hz_reset_mode_counter;
reg[5:0] led_500mhz_reset_mode_counter;

// 2hz LED setup
always @(negedge(reset) or posedge(clk_12hz))
begin
    if (reset == 0) begin
        led_2hz_reset_mode_counter <= 5'd0;
        led_2hz_signal <= 1'b0;
    end
    else begin
        if (led_2hz_reset_mode_counter < 5'd6) begin
            led_2hz_reset_mode_counter <= led_2hz_reset_mode_counter + 5'd1;
            led_2hz_signal <= 1'b1;
        end
        else begin
            if  (led_2hz_reset_mode_counter < 5'd12) begin
                 led_2hz_reset_mode_counter <= led_2hz_reset_mode_counter + 5'd1;  
                 led_2hz_signal <= 1'b0;
            end 
            else begin 
            led_2hz_reset_mode_counter <= 5'd0;
            end
        end
    end
end

// 1hz LED setup
always @(negedge(reset) or posedge(clk_12hz))
begin
    if (reset == 0) begin
        led_1hz_reset_mode_counter <= 5'd0;
        led_1hz_signal <= 1'b0;
    end
    else begin
        if (led_1hz_reset_mode_counter < 5'd12) begin
            led_1hz_reset_mode_counter <= led_1hz_reset_mode_counter + 5'd1;
            led_1hz_signal <= 1'b1;
        end
        else begin
            if  (led_1hz_reset_mode_counter < 5'd24) begin
                 led_1hz_reset_mode_counter <= led_1hz_reset_mode_counter + 5'd1;  
                 led_1hz_signal <= 1'b0;
            end 
            else begin 
                 led_1hz_reset_mode_counter <= 5'd0;
            end
        end
    end
end

// 500mhz LED setup
always @(negedge(reset) or posedge(clk_12hz))
begin
    if (reset == 0) begin
        led_500mhz_reset_mode_counter <= 6'd0;
        led_500mhz_signal <= 1'b0;
    end
    else begin
        if (led_500mhz_reset_mode_counter < 6'd24) begin
            led_500mhz_reset_mode_counter <= led_500mhz_reset_mode_counter + 6'd1;
            led_500mhz_signal <= 1'b1;
        end
        else begin
            if  (led_500mhz_reset_mode_counter < 6'd48) begin
                 led_500mhz_reset_mode_counter <= led_500mhz_reset_mode_counter + 6'd1;  
                 led_500mhz_signal <= 1'b0;
            end 
            else begin 
                 led_500mhz_reset_mode_counter <= 6'd0;
            end
        end
    end
end

// assign watchdog period status to led_mode  
always @(wdog_period_status or wdog_timeout_led)
begin
	if(!wdog_timeout_led) begin
       led_mode <= wdog_period_status;
	end
	else begin
	    led_mode <= `WDOG_TIMEOUT;
	end
end

// output to led using mux
assign led1_grn = (led_mode == `WDOG_PHASE_ONE) ? 1'b1 : ((led_mode == `WDOG_PHASE_TWO) ? led_2hz_signal : ((led_mode == `WDOG_PHASE_THREE) ? led_1hz_signal : ((led_mode == `WDOG_PHASE_FOUR) ? led_500mhz_signal : 1'b0)));
assign led1_red = (led_mode == `WDOG_TIMEOUT) ? 1'b1 : ((led_mode == `WDOG_DISABLE) ? led_2hz_signal : 1'b0);

endmodule


