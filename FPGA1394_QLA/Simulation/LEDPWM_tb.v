`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   13:48:04 08/21/2013
// Design Name:   LEDPWM
// Module Name:   /home/zihan/dev/mechatronics/firmware/FPGA1394_QLA/LEDPWM_tb.v
// Project Name:  FPGA1394-QLA
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: LEDPWM
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module LEDPWM_tb;

	// Inputs
	reg sysclk;
	reg reset;

	// Outputs
	wire led_drive;

	// Instantiate the Unit Under Test (UUT)
	LEDPWM uut (
		.sysclk(sysclk), 
		.reset(reset), 
		.led_drive(led_drive)
	);
    defparam uut.start_phase = 200;

	initial begin
		// Initialize Inputs
		sysclk = 0;
        reset = 1'b1;

		// Wait 100 ns for global reset to finish
        #100 
        reset = 1'b0;
        #100
        reset = 1'b1;
        
		// Add stimulus here
        #20000
        $finish;
	end
    
    // generate clk 
    always begin
        #5 sysclk <= ~sysclk;     // system clock 
    end
      
endmodule

