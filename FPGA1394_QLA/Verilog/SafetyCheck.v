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
    reg [15:0] abs_cur_in;
    reg [15:0] abs_dac_in;
	 
    // ---- Code Starts Here -----
    initial begin
        amp_disable <= 1'b0;
        abs_cur_in <= 16'd0;
        abs_dac_in <= 16'd0;
    end

    always @ (posedge clk) 
    begin
        // abs_cur_in
        if ( cur_in > 16'h7fff ) begin
            abs_cur_in[15:0] <= cur_in[15:0] - 16'h7fff;
        end
        else begin
            abs_cur_in[15:0] <= 16'h7fff - cur_in[15:0];
        end
    
        // abs_dac_in
        if ( dac_in > 16'h7fff ) begin
            abs_dac_in[15:0] <= dac_in[15:0] - 16'h7fff;
        end
        else begin
            abs_dac_in[15:0] <= 16'h7fff - dac_in[15:0];
        end
    
    end
	 
	 // amp_disable
    always @ (posedge(clk) or negedge(reset))
    begin
        if (reset == 0) begin
            amp_disable <= 1'b0;
        end

        // when current is small pass
        else if ((cur_in < 16'h8300) && (cur_in > 16'h7d00)) begin
            amp_disable <= 1'b0;
        end
    
        else if ((cur_in > 16'h7ff0) && (dac_in > 16'h7ff0) && (abs_cur_in > (abs_dac_in << 1))) begin
            amp_disable <= 1'b1;
        end
    
        else if ((cur_in < 16'h800f) && (dac_in < 16'h800f) && (abs_cur_in > (abs_dac_in << 1))) begin
//        else if ((cur_in < 16'h800f) && (dac_in < 16'h800f)) begin    
            amp_disable <= 1'b1;
        end
    
        else begin  
            amp_disable <= 1'b0;
        end

    end

endmodule
