/*******************************************************************************    
 *
 * Copyright(C) 2017 Johns Hopkins University
 *
 * Module:  UartTx
 *
 * Purpose: This module transmits RS232 stream from parallel data.
 *
 * Revision history
 *     08/09/17    Jie Ying Wu         Initial revision
 */

module ds_UartTx(
	input  wire       clk,         // 9600 Hz
    input  wire       reset,       // Global reset
	input  wire [7:0] tx_data,     // Byte of data to transmit
    input  wire       new_tx_data, // New data to transmit
	output wire       ser_out,     // Serial RS232 out
    output reg        tx_busy      // Transmitting - not accepting new data
);

reg [8:0] rshift;
reg [3:0] counter;
reg [1:0] state;

localparam IDLE     = 2'h1,
           TRANSMIT = 2'h2,
           STOP     = 2'h3;
           
initial begin
    rshift  <= 9'h1FF;
    counter <= 4'b0;
    state   <= IDLE;
end
   
assign ser_out = rshift[0]; 
  
always @(posedge clk or posedge reset) begin
    if (reset) begin
        rshift  <= 9'h1FF;
        counter <= 4'b0;
        state   <= IDLE;
    end else begin
        case (state)
            IDLE: begin     // Waiting for new data
                if (new_tx_data) begin
                    rshift  <= {tx_data, 1'b0};  // Load data and start bit to transmit
                    tx_busy <= 1'b1;
                    state   <= TRANSMIT;
                end
            end
            TRANSMIT: begin // Transmitting data - 10 bits {start bit = 0, data[0] to data[7], stop bit = 1} 
                rshift  <= {1'b1, rshift[8:1]};
                counter <= counter + 4'b1;
                if (counter == 4'h9) begin // 10 counts to send start and stop bit
                    state   <= IDLE;
                    tx_busy <= 1'b0;
                end
            end 
            STOP: begin     // just to make sure tdata doesn't get loaded twice
                rshift <= 9'h1FF;
                state  <= IDLE;
            end
        endcase
    end
end

endmodule