`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    19:03:22 07/17/2014 
// Design Name: 
// Module Name:    EthernetTest 
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
//
//////////////////////////////////////////////////////////////////////////////////
module EthernetTest(
	input wire clk40m,
	output wire CSN,
	output wire RSTN,
	input wire PME,
	output wire CMD,
	input wire INTRN,
	output wire RDN,
	output wire WRN,
	inout [15:0] SD,
	output wire LED	
    );
	
	wire reset;
	wire length;//Indicate manipulating 16-bit register(1) or 8-bit(0) 
	wire RW;//Reg read(0) or write(1)
	assign LED = RSTN & PME;//idle
	assign CSN = 0;
	wire[15:0] dataRead;
	reg[15:0] dataWrite;
	
	
	AccessReg RegIO(
		.clk40m(clk40m),
		.reset(reset),
		.CMD(CMD),
		.RDN(RDN),
		.WRN(WRN),
		.RW(RW),
		.offset(offset),
		.length(length),
		.SD(SD),
		.inData(dataWrite),
		.outData(dataRead),
		.done(regDone)
	);

	
endmodule
