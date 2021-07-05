module  uart_recv_2480(
     input               sys_clk,          //sys clk

	 input               uart_rxd,         //UART recv port
	 output  reg  [3:0]  rx_cnt,           //recv data counter
	 output  reg  [7:0]  rxdata            //recv data buffer
);


//parameter define
parameter    CLK_FREQ = 49152000;          //define sys clk freq
parameter    UART_BPS = 9600;              //define serial baud
localparam   BPS_CNT  = CLK_FREQ/UART_BPS; //count BPS_CNT times for sys clk


//reg define
reg          uart_rxd_d0;                  
reg          uart_rxd_d1;
reg   [15:0] clk_cnt;                      //sys clk counter
reg          rx_flag;                      //recv process flag


//wire define
wire         start_flag;                  
 

//**************************************************************
//                       main  code
//**************************************************************


//capture recv port falling edge (start bit), get 1 clk cycle pulse
assign  start_flag = uart_rxd_d1 & (~uart_rxd_d0);


//delay 2 clk cycle for UART recv port data
always @(posedge sys_clk) begin
	 begin
	     uart_rxd_d0 <= uart_rxd;
		 uart_rxd_d1 <= uart_rxd_d0;
	 end
end

		  
//when pulse start_flag arrives, start recv process
always @(posedge sys_clk) begin
     begin
	     if (start_flag)                    //detect start bit
		     rx_flag <= 1'b1;               //enter recv process, rx_flag pull up
		 else if ((rx_cnt == 4'd9)&&(clk_cnt == BPS_CNT/2))
		     rx_flag <= 1'b0;               //stop recv process when counting to half of the stop bit
		 else
		     rx_flag <= rx_flag;            
	 end
end


//after entering recv process, start sys clk cnt & recv data cnt
always @(posedge sys_clk) begin
	 if (rx_flag) begin                     //still in recv process
	     if (clk_cnt < BPS_CNT - 1) begin
		     clk_cnt <= clk_cnt + 1'b1;
             rx_cnt  <= rx_cnt;
		 end
		 else begin
		     clk_cnt <= 16'd0;              //sys clk cnt reset after 1 baud cycle
		     rx_cnt  <= rx_cnt + 1'b1;      //while recv data cnt add 1
		 end
	 end
	 else begin                             //recv process end, counter reset
	     clk_cnt <= 16'd0;
		 rx_cnt  <= 4'd0; 
     end        
end


//store UART recv data according to recv counter
always @(posedge sys_clk) begin
     if (rx_flag)                                  //system in recv process
	     if (clk_cnt == BPS_CNT/2) begin           //sys clk cnt counts to half of a data bit
              case (rx_cnt)
				 4'd1 : rxdata[0] <= uart_rxd_d1;  //data bits lowest bit
				 4'd2 : rxdata[1] <= uart_rxd_d1;
				 4'd3 : rxdata[2] <= uart_rxd_d1;
				 4'd4 : rxdata[3] <= uart_rxd_d1;
				 4'd5 : rxdata[4] <= uart_rxd_d1;
				 4'd6 : rxdata[5] <= uart_rxd_d1;
				 4'd7 : rxdata[6] <= uart_rxd_d1;
				 4'd8 : rxdata[7] <= uart_rxd_d1;  //data bits highest bit
				 default: ;
		      endcase
		     end
		  else
		     rxdata <= rxdata;
	 else
	     rxdata <= 8'd0;	 
end

endmodule
