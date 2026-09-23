/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

`timescale 1ns / 1ps

/*
 * dSIB-Si packet (11 bytes, 115200 8N1):
 *   0..3  "dSIB"
 *   4     {3'b0, dsib_z_si_present, suj_z_id[3:0]}
 *   5     suj_z_pot1[7:0]
 *   6     {4'b0, suj_z_pot1[11:8]}
 *   7     suj_z_pot2[7:0]
 *   8     {4'b0, suj_z_pot2[11:8]}
 *   9..10 CRC16, low byte first
 * CRC16 is initialized to 16'hffff and covers bytes 4 through 8.
 */
module dsib_si_parser
(
    input wire       clk,
    input wire[7:0]  rx_data,
    input wire       rx_data_valid,

    output reg       packet_valid = 1'b0,
    output reg[3:0]  suj_z_id = 4'd0,
    output reg       dsib_z_si_present = 1'b0,
    output reg[11:0] suj_z_pot1 = 12'd0,
    output reg[11:0] suj_z_pot2 = 12'd0
);

localparam[3:0] DSIB_PARSE_HEADER_D = 4'd0;
localparam[3:0] DSIB_PARSE_HEADER_S = 4'd1;
localparam[3:0] DSIB_PARSE_HEADER_I = 4'd2;
localparam[3:0] DSIB_PARSE_HEADER_B = 4'd3;
localparam[3:0] DSIB_PARSE_FLAGS = 4'd4;
localparam[3:0] DSIB_PARSE_POT1_LO = 4'd5;
localparam[3:0] DSIB_PARSE_POT1_HI = 4'd6;
localparam[3:0] DSIB_PARSE_POT2_LO = 4'd7;
localparam[3:0] DSIB_PARSE_POT2_HI = 4'd8;
localparam[3:0] DSIB_PARSE_CRC_LO = 4'd9;
localparam[3:0] DSIB_PARSE_CRC_HI = 4'd10;

reg[3:0] dsib_parse_state = DSIB_PARSE_HEADER_D;
reg[3:0] suj_z_id_staged = 4'd0;
reg dsib_z_si_present_staged = 1'b0;
reg[11:0] suj_z_pot1_staged = 12'd0;
reg[11:0] suj_z_pot2_staged = 12'd0;
reg[7:0] dsib_crc_input = 8'd0;
reg dsib_crc_init = 1'b0;
reg dsib_crc_ena = 1'b0;
wire[15:0] dsib_crc_data;
reg[7:0] dsib_received_crc_lo = 8'd0;

crc16 dsib_crc16
(
    .clock(clk),
    .init(dsib_crc_init),
    .ena(dsib_crc_ena),
    .data(dsib_crc_input),
    .q(dsib_crc_data)
);

wire dsib_packet_accept = rx_data_valid &&
                          (dsib_parse_state == DSIB_PARSE_CRC_HI) &&
                          ({rx_data, dsib_received_crc_lo} == dsib_crc_data);

always @(posedge clk) begin
    packet_valid <= 1'b0;
    dsib_crc_init <= 1'b0;
    dsib_crc_ena <= 1'b0;

    if (rx_data_valid) begin
        case (dsib_parse_state)
            DSIB_PARSE_HEADER_D: begin
                if (rx_data == "d") begin
                    dsib_parse_state <= DSIB_PARSE_HEADER_S;
                end
            end

            DSIB_PARSE_HEADER_S: begin
                if (rx_data == "S") begin
                    dsib_parse_state <= DSIB_PARSE_HEADER_I;
                end else begin
                    dsib_parse_state <= DSIB_PARSE_HEADER_D;
                end
            end

            DSIB_PARSE_HEADER_I: begin
                if (rx_data == "I") begin
                    dsib_parse_state <= DSIB_PARSE_HEADER_B;
                end else begin
                    dsib_parse_state <= DSIB_PARSE_HEADER_D;
                end
            end

            DSIB_PARSE_HEADER_B: begin
                if (rx_data == "B") begin
                    dsib_parse_state <= DSIB_PARSE_FLAGS;
                    dsib_crc_init <= 1'b1;
                end else begin
                    dsib_parse_state <= DSIB_PARSE_HEADER_D;
                end
            end

            DSIB_PARSE_FLAGS: begin
                dsib_z_si_present_staged <= rx_data[4];
                suj_z_id_staged <= rx_data[3:0];
                dsib_crc_input <= rx_data;
                dsib_crc_ena <= 1'b1;
                dsib_parse_state <= DSIB_PARSE_POT1_LO;
            end

            DSIB_PARSE_POT1_LO: begin
                suj_z_pot1_staged[7:0] <= rx_data;
                dsib_crc_input <= rx_data;
                dsib_crc_ena <= 1'b1;
                dsib_parse_state <= DSIB_PARSE_POT1_HI;
            end

            DSIB_PARSE_POT1_HI: begin
                suj_z_pot1_staged[11:8] <= rx_data[3:0];
                dsib_crc_input <= rx_data;
                dsib_crc_ena <= 1'b1;
                dsib_parse_state <= DSIB_PARSE_POT2_LO;
            end

            DSIB_PARSE_POT2_LO: begin
                suj_z_pot2_staged[7:0] <= rx_data;
                dsib_crc_input <= rx_data;
                dsib_crc_ena <= 1'b1;
                dsib_parse_state <= DSIB_PARSE_POT2_HI;
            end

            DSIB_PARSE_POT2_HI: begin
                suj_z_pot2_staged[11:8] <= rx_data[3:0];
                dsib_crc_input <= rx_data;
                dsib_crc_ena <= 1'b1;
                dsib_parse_state <= DSIB_PARSE_CRC_LO;
            end

            DSIB_PARSE_CRC_LO: begin
                dsib_received_crc_lo <= rx_data;
                dsib_parse_state <= DSIB_PARSE_CRC_HI;
            end

            DSIB_PARSE_CRC_HI: begin
                if (dsib_packet_accept) begin
                    suj_z_id <= suj_z_id_staged;
                    dsib_z_si_present <= dsib_z_si_present_staged;
                    suj_z_pot1 <= suj_z_pot1_staged;
                    suj_z_pot2 <= suj_z_pot2_staged;
                    packet_valid <= 1'b1;
                end
                dsib_parse_state <= (rx_data == "d") ? DSIB_PARSE_HEADER_S : DSIB_PARSE_HEADER_D;
            end

            default: begin
                dsib_parse_state <= DSIB_PARSE_HEADER_D;
            end
        endcase
    end
end

endmodule
