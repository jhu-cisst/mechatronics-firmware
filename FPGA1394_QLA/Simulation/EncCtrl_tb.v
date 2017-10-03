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
  reg         a;
  reg         b;
  reg         dir;
  wire [31:0] period;
  reg   [1:0] fsm;
  reg  [20:0] counter;
  wire  [9:0] cycle;
  
  // Define encoder cycle length
  assign cycle = 20;
  
  parameter INIT    = 2'h0, 
            UP      = 2'h1,
            STEADY  = 2'h2,
            DOWN    = 2'h3,
            TIME_UP = 10,
			FACTOR  = 10;
  
  initial begin
		// Initialize Inputs
		clk1394 = 0;
		a       = 0;
		b       = 0;
		dir     = 1;
		fsm     = INIT;
		counter = 0;
	end
    
	// generate clk
    always begin
        #1 clk1394 <= ~clk1394;     // system clock 
    end
	
	always begin
      case (fsm)
	    INIT: begin
		  #(cycle + TIME_UP*FACTOR) a <= ~a;		  
		end
        UP: begin  
		  #(cycle + (TIME_UP*FACTOR - counter*FACTOR)) a <= ~a;
		  if (a)
    		  #(cycle + (TIME_UP*FACTOR - counter*FACTOR) - (TIME_UP*FACTOR - counter*FACTOR)/8) a <= ~a;
	      else     		  
		      #(cycle + (TIME_UP*FACTOR - counter*FACTOR)) a <= ~a;
        end
        STEADY: begin
          #cycle a <= ~a;
		end
		DOWN: begin
		  #(cycle + counter*FACTOR) a <= ~a;
		end
      endcase		
	end
	
	always begin
		case (fsm)
		INIT: begin
		  #((cycle + TIME_UP*FACTOR)/4) b <= b;
		  #(cycle + TIME_UP*FACTOR) b <= ~b;		  
		  fsm     <= UP;
	    end
        UP: begin  
		  #(cycle + (TIME_UP*FACTOR - counter*FACTOR)) b <= ~b;
          if (counter === TIME_UP) begin
		    fsm     <= DOWN;
			counter <= 21'b0;
		  end else begin
		    counter <= counter + 1;
		  end
		end
        STEADY: begin
          #cycle b <= ~b;
		  if (counter === TIME_UP) begin
		    fsm     <= DOWN;
			counter <= 21'b0;
		  end else begin
		    counter <= counter + 1;
		  end
		end
		DOWN: begin
		  #(cycle + counter*FACTOR) b <= ~b;
			if (counter === TIME_UP) begin
			  counter <= 21'b0;
		  end else begin
		    counter <= counter + 1;
		  end
		end
      endcase		
	end
	  
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


/* Notes - first byte from simulation
11010000
01000000 -> value changes during -> seems OK cuz running counter
11000000
11011000
*/
endmodule

