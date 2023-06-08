/*******************************************************************************
 *
 * Copyright(C) 2017-2023 ERC CISST, Johns Hopkins University
 *
 * Module: ESPMComm
 *
 * Purpose: This file contains the receiving module (ESPMRX) and transmitting
 *          module (ESPMTX) of the duplex communication between the dVRK board
 *          and the ESPM board on the da Vinci Si PSM.
 *          The communication is in three stages.
 *          FRAME:  Looks for 32-bit frame, 32'hAC450F28
 *          R_DATA: Expects 25 32-bit words
 *          R_CRC:  Checks against a 16-bit CRC
 *
 * Revision history
 *     07/14/17    Jie Ying Wu    Initial revision
 */

`timescale 1ns / 1ps

`define ESPMCOMM_MAGIC 32'hAC450F28

module ESPMRX (input wire clock,                 // bit clock for ESPM chain
               input wire rdat,                  // serial data in
               output reg [1:0] cfsm,
               output wire [31:0] rdata,          // UNREGISTERED receive data - load when load_rdata asserts
               output wire load_rdata,            // time to load rdata
               output wire [9:0] rdata_sel,       //
               output reg framed,         // we saw a valid framing sequence for the current packet
               output reg crc_good,              // received a pkt with good CRC
               output reg eof,                   // end of packet
               output reg [15:0] page,
               output reg [9:0] length);

    // internal variables
    wire [15:0] crc_data;

    reg [14:0] bit_ctr = 'd0;
    assign rdata_sel   = bit_ctr[14:5] - 'd2;
    wire [4:0] bit_sel = bit_ctr[4:0];
    wire load_crc = bit_sel[2:0] == 'b111 && cfsm != R_CRC;
    assign load_rdata = bit_sel == 'd31 && cfsm == R_DATA;

    reg [31:0] rdata_shift;
    assign rdata = rdata_shift;

    reg [5:0] recovery_extra_delay = 'd0;
    reg recovery_extra_delay_en = 'b0;


    localparam FRAME = 2'h0,
    R_HEADER = 2'h1,
    R_DATA = 2'h2,
    R_CRC = 2'h3;

    initial begin
        cfsm       <= FRAME;
    end

    //----------------------------------------------------------------------------------------------
    always @(posedge clock)
    begin
        bit_ctr <= cfsm == FRAME ? 'd32 : bit_ctr + 'b1;

        case (cfsm)
            FRAME: begin
                eof       <= 'b0;
                crc_good  <= 'b0;
                if (rdata_shift == `ESPMCOMM_MAGIC) begin
                    framed    <= 'b1;
                    cfsm      <= R_HEADER;
                end
            end

            R_HEADER: begin
                if (bit_sel == 'd31) begin
                    cfsm <= R_DATA;
                    length <= rdata_shift[9:0] + (recovery_extra_delay_en ? recovery_extra_delay : 'd0);
                    page <= rdata_shift[31:16];
                end
            end

            R_DATA: begin
                if ((bit_sel == 'd31) && (rdata_sel == length - 'd1)) begin
                    cfsm <= R_CRC;
                end
            end

            R_CRC: begin
                if (bit_sel == 'd31) begin
                    framed  <= 'b0;
                    eof     <= 'b1;
                    cfsm    <= FRAME;
                    if (crc_data == rdata_shift[15:0]) begin
                        crc_good       <= 'b1;
                        recovery_extra_delay_en <= 'b0;
                        recovery_extra_delay <= 'd0;
                    end else begin
                        recovery_extra_delay_en <= recovery_extra_delay > 'd3 ? ~recovery_extra_delay_en : 'b0;
                        recovery_extra_delay <= recovery_extra_delay + 'd1;
                    end
                end
            end
        endcase
    end

    always @ (negedge clock) begin
        rdata_shift <= {rdat, rdata_shift[31:1]};  // always right shift in data
    end

    wire [7:0] crc_input = rdata_shift[31:24];

    crc16 CRC (
    .clock   (clock),
    .init    (cfsm == FRAME),
    .ena     (load_crc), 
    .data    (crc_input),
    .q       (crc_data)
    );

endmodule


module ESPMTX (
    input  wire        clock,      // received clock from ESM
    input  wire [31:0] tdata,      // parallel transmit data (output of mux selected by tdata_sel)
    input [15:0] page,
    input [9:0] length,

    output reg   [1:0] cfsm,       // current state
    output wire   [9:0] tdata_sel,  // 6 bit counter that selects tdata multiplexor
    output reg         pkt_start,  // starting to xmit a new packet
    output reg         load_tdata, // loading serializer from parallel input
    output reg         tdat);      // serial data out

    // internal variables
    wire  [15:0]  crc_data;

    reg [14:0] bit_ctr = 'd0;

    // There are 2 quadlets before the payload, but here we advance the tdata_sel by 1
    // to give some timing margin for the data source.
    assign tdata_sel   = bit_ctr[14:5] - 'd1;
    wire [4:0] bit_sel = bit_ctr[4:0];

    reg [15:0] page_latched;
    reg [9:0] length_latched;
    reg [31:0] current_quadlet;
    reg [31:0] payload_buffer;

    localparam FRAME = 2'h0,  // transmit framing sequence
    T_HEADER = 2'h1,  // transmit header
    T_DATA = 2'h2,  // transmit data
    T_CRC = 2'h3; // transmit CRC

    initial
    begin
        pkt_start  <= 'b0;
        load_tdata <= 'd0;
        cfsm       <= FRAME;  // start by framing on the recv data
    end

    //----------------------------------------------------------------------------------------------

    always @(*) begin
        case (cfsm)
            FRAME: current_quadlet = `ESPMCOMM_MAGIC;
            T_HEADER: current_quadlet = {page_latched, 6'b0, length_latched};
            T_DATA: current_quadlet = payload_buffer;
            T_CRC: current_quadlet = {16'b0, crc_data};
            default: current_quadlet = 32'hcccccccc;
        endcase
    end

    always @(posedge clock) begin
        bit_ctr <= bit_ctr + 1'b1;
        tdat <= current_quadlet[bit_sel];

        if (bit_ctr == 'd31) begin
            page_latched <= page;
            length_latched <= length;
        end
        if (load_tdata) begin
            payload_buffer <= tdata;
        end
        pkt_start <= bit_ctr == 'd0;
        load_tdata <= bit_sel == 'd30; // assert at 30 to load at 31 because of pipelining

        case (cfsm)
            FRAME: begin
                if (bit_sel == 'd31) cfsm <= T_HEADER;
            end

            T_HEADER: begin
                if (bit_sel == 'd31) cfsm <= T_DATA;
            end

            T_DATA: begin
                if ((bit_sel == 'd31) & (tdata_sel == length_latched)) begin
                    cfsm    <= T_CRC;
                end
            end

            T_CRC: begin
                if (bit_sel == 'd31) begin
                    cfsm    <= FRAME;
                    bit_ctr <= 'd0;
                end
            end
        endcase
    end

    reg crc_en = 'b0;
    reg [7:0] crc_input = 'b0;
    always @(posedge clock) begin
        case (bit_sel[1:0])
            'b00: crc_input <= current_quadlet[7:0];
            'b01: crc_input <= current_quadlet[15:8];
            'b10: crc_input <= current_quadlet[23:16];
            'b11: crc_input <= current_quadlet[31:24];
            default: crc_input <= 'b0;
        endcase
        crc_en <= bit_sel[4:2] == 'b0 && cfsm != T_CRC;
    end


    crc16 CRC (
    .clock   (clock),
    .init    (cfsm == FRAME),
    .ena     (crc_en),
    .data    (crc_input),
    .q       (crc_data)
    );

endmodule
