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



module SafetyCheck(
    input  wire clk,            // system clock
    input  wire reset,          // global reset
    input  wire[15:0] cur_in,   // feedback current
    input  wire[15:0] dac_in,   // command current
    output reg  amp_disable     // amplifier disable
    );
     
    // local variable
    reg [23:0] error_counter;  // error counter 
    reg [15:0] abs_error_cur;
	 
    // ---- Code Starts Here -----
    initial begin
        amp_disable <= 1'b0;
        abs_error_cur <= 16'd0;
        error_counter <= 24'd0;
    end

    always @ (posedge clk) 
    begin        
        // abs_error_cur
        if ( cur_in > dac_in ) begin
            abs_error_cur <= cur_in - dac_in;
        end
        else begin
            abs_error_cur <= dac_in - cur_in;
        end  
    end
	 
	 // amp_disable error counter 
    always @ (posedge(clk) or negedge(reset))
    begin
        if (reset == 0) begin
            error_counter <= 24'd0;
        end

        // 16'h1200 = 900 mA 
        else if (abs_error_cur > 16'h1200) begin
            error_counter <= error_counter + 1'b1;
        end
        
        else begin  
            error_counter <= 24'd0;
        end
    end
    
    // amp_disable
    always @ (posedge(clk) or negedge(reset))
    begin
        if (reset == 0) begin
            amp_disable <= 1'b0;
        end
        
        else if (error_counter < 24'd2457600) begin
        // for simulation
        //else if (error_counter < 24'd5) begin 
            amp_disable <= 1'b0;
        end
        else begin
            amp_disable <= 1'b1;
        end
    end
    
endmodule
