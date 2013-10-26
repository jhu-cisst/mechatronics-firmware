`timescale 1ns / 1ps

/*******************************************************************************
 *
 * Copyright(C) 2013 ERC CISST, Johns Hopkins University.
 *
 * This module controls access to the adc modules by selecting the data to
 * output based on the read address, and by combining the 16-bit values for
 * analog pot and motor current into a single 32-bit word.
 *
 * Revision history
 *     04/26/13    Zihan Chen    Initial revision
 */

// USE_SIMULATION flag
`include "Constants.v"

module SafetyCheck(
    input  wire clk,            // system clock
    input  wire reset,          // global reset
    input  wire[15:0] cur_in,   // feedback current
    input  wire[15:0] dac_in,   // command current
    input  wire reg_wen, 
    output reg  amp_disable     // amplifier disable
    );
     
    // local variable
    reg [23:0] error_counter;  // error counter 
    reg [15:0] abs_error_cur;
    wire [15:0] high_limit;
    wire[15:0] low_limit;
	 
    // ---- Code Starts Here -----
    initial begin
        amp_disable <= 1'b0;
        error_counter <= 24'd0;
    end
    
    assign high_limit = ((dac_in[15] == 1'b1) ? dac_in : ~dac_in) + 16'h0900;
    assign low_limit = ((dac_in[15] == 1'b1) ? ~dac_in : dac_in) - 16'h0900;

    always @ (posedge clk)
    begin
        // If measured current is small (150 mA), clear error counter
        if ((cur_in < 16'h8300) && (cur_in > 16'h7d00)) begin
           error_counter <= 24'd0;
        end
        
        // else if commanded current is large, 
        // clear error counter (margin = 0x0900 440 mA)
        else if ((dac_in <= 16'h0900) || (dac_in >= 16'hf6ff)) begin
           error_counter <= 24'd0;
        end 
          
        // else perform safety check
        else begin
           if ((cur_in < low_limit) || (cur_in > high_limit)) begin
               error_counter <= error_counter + 1'b1;
           end
           else begin
               error_counter <= 24'd0;
           end
        end
    end

    
    // amp_disable
    always @ (posedge(clk) or negedge(reset) or posedge(reg_wen))
    begin
        if (reset == 0 || reg_wen) begin
            amp_disable <= 1'b0;
        end
        
        // 50 mS 
`ifdef USE_SIMULATION
        // use counter limit = 5 for simulation
        else if (error_counter < 24'd5) begin 
            amp_disable <= amp_disable;
        end
`else        
        else if (error_counter < 24'd2457600) begin
            amp_disable <= amp_disable;
        end
`endif        
        else begin
            amp_disable <= 1'b1;
        end
    end
    
endmodule
