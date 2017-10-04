/*******************************************************************************    
 *
 * Copyright(C) 2017 ERC CISST, Johns Hopkins University.
 *
 * Module:  FPGA1394_QLA_tb
 *
 * Purpose: This is a generic starting point to build a testbench for the 
 *          top level module for the FPGA1394-QLA motor controller interface. 
 *          It creates the clocks and the other signals should be changed as
 *          needed.  
 *
 * Revision history
 *     06/27/2017    Jie Ying Wu        Initial commit
 */

 `timescale 1ns / 1ps

 module EncCtrl_tb;
  
  reg         clk1394;
  wire	      clk_fast;
  reg         clk_encoder;
  wire  [8:0] x;
  integer     i;
  reg   [8:0] speed [0:9];
  wire        a;
  wire        b;
  reg         dir;
  wire [31:0] period;
  
  // Define encoder cycle length
  assign cycle = 20;
  
  initial begin
		// Initialize Inputs
		clk_encoder = 0;
		i       = 0;
		clk1394 = 0;
		dir     = 0;
	    speed[0] = 250;
        speed[1] = 200;
        speed[2] = 150;
        speed[3] = 100;
        speed[4] = 50;
        speed[5] = 100;
        speed[6] = 150;
        speed[7] = 200;
        speed[8] = 250;
        speed[9] = 300;
	end
    
	// generate clk
    always begin
        #1 clk1394 <= ~clk1394;     // system clock 
    end
	
	always begin
        #x clk_encoder <= ~clk_encoder;     // system clock 
    end

	always begin
		#50000 i <= (i == 9) ? 0 : i + 1;
	end
	
    assign x = speed[i];
	
	sine_wave_gen uut (
        .Clk(clk_encoder), 
        .a(a),
		.b(b)
	);
	
ClkDiv divenc1(clk1394, clk_fast); defparam divenc1.width = 1;   // 49.152 MHz / 2**4 ==> 3.072 MHz
	  
EncPeriodQuad VelEstimate(
    .clk(clk1394),       // sysclk
    .clk_fast(clk_fast), // count this clock between encoder ticks
    .reset(1),           // global reset signal
    .a(a),               // quad encoder line a
    .b(b),               // quad encoder line b
    .dir(dir),           // dir from EncQuad
    .period(period)      // num of fast clock ticks
);

endmodule


module sine_wave_gen(Clk,a,b);
//declare input and output
    input Clk;
    output a;
	output b;
//declare the sine ROM - 30 registers each 8 bit wide.  
    reg [7:0] sine [0:29];
//Internal signals  
    integer i;  
	integer j;
	
//Initialize the sine rom with samples. 
    initial begin
        i = 0;
		j = 8;
        sine[0] = 1;
        sine[1] = 1;
        sine[2] = 1;
        sine[3] = 1;
        sine[4] = 1;
        sine[5] = 1;
        sine[6] = 1;
        sine[7] = 1;
        sine[8] = 1;
        sine[9] = 1;
        sine[10] = 1;
        sine[11] = 1;
        sine[12] = 1;
        sine[13] = 1;
        sine[14] = 1;
        sine[15] = 0;
        sine[16] = 0;
        sine[17] = 0;
        sine[18] = 0;
        sine[19] = 0;
        sine[20] = 0;
        sine[21] = 0;
        sine[22] = 0;
        sine[23] = 0;
        sine[24] = 0;
        sine[25] = 0;
        sine[26] = 0;
        sine[27] = 0;
        sine[28] = 0;
        sine[29] = 0;
    end
    
    assign a = (sine[i]);
    assign b = (sine[j]);
	
    //At every positive edge of the clock, output a sine wave sample.
    always@ (posedge(Clk))
    begin
		i <= i+ 1;
        if(i == 29)
            i <= 0;
		j <= j+ 1;
        if(j == 29)
            j <= 0;
    end
endmodule