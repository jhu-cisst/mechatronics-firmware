`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Johns Hopkins University 
// Engineer: Zihan Chen 
// 
// Create Date:    11:43:48 08/20/2013 
// Design Name: 
// Module Name:    LEDPWM
// Project Name: FPGA1394-QLA
// Target Devices: 
// Tool versions: 13.4
// Description: 
//
// Dependencies: ClkDiv
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module LEDPWM(
    input wire sysclk,
    input wire reset,
    output reg led_drive
    );

// define parameter
parameter start_phase = 0;   // pwm param, 0 to 1023 

// generate clock
wire clk_768khz;  // clk 768khz
ClkDiv divenc1(sysclk, clk_768khz); defparam divenc1.width = 6;
wire clk_pwm;  // pwm signal 187.5 Hz, 4096 cnts clk_768khz
ClkDiv divpwm(sysclk, clk_pwm); defparam divpwm.width = 18;
wire clk_pwm_width;  // clk for pwm width update 93.75 Hz
ClkDiv divpw(sysclk, clk_pulsewidth); defparam divpw.width = 19;

// variable
reg[31:0] ROM_PWM[0:1023];    // pwm period lookup table
reg[31:0] period,i;    // for cycling through lookup table
reg[31:0] pulse_width;   // current pwm width 
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
    period <= (period+1) % 1023;
    pulse_width <= ROM_PWM[period];
end


// Initialization
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
    for (i=900; i<1023; i=i+1) ROM_PWM[i] = 0;

    // initialize period to start_phase
    period = start_phase;
end

endmodule
