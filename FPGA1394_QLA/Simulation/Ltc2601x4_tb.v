`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   01:55:43 08/21/2013
// Design Name:   LTC2601x4
// Module Name:   /home/zihan/dev/mechatronics/firmware/FPGA1394_QLA/Simulation/Ltc2601x4_tb.v
// Project Name:  FPGA1394-QLA
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: LTC2601x4
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module Ltc2601x4_tb;

	// Inputs
	reg clkin;
	reg reset;
	reg trig;
	reg [31:0] word;

	// Outputs
	wire [3:0] addr;
	wire sclk;
	wire csel;
	wire mosi;
	wire busy;
	wire flush;

	// Instantiate the Unit Under Test (UUT)
	LTC2601x4 uut (
		.clkin(clkin), 
		.reset(reset), 
		.trig(trig), 
		.word(word), 
		.addr(addr), 
		.sclk(sclk), 
		.csel(csel), 
		.mosi(mosi), 
		.busy(busy), 
		.flush(flush)
	);

	initial begin
		// Initialize Inputs
		clkin = 0;
		reset = 1'b1;
		trig = 0;
		word = 0;

        // set global reset signal
        #100 
        reset = 1'b0;
        #100
        reset = 1'b1;
        
		// Add stimulus here
        #100
        word <= 32'h00f08000;
        trig <= 1'b1;
        
        #500
        trig <= 1'b0;
        
        #5000
        $finish;
	end
    
    // generate clk 
    always begin
        #5 clkin <= ~clkin;     // system clock 
    end
      
endmodule

