`timescale 1ns / 1ps

/*******************************************************************************
 *
 * Copyright(C) 2013-2020 ERC CISST, Johns Hopkins University.
 *
 * This module performs a safety check by comparing the measured motor current
 * (cur_in) to the commanded motor current (dac_in). If the difference is too
 * large, the amp_disable signal is set to indicate that the motor amplifiers
 * should be disabled.
 *
 * Commanded and measured motor currents are both 16-bit unsigned values,
 * with a full scale of +/-6.25 Amps.
 *
 * Generally, the threshold for the safety check is 0x900 bits (about 440 mA).
 * If the difference is greater than this, then error_counter is incremented.
 * There are two special cases:
 * 1) If the measured current is small (<150 mA), then error_counter is cleared.
 * 2) If the commanded current is large (within 0x900 bits or 440 mA of the maximum
 *    positive or negative value), then error_counter is cleared.  The rationale is that
 *    if a large motor current is commanded, there is little value to a safety check
 *    (i.e., the system cannot be less safe by applying a large motor current, because
 *    that is what was requested).
 * If error_counter reaches a value of 2457600 (50 ms, with clk=49.152 MHz), the
 * amp_disable signal is set. It is cleared by asserting the clear_disable input.
 *
 * Revision history
 *     04/26/13    Zihan Chen    Initial revision
 */

// USE_SIMULATION flag
`include "Constants.v"

module SafetyCheck(
    input  wire clk,            // system clock
    input  wire[15:0] cur_in,   // feedback current
    input  wire[15:0] dac_in,   // command current
    input  wire clear_disable,  // signal to clear amplifier disable
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
    always @ (posedge(clk) or posedge(clear_disable))
    begin
        if (clear_disable) begin
            amp_disable <= 1'b0;
        end
        
`ifdef USE_SIMULATION
        // use counter limit = 5 for simulation
        else if (error_counter < 24'd5) begin 
            amp_disable <= amp_disable;
        end
`else        
        // 50 mS
        else if (error_counter < 24'd2457600) begin
            amp_disable <= amp_disable;
        end
`endif        
        else begin
            amp_disable <= 1'b1;
        end
    end
    
endmodule
