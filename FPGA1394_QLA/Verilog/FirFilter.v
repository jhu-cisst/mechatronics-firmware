`timescale 1ns / 1ps

module FirFilter(
    input wire        clkfir,
    input wire        data_ready,
	 input wire [15:0] input1,
	 input wire [15:0] input2,
	 input wire [15:0] input3,
	 input wire [15:0] input4,
	 output reg [15:0] output1,
	 output reg [15:0] output2,
	 output reg [15:0] output3,
	 output reg [15:0] output4
);

// local wires
reg         pot_fb_tvalid;
reg  [2:0]  num_channel;
reg  [5:0]  counter;
wire [15:0] input_data [3:0];

initial counter       = 0;
initial num_channel   = 1;
initial pot_fb_tvalid = 0;

assign input_data[0] = input1;
assign input_data[1] = input2;
assign input_data[2] = input3;
assign input_data[3] = input4;

// feed data into 4 channel by waiting minimum cycles 
// needed to process one input. Usually when the coeff
// number is odd and symmetric, the # of cycles = (num_coeff - 1)/2
// in this case, we waited some extra cycles for stability
always @(posedge(clkfir)) begin
	if (data_ready) begin
	   pot_fb_tvalid <= 1;
		num_channel <= 1;
		counter <= 1;
	end 
	
	if (counter > 0 && counter < 20) begin
		pot_fb_tvalid <= 0;
		counter <= counter + 1;
	end
	
	if (num_channel <= 3 && counter >= 20) begin
	   pot_fb_tvalid <= 1;
		num_channel <= num_channel + 1;
		counter <= 1;
	end
end

// functional part
// local wires
reg  [15:0] s_axis_data_tdata;
wire        s_axis_data_tready; 
wire        s_axis_config_tready;
reg  [4:0]  s_axis_config_tdata;
reg         s_axis_config_tvalid;
wire [39:0] m_axis_data_tdata;
wire        m_axis_data_tvalid;
reg  [1:0]  s_axis_data_tuser;
wire        event_s_data_chanid_incorrect;

initial    s_axis_config_tdata = 4;
initial    s_axis_config_tvalid = 1;

assign     config_tready = s_axis_config_tready;
assign     config_tvalid = s_axis_config_tvalid;
assign     sready = s_axis_data_tready;

// config channel sequence
always @(posedge(clkfir)) begin
	if (s_axis_config_tready) begin
		s_axis_config_tvalid <= 0;
	end
end

// feed data sequentially to each channel
always @(posedge(pot_fb_tvalid)) begin
	s_axis_data_tdata <= input_data[num_channel-1];
	s_axis_data_tuser <= num_channel - 1;
end

FIR filter (
  .aclk(clkfir),                                                // input aclk
  .s_axis_data_tvalid(pot_fb_tvalid),                           // input s_axis_data_tvalid
  .s_axis_data_tready(s_axis_data_tready),                      // output s_axis_data_tready
  .s_axis_data_tuser(s_axis_data_tuser),                        // input [1 : 0] s_axis_data_tuser
  .s_axis_data_tdata(s_axis_data_tdata),                        // input [15 : 0] s_axis_data_tdata
  .s_axis_config_tvalid(s_axis_config_tvalid),                  // input s_axis_config_tvalid
  .s_axis_config_tready(s_axis_config_tready),                  // output s_axis_config_tready
  .s_axis_config_tdata(s_axis_config_tdata),                    // input [7 : 0] s_axis_config_tdata
  .m_axis_data_tvalid(m_axis_data_tvalid),                      // output m_axis_data_tvalid
  .m_axis_data_tuser(m_axis_data_tuser),                        // output [1 : 0] m_axis_data_tuser
  .m_axis_data_tdata(m_axis_data_tdata),                        // output [39 : 0] m_axis_data_tdata
  .event_s_data_chanid_incorrect(event_s_data_chanid_incorrect) // output event_s_data_chanid_incorrect
);

// select 16 bits data 
always@(posedge(m_axis_data_tvalid)) begin
	if (m_axis_data_tuser == 0) begin
		output1 <= m_axis_data_tdata[35:20];
	end else if (m_axis_data_tuser == 1) begin
	   output2 <= m_axis_data_tdata[35:20];
	end else if (m_axis_data_tuser == 2) begin
	   output3 <= m_axis_data_tdata[35:20];
	end else if (m_axis_data_tuser == 3) begin
	   output4 <= m_axis_data_tdata[35:20];
	end
end

endmodule