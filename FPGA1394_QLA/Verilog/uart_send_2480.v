module uart_send_2480 (
	input               sys_clk,           // sys clk
	
	input               uart_en,           // send enable sig                                
	input   [9:0]       uart_din,          // data-to-be-sent
	input   wire        master_rst,        // master reset flag
	output  reg         uart_done,         // send 1 frame over flag
	output  reg         uart_txd           // UART send port
);

// parameter define
parameter    CLK_FREQ = 49152000;           // define sys clk freq
parameter    UART_BPS_9600 = 9600;          // define serial baud - 9600
parameter    UART_BPS_4800 = 4800;          // define serial baud - 4800
localparam   BPS_CNT_9600  = CLK_FREQ / UART_BPS_9600;  // count 9600 bits per second
localparam   BPS_CNT_4800  = CLK_FREQ / UART_BPS_4800;  // count 4800 bits per second

// reg define
reg          uart_en_d0;                  
reg          uart_en_d1;
reg  [15:0]  clk_cnt;                       // sys clk counter
reg  [ 3:0]  tx_cnt;                        // send data counter
reg          tx_flag;                       // send process flag
reg  [ 9:0]  tx_data;                       // send data buffer

// wire define
wire         en_flag;      

//**************************************************************
//                       main  code
//**************************************************************

// capture uart_en rising edge, get 1 clk cycle pulse
assign  en_flag = (~uart_en_d1) & uart_en_d0;

// delay 2 clk cycle for send enable sig uart_en
always @(posedge sys_clk) begin
	 uart_en_d0 <= uart_en;
	 uart_en_d1 <= uart_en_d0;
end
		  
// when en_flag pulled high, register data-to-be-sent and start send process
always @(posedge sys_clk) begin
	 if (en_flag) begin                          // detect send enable rising edge
		 tx_flag   <= 1'b1;                      // enter send process, tx_flag pull high
		 uart_done <= 1'b0;
		 tx_data   <= uart_din;                  // register data-to-be-sent	
	 end
	 else if ((tx_cnt == 4'd9) && (clk_cnt == BPS_CNT_9600/2) && (!master_rst))
	 begin                                       // Normally in 9600 baud, stop send process a half baud cycle after stop bit
		 tx_flag   <= 1'b0;                      // send process end, tx_flag pull low
		 uart_done <= 1'b1;                      // issue send done flag to DS2505.v
		 tx_data   <= 10'd0; 
	 end
	 else if ((tx_cnt == 4'd9) && (clk_cnt == BPS_CNT_4800/2) && (master_rst))
	 begin                                       // For initial master reset in 4800 baud
		 tx_flag   <= 1'b0;                      // send process end, tx_flag pull low
		 uart_done <= 1'b1;                      // issue send done flag to DS2505.v
		 tx_data   <= 10'd0; 
	 end 
	 else begin
		 tx_flag   <= tx_flag;
		 uart_done <= 1'b0;
		 tx_data   <= tx_data;
	 end
end

// after entering send process, start sys clk cnt & send data cnt
always @(posedge sys_clk) begin
     if (tx_flag) begin                          // still in send process
		 if (master_rst) begin
             if (clk_cnt == BPS_CNT_4800 - 1) begin
				 clk_cnt <= 16'd0;               // sys cnt reset after 1 baud cycle
                 tx_cnt  <= tx_cnt + 1'b1;       // while send data cnt add 1
             end
             else
                 clk_cnt <= clk_cnt + 1'b1;
         end
         else begin
             if (clk_cnt == BPS_CNT_9600 - 1) begin
				 clk_cnt <= 16'd0;               // sys cnt reset after 1 baud cycle
                 tx_cnt  <= tx_cnt + 1'b1;       // while send data cnt add 1
             end
             else begin
                 clk_cnt <= clk_cnt + 1'b1;
             end
         end
     end
     else begin                                  // send process end, counter reset
         clk_cnt <= 16'd0;
         tx_cnt  <= 4'd0; 
     end        
end

// assign data to UART sent port according to send cnt
always @(posedge sys_clk) begin
     if (tx_flag)  
         uart_txd <= tx_data[tx_cnt];            // load data bits to send port
     else
         uart_txd <= 1'b1;	                     // send port pulled high when free 
end

endmodule

