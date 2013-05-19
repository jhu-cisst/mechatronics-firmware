`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   23:04:10 05/18/2013
// Design Name:   BoardRegs
// Module Name:   /home/zihan/dev/mechatronics/FPGA1394_QLA/BoardRegs_tb.v
// Project Name:  FPGA1394-QLA
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: BoardRegs
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module BoardRegs_tb;

	// Inputs
	reg sysclk;
	reg clkaux;
	reg [4:1] neg_limit;
	reg [4:1] pos_limit;
	reg [4:1] home;
	reg [4:1] fault;
	reg relay;
	reg mv_good;
	reg v_fault;
	reg [3:0] board_id;
	reg [15:0] temp_sense;
	reg [7:0] reg_addr;
	reg [31:0] reg_wdata;
	reg wr_en;
	reg [31:0] prom_status;
	reg [31:0] prom_result;
	reg [4:1] safety_amp_disable;
	reg [15:0] cur1;
	reg [15:0] dac1;

	// Outputs
	wire reset;
	wire [4:1] amp_disable;
	wire [4:1] dout;
	wire pwr_enable;
	wire relay_on;
	wire [31:0] reg_rdata;

	// Instantiate the Unit Under Test (UUT)
	BoardRegs uut (
		.sysclk(sysclk), 
		.clkaux(clkaux), 
		.reset(reset), 
		.amp_disable(amp_disable), 
		.dout(dout), 
		.pwr_enable(pwr_enable), 
		.relay_on(relay_on), 
		.neg_limit(neg_limit), 
		.pos_limit(pos_limit), 
		.home(home), 
		.fault(fault), 
		.relay(relay), 
		.mv_good(mv_good), 
		.v_fault(v_fault), 
		.board_id(board_id), 
		.temp_sense(temp_sense), 
		.reg_addr(reg_addr), 
		.reg_rdata(reg_rdata), 
		.reg_wdata(reg_wdata), 
		.wr_en(wr_en), 
		.prom_status(prom_status), 
		.prom_result(prom_result), 
		.safety_amp_disable(safety_amp_disable), 
		.cur1(cur1), 
		.dac1(dac1)
	);

	initial begin
		// Initialize Inputs
		sysclk = 0;
		clkaux = 0;
		neg_limit = 0;
		pos_limit = 0;
		home = 0;
		fault = 0;
		relay = 0;
		mv_good = 0;
		v_fault = 0;
		board_id = 0;
		temp_sense = 0;
		reg_addr = 0;
		reg_wdata = 0;
		wr_en = 0;
		prom_status = 0;
		prom_result = 0;
		safety_amp_disable = 0;
		cur1 = 0;
		dac1 = 0;

		// Wait 500 ns for global reset to finish
        // #5 * 2 * 49 = 490 
		#550;
        
		// Add stimulus here
        
        // pull mv_good to HIGH
        mv_good = 1'b1;
        // wait 1000 ns 
        #100000;
        // pull mv_good to LOW
        mv_good = 1'b0;
        
        
        
        
	end
    
 
    // sysclk generator
    always begin
        #5 sysclk <= ~sysclk;     // system clock 
        clkaux <= ~clkaux;    // clkaux: 
    end
    
    
      
endmodule

