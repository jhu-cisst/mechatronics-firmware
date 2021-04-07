 `timescale 1ns / 1ps
 
 module CtrlLed_tb;
  
  reg         clk1394;
  reg 	      clk_12hz;
  reg         reset;  

  initial begin
	// Initialize Inputs
	clk1394 = 0;
	clk_12hz = 0;
	reset = 1;
  end
    
  //generate clk
  always begin
    #1 clk1394 <= ~clk1394;     // system clock 
  end
	
  //generate clk
  always begin
    #12 clk_12hz <= ~clk_12hz;     // system clock 
  end
	
	
  CtrlLED uut(
    .sysclk(clk1394),
    .clk_12hz(clk_12hz),
    .reset(reset),
    .led1_grn(led1_grn),
    .led1_red(led1_red),
    .led2_grn(led2_grn),
    .led2_red(led2_red)
  );

  endmodule