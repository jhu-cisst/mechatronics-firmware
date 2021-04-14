`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    11:41:03 04/14/2021 
// Design Name: 
// Module Name:    FirFilter 
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
module FirFilter(
    input clkfir,
	 input clkadc,
    input wire data_valid,
	 input wire [15:0] raw_data,
	 output reg [15:0] filtered_data
);


// wire declaration
wire s_axis_data_tready;
wire m_axis_data_tvalid;
reg [15:0] s_axis_data_tdata;
wire [39:0] m_axis_data_tdata;

// feed raw data to filter when data_valid and data_tready are set
always @(posedge(data_valid)) begin
	if (s_axis_data_tready) begin
		s_axis_data_tdata <= raw_data;
	end
end

FIR filter (
  .aclk(clkfir),                               // input aclk
  .s_axis_data_tvalid(data_valid),             // input s_axis_data_tvalid
  .s_axis_data_tready(s_axis_data_tready),     // output s_axis_data_tready
  .s_axis_data_tdata(s_axis_data_tdata),       // input [15 : 0] s_axis_data_tdata
  .m_axis_data_tvalid(m_axis_data_tvalid),     // output m_axis_data_tvalid
  .m_axis_data_tdata(m_axis_data_tdata)        // output [39 : 0] m_axis_data_tdata
);

// return filtered data
always@(posedge(m_axis_data_tvalid)) begin
	filtered_data <= m_axis_data_tdata[35:20];
end

endmodule