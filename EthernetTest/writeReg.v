`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    09:39:30 07/18/2014 
// Design Name: 
// Module Name:    writeReg 
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

module getWriteAddr(
	input wire[7:0] offset,
	input wire length,//length=0:byte, length=1:word
	output wire[15:0] writeAddr
	);
	wire[1:0] offsetLast;
	assign offsetLast = offset[1:0];
	assign writeAddr[12] = (offsetLast==0) ? 1:0;
	assign writeAddr[13] = ((~length && offsetLast==1) || (length && offsetLast==0)) ? 1:0;
	assign writeAddr[14] = (offsetLast==2) ? 1:0;
	assign writeAddr[15] = ((~length && offsetLast==3) || (length && offsetLast==2)) ? 1:0;	
	assign writeAddr[7:2] = offset[7:2];
endmodule

module AccessReg(
	input wire clk40m,
	input wire reset,
	output reg CMD,
	output reg RDN,
	output reg WRN,
	input wire RW,
	input wire[7:0] offset,
	input wire length,
	inout[15:0] SD,
	output reg[15:0] dataWrite,
	input wire[15:0] dataRead,
	output reg done
	);

	reg[15:0] SDReg;
	
	reg[15:0] writeReg;
	wire[15:0] writeAddr;
	getWriteAddr(
		.offset(offset),
		.length(length),
		.writeAddr(writeAddr)
	);
	
		
	localparam [1:0] s0 = 2'b00,//stage0: write address
					 s1 = 2'b01,//stage1: write data
					 s2 = 2'b10,//stage2: read data
					 s3 = 2'b11;//stage3: idle
	reg[1:0] state;
	reg[7:0] count;
	
	assign SD = SDReg;
	
	always @(posedge clk40m or negedge reset) begin//FSM
		if(!reset) begin
			CMD <= 1;
			done <= 0;
			//state = 3;
			SDReg <= 16'hzzzz;
			WRN <= 1'b1;
			RDN <= 1'b1;
		end
		else begin
			count <= count + 1'b1;
			
			if (count == 8'd10) begin
				CMD <= 1'b1;
				WRN <= 1'b0;
				SDReg <= 16'h30C0;
			end	
			else if (count == 8'd20) begin
				WRN <= 1'b1;
			end
			
			else if (count == 8'd22) begin
				RDN <= 1'b0;
				CMD <= 1'b0;
				SDReg <= 16'hzzzz;
				//outData <= SD;
			end
			
			else if (count == 8'd41) begin
				RDN <= 1'b1;
				//outData <= SD;
			end
			else if (count == 8'd42) begin				
				outData <= SD;
			end
		
//			case(state)
//				s0: begin
//					if(RDN && ~WRN) begin
//						CMD <= 0;
//						writeReg <= writeAddr;
//						state <= s2;
//					end
//					else if(~RDN && WRN) begin
//						CMD <= 0;
//						writeReg <= writeAddr;
//						state <= s1;
//					end
//					else begin
//						writeReg <= 16'h0000;
//						state <= s3;
//					end
//					end
//				s1: begin
//					done <= 1;
//					writeReg <= inData;
//					state <= s3;
//					end
//				s2: begin
//					done <= 1;
//					state <= s3;
//					end
//				s3: begin
//					if(regTrig) begin
//						CMD <= 1;
//						done <= 0;
//						state <= s0;
//					end
//					end
//				default: state <= s3;
//			endcase
		end
	end
		
//	assign SD = (state == s0 || state == s1) ? writeReg:16'bz;
//	always @(state) begin
//		if(state == s2)
//			outData <= SD;
//	end
	
	wire[35:0] ILAControl;
	Ethernet_icon icon(.CONTROL0(ILAControl));
	Ethernet_ila ila(
	    .CONTROL(ILAControl),
		.CLK(clk40m),
		.TRIG0(WRN),
		.TRIG1(RDN),
		.TRIG2(CMD),
		.TRIG3(regTrig),
		.TRIG4(offset),
		.TRIG5(SD),
		.TRIG6(count),
		.TRIG7(outData),
		.TRIG8(done),
		.TRIG9(state[0]),
		.TRIG10(INTRN)
	);
		
endmodule

