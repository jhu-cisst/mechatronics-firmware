`timescale 1ns / 1ps
/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2014-2021 ERC CISST, Johns Hopkins University.
 *
 * This module implements the finite impulse response filter for potentiometer feedback
 * and motor current feedback. FIR core uses 4 parallel data path for processing data 
 * stream from 4 axis. It uses clkadc as driving clock signal. 4 DSP slices are needed for 
 * this module.
 * 
 * Revision history
 *     19/06/21    Jintan Zhang        Initial Revision
 * 
 */

module FirFilter(
  input  wire        clkfir,
  input  wire        data_ready,
	input  wire        reload_valid,
	input  wire        reload_last,
	output wire        reload_ready,
	input  wire [15:0] reload_coeff,
	input  wire [15:0] input1,
	input  wire [15:0] input2,
	input  wire [15:0] input3,
	input  wire [15:0] input4,
	output reg  [15:0] output1,
	output reg  [15:0] output2,
	output reg  [15:0] output3,
	output reg  [15:0] output4
);

// local wires
reg          fb_tvalid;
initial      fb_tvalid = 0;

// generate tvalid signal according to adc data_ready
always @(posedge(clkfir)) begin
	if (data_ready && reload_valid == 0) begin
	  fb_tvalid <= 1'b1;
	end else begin
		fb_tvalid <= 0;
	end
end

// functional part
// local wires
reg  [63:0]  s_axis_data_tdata;
wire         s_axis_data_tready; 
wire         s_axis_config_tready;
reg  [7:0]   s_axis_config_tdata;
reg          s_axis_config_tvalid;
wire [159:0] m_axis_data_tdata;
wire         m_axis_data_tvalid;
wire         event_s_reload_tlast_missing;
wire         event_s_reload_tlast_unexpected;

// config data, required for coefficient reload, 
// data content is irrelavent since it is not used
initial      s_axis_config_tdata = 7'd0;
initial      s_axis_config_tvalid = 1'b1;

// config channel sequence
always @(posedge(clkfir)) begin
	if (s_axis_config_tready) begin
		s_axis_config_tvalid <= 0;
	end
	// send same config packet after coeff reload
	if (reload_last) begin
		s_axis_config_tvalid <= 1'b1;
	end
end

// feed data sequentially to each channel
always @(posedge(fb_tvalid)) begin
	if (s_axis_data_tready) begin
	  s_axis_data_tdata <= {input4, input3, input2, input1};
  end
end

FIR filter (
  .aclk(clkfir),                                                    // input aclk
  .s_axis_data_tvalid(fb_tvalid),                                   // input s_axis_data_tvalid
  .s_axis_data_tready(s_axis_data_tready),                          // output s_axis_data_tready
  .s_axis_data_tdata(s_axis_data_tdata),                            // input [63 : 0] s_axis_data_tdata
  .s_axis_config_tvalid(s_axis_config_tvalid),                      // input s_axis_config_tvalid
  .s_axis_config_tready(s_axis_config_tready),                      // output s_axis_config_tready
  .s_axis_config_tdata(s_axis_config_tdata),                        // input [7 : 0] s_axis_config_tdata
  .s_axis_reload_tvalid(reload_valid),                              // input s_axis_reload_tvalid
  .s_axis_reload_tready(reload_ready),                              // output s_axis_reload_tready
  .s_axis_reload_tlast(reload_last),                                // input s_axis_reload_tlast
  .s_axis_reload_tdata(coeff),                                      // input [15 : 0] s_axis_reload_tdata
  .m_axis_data_tvalid(m_axis_data_tvalid),                          // output m_axis_data_tvalid
  .m_axis_data_tdata(m_axis_data_tdata),                            // output [159 : 0] m_axis_data_tdata
  .event_s_reload_tlast_missing(event_s_reload_tlast_missing),      // output event_s_reload_tlast_missing
  .event_s_reload_tlast_unexpected(event_s_reload_tlast_unexpected) // output event_s_reload_tlast_unexpected
);

// select 16 bits data 
always@(posedge(m_axis_data_tvalid)) begin
	output1 <= m_axis_data_tdata[35:20];
	output2 <= m_axis_data_tdata[75:60];
	output3 <= m_axis_data_tdata[115:100];
	output4 <= m_axis_data_tdata[155:140];
end

endmodule