`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   23:05:16 05/22/2013
// Design Name:   SafetyCheck
// Module Name:   /home/zihan/dev/mechatronics/FPGA1394_QLA/Simulation/SafetyCheck_tb.v
// Project Name:  FPGA1394-QLA
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: SafetyCheck
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module SafetyCheck_tb;

	// Inputs
	reg clk;
	reg reset;
	reg [15:0] cur_in;
	reg [15:0] dac_in;

	// Outputs
	wire amp_disable;

	// Instantiate the Unit Under Test (UUT)
	SafetyCheck uut (
		.clk(clk), 
		.reset(reset), 
		.cur_in(cur_in), 
		.dac_in(dac_in), 
		.amp_disable(amp_disable)
	);

	initial begin
		// Initialize Inputs
		clk = 0;
		reset = 1'b1;
		cur_in = 0;
		dac_in = 0;

   		// set global reset signal
        #100 
        reset = 1'b0;
        #100
        reset = 1'b1;
        
        // case 1
        #100
        cur_in <= 16'h8000;
        dac_in <= 16'h8000;
        
        // case 2
        #300
        cur_in <= 16'h8200;
        dac_in <= 16'hefff;
        
        // case 3: pos dac neg cur
        #300
        cur_in <= 16'h8FFF;
        dac_in <= 16'h7000;
        
        // case 4: pos dac pos cur
        #300 
        cur_in <= 16'h8FFF;
        dac_in <= 16'h8300;
                
        #300 
        cur_in <= 16'h8500;
        dac_in <= 16'h8300;
                
        #300
        $finish;

	end
    
    // sysclk generator
    always begin
        #5 clk <= ~clk;     // system clock 
    end
    
      
endmodule

