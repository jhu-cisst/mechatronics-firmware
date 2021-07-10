module  uart_send_2480(
     input               sys_clk,           //sys clk
     wire   send_temp,      
	 input               uart_en,           //send enable sig
     input   [9:0]       uart_din,          //data-to-be-sent
	 output  reg         uart_done         //send 1 frame over flag	
	  
);

reg    uart_txd;      //UART send port
assign send_temp = uart_txd;

//parameter define
parameter    CLK_FREQ = 49152000;           //define sys clk freq
parameter    UART_BPS = 9600;               //define serial baud
localparam   BPS_CNT  = CLK_FREQ/UART_BPS;  //count BPS_CNT times for sys clk

//reg define
reg          uart_en_d0;                  
reg          uart_en_d1;
reg  [15:0]  clk_cnt;                       //sys clk counter
reg  [ 3:0]  tx_cnt;                        //send data counter
reg          tx_flag;                       //send process flag
reg  [ 9:0]  tx_data;                       //send data buffer

//wire define
wire         en_flag;      

//**************************************************************
//                       main  code
//**************************************************************

//capture uart_en rising edge, get 1 clk cycle pulse
assign  en_flag = (~uart_en_d1) & uart_en_d0;

//delay 2 clk cycle for send enable sig uart_en
always @(posedge sys_clk) begin
	 begin
	     uart_en_d0 <= uart_en;
		 uart_en_d1 <= uart_en_d0;
	 end
end
		  
//when en_flag pulled high, register data-to-be-sent and start send process
always @(posedge sys_clk) begin
	 if (en_flag) begin                      //detect send enable rising edge
         tx_flag <= 1'b1;                    //enter send process, tx_flag pull up
		 uart_done <= 1'b0;
         tx_data <= uart_din;                //register data-to-be-sent		  
	 end
	 else if ((tx_cnt == 4'd9)&&(clk_cnt == BPS_CNT/2)) 
	 begin                                   //stop send process in the half of stop bit
	     tx_flag <= 1'b0;                    //send process end, tx_flag pull down
		 uart_done <= 1'b1; 
	     tx_data <= 10'd0; 
	 end
	 else begin
	     tx_flag <= tx_flag;
		 uart_done <= 1'b0;
		 tx_data <= tx_data;
	 end
end

//after entering send process, start sys clk cnt & send data cnt
always @(posedge sys_clk) begin
	 if (tx_flag) begin                      //still in send process
	     if (clk_cnt < BPS_CNT - 1) begin
		     clk_cnt <= clk_cnt + 1'b1;
             tx_cnt  <= tx_cnt;
		 end
		 else begin
		     clk_cnt <= 16'd0;               //sys cnt reset after 1 baud cycle
		     tx_cnt  <= tx_cnt + 1'b1;       //while send data cnt add 1
		 end
	 end
	 else begin                              //send process end, counter reset
	     clk_cnt <= 16'd0;
		 tx_cnt  <= 4'd0; 
    end        
end

//assign data to UART sent port according to send cnt
always @(posedge sys_clk) begin
	 if (tx_flag)  
        case (tx_cnt)
		      4'd0 : uart_txd <= 1'd0; //start bit
			  4'd1 : uart_txd <= tx_data[1]; //data bits lowest bit
			  4'd2 : uart_txd <= tx_data[2];
			  4'd3 : uart_txd <= tx_data[3];
			  4'd4 : uart_txd <= tx_data[4];
			  4'd5 : uart_txd <= tx_data[5];
			  4'd6 : uart_txd <= tx_data[6];
			  4'd7 : uart_txd <= tx_data[7];
			  4'd8 : uart_txd <= tx_data[8]; //data bits highest bit
			  4'd9 : uart_txd <= 1'd1; //stop bit
			  default: ;
		  endcase
	 else
	     uart_txd <= 1'b1;	                 //send port pulled high when free 
end

// //data send process finish, then issue a flag sig
// always @(posedge sys_clk) begin
// 	 if (tx_cnt == 4'd9)                     //counts to the final bit   
// 		 uart_done <= 1'b1;                  //pull up send done flag
// 	 else 
// 		 uart_done <= 1'b0;
// end

endmodule

