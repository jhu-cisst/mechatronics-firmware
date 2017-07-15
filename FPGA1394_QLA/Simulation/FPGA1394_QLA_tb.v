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

 module FPGA1394_QLA_tb;
  
  reg            clk1394;
  wire [7:0]     data;
  wire [1:0]     ctl;
  
  reg            clk29m;
  reg            clk40m;
  
  wire [1:32]    IO1;
  wire [1:38]    IO2;
  
  initial begin
		// Initialize Inputs
		clk1394 = 0;
		clk40m = 0;
		clk29m = 0;
	end
    
	// generate clk 
    always begin
        #20 clk1394 <= ~clk1394;     // system clock 
    end
	
	always begin
        #25 clk40m <= ~clk40m;     // system clock 
    end
	
	always begin
        #35 clk29m <= ~clk29m;     // system clock 
    end
	  
  FPGA1394QLA dvrk(
  .clk1394(clk1394),
  .data(data[7:0]),
  .ctl(ctl[1:0]),
  .lreq(),
  .reset_phy(),
  .RxD(1'b0),
  .RTS(1'b0),
  .TxD(),
  .clk29m(clk29m),
  .clk40m(clk40m),
  .wenid(1'b0),
  .IO1(IO1[1:32]),
  .IO2(IO2[1:38]),
  .LED(),
  .XCCLK(),    
  .XMISO(1'b0),
  .XMOSI(),
  .XCSn()
  );

endmodule

