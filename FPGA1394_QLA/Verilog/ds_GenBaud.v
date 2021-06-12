/*******************************************************************************    
 *
 * Copyright(C) 2017 Johns Hopkins University
 *
 * Module:  GenBaud
 *
 * Purpose: This module generates 4800 and 9600 Hz clocks for RS232  
 *          communication to the DS2480B. 
 *
 * Revision history
 *     08/09/17    Jie Ying Wu         Initial revision
 */

module ds_GenBaud (
	input wire clk, 
    input wire reset, 
	output reg clk9600,
    output reg clk4800
);

    reg [11:0]	counter;

    initial begin
        counter <= 12'b0;
        clk4800 <= 1'b0;
        clk9600 <= 1'b0;
    end

// Counter to step down the clock to ~9600 Hz
    always @ (posedge clk or posedge reset)
    begin
        if (reset) begin 
            counter <= 12'b0;
        end else if (counter == 12'd2610) begin 
            counter  <= 12'b0;
            clk9600 <= ~clk9600;
        end else begin 
            counter <= counter + 12'b1;
        end
    end

// Half the clock rate for master reset
    always @ (posedge clk9600) begin
        clk4800 <= ~clk4800;
    end
endmodule
