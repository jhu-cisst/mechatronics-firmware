/*******************************************************************************    
 *
 * Copyright(C) 2017 Johns Hopkins University
 *
 * Module:  UartRx
 *
 * Purpose: This module receives RS232 stream and converts it to
 *          parallel data.
 *
 * Revision history
 *     08/09/17    Jie Ying Wu         Initial revision
 */
 
module ds_UartRx(
	input  wire       clk,          // 9600 Hz
    input  wire       reset,        // Global reset
	input  wire       ser_in,       // Serial RS232 stream in
	output reg  [7:0] rx_data,      // Parallel received data
    output reg        new_rx_data   // Signals new data available
);

    reg [7:0] rshift;
    reg [2:0] counter;
    reg [1:0] state;

    localparam IDLE    = 2'h1,
               RECEIVE = 2'h2,
               STOP    = 2'h3;
           
    initial begin
        counter <= 3'b0;
        state   <= IDLE;
    end
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 3'b0;
            state   <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    new_rx_data <= 1'b0;
                    if (~ser_in) begin
                        state   <= RECEIVE;
                        counter <= 3'b0;
                    end
                end
                RECEIVE: begin
                    counter <= counter + 3'b1;
                    if (counter == 3'h7) begin 
                        state       <= STOP;
                    end
                end 
                STOP: begin  // Load data now
                    new_rx_data <= 1'b1;
                    rx_data     <= rshift;
                    state       <= IDLE;
                end
            endcase
        end
    end

    // Always shift in data
    always @(negedge clk) begin
        rshift[7:0] <= {ser_in, rshift[7:1]};
    end
endmodule
