/*******************************************************************************
 *
 * Copyright(C) 2017 ERC CISST, Johns Hopkins University
 *
 * Module: DvrkRx
 *
 * Purpose: This module is the receiving half of the duplex communication
 *          between the dVRK board and the ESPM board on the da Vinci S PSM.
 *          The communication is in three stages. 
 *          FRAME:  Looks for 32-bit frame, 32'hAC450F28
 *          R_DATA: Expects 25 32-bit words
 *          R_CRC:  Checks against a 16-bit CRC 
 *          
 * Revision history
 *     07/14/17    Jie Ying Wu    Initial revision
 */

`timescale 1ns / 1ps

module DvrkRx (
input  wire        clock,       // bit clock for ESPM chain   
input  wire        rdat,        // serial data in

output reg   [1:0] cfsm,
output reg   [4:0] bit_ctr,     // counts 16 bits per frame (word)
output reg  [31:0] rdata,       // UNREGISTERED receive data - load when load_rdata asserts
output reg         load_rdata,  // time to load rdata - won't assert if data error
output reg   [6:0] rdata_sel,   // 3 bit counter that indicates which of 8 data words to load
output reg  [31:0] framed,      // we saw a valid framing sequence for the current packet
output reg         crc_good,    // received a pkt with good CRC
output reg  [31:0] crc_err,
output reg  [31:0] crc_good_count,

input skip_crc
);

// internal variables
reg         load_crc;
wire [15:0] crc_data;


parameter FRAME   = 2'h1, 
          R_DATA  = 2'h2,
          R_CRC   = 2'h3,
          DATA_LENGTH = 'd63; 
          
initial begin
      load_rdata <= 1'b0;
      load_crc   <= 1'b0;
      framed     <= 0;
      bit_ctr    <= 5'd0;
      rdata_sel  <= 'd127;  // initialize at max so it overflows to 0 at the next count
      rdata      <= 32'd0;
      cfsm       <= FRAME;  // start by transmitting 8 zeros and ACK code (to frame receiver)
      crc_good   <= 0;
end

//----------------------------------------------------------------------------------------------

always @(posedge clock)
    begin       
      case (cfsm)
        FRAME: begin  
          if (rdata == 32'hAC450F28) begin
            framed  <= 1;
            cfsm    <= R_DATA;
            bit_ctr <= 0;
            rdata_sel <= 'd127;
				    crc_good <= 0;
          end
        end

        R_DATA: begin
          // inc rdata_sel to indicate word number for parent to load, increase at arbitrary 7 counts later
          rdata_sel  <= (bit_ctr == 7) ? (rdata_sel + 1) : rdata_sel; 
    	    load_rdata <= (bit_ctr == 30);
          load_crc   <= (bit_ctr[2:0] == 6); // loads LS (1st) byte when ctr is 8 and MS byte when ctr is 0
    	    if ((bit_ctr == 31) & (rdata_sel == DATA_LENGTH)) begin 
            cfsm    <= R_CRC;
            bit_ctr <= 0;
          end else begin
            bit_ctr <= bit_ctr + 1'b1;
          end
        end

        R_CRC: begin
		      load_rdata <= 0;
          load_crc   <= 0;
          
          if (bit_ctr == 15)
            begin
              framed <= 0;
              cfsm   <= FRAME;
			        bit_ctr <= 0;
              if (skip_crc || crc_data == rdata[31:16]) begin
				        crc_good <= 1;
                crc_good_count <= crc_good_count + 'h1;
				      end else begin
                crc_err <= crc_err + 1;
				
              end
			    end
            else begin
              bit_ctr    <= bit_ctr + 1;
            end
          end

        default: begin  
          load_rdata <= 1'b0;
          load_crc   <= 1'b0;
          framed     <= 0;
          bit_ctr    <= 5'd0;
          rdata_sel  <= 'd127;
          cfsm       <= FRAME; 
        end
      endcase
    end

// can't clock these because it would delay them to parent at same time as pkt_start is asserting
// assign crc_good = (crc_data == rdata[31:16]);

always @ (negedge clock) begin
    rdata      <= {rdat, rdata[31:1]};  // always right shift in data
end

crc16 CRC (
  .clock   (clock),
  .init    (cfsm == FRAME),     
  .ena     (load_crc),       // loads LS (1st) byte when ctr is 8 and MS byte when ctr is 0
  .data    (rdata[31:24]),   // 8 MSBs of right shifter
  .q       (crc_data)
);

endmodule
