/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

`timescale 1ns / 1ps

module dsib_si_uart
#(
    parameter CLOCKS_PER_BAUD = 427 // 115200 baud at 49.152 MHz
)
(
    input wire       clk,

    input wire       rx_pin,
    output reg[7:0]  rx_data = 8'd0,
    output reg       rx_data_valid = 1'b0,
    input wire       rx_data_ready,

    input wire[7:0]  tx_data,
    input wire       tx_data_valid,
    output reg       tx_data_ready = 1'b1,
    output wire      tx_pin
);

localparam[15:0] BAUD_CYCLES = CLOCKS_PER_BAUD;
localparam[15:0] HALF_BAUD_CYCLES = CLOCKS_PER_BAUD / 2;

localparam[2:0] RX_IDLE = 3'd0;
localparam[2:0] RX_START = 3'd1;
localparam[2:0] RX_DATA = 3'd2;
localparam[2:0] RX_STOP = 3'd3;
localparam[2:0] RX_HOLD = 3'd4;

reg[2:0] rx_state = RX_IDLE;
reg[15:0] rx_cycle_count = 16'd0;
reg[2:0] rx_bit_count = 3'd0;
reg[7:0] rx_shift = 8'd0;
reg rx_pin_d0 = 1'b1;
reg rx_pin_d1 = 1'b1;
wire rx_pin_falling = rx_pin_d1 & ~rx_pin_d0;

always @(posedge clk) begin
    rx_pin_d0 <= rx_pin;
    rx_pin_d1 <= rx_pin_d0;

    if (rx_data_valid && rx_data_ready) begin
        rx_data_valid <= 1'b0;
    end

    case (rx_state)
        RX_IDLE: begin
            rx_cycle_count <= 16'd0;
            rx_bit_count <= 3'd0;
            if (rx_pin_falling) begin
                rx_state <= RX_START;
            end
        end

        RX_START: begin
            if (rx_cycle_count == HALF_BAUD_CYCLES - 16'd1) begin
                rx_cycle_count <= 16'd0;
                if (!rx_pin_d1) begin
                    rx_state <= RX_DATA;
                end else begin
                    rx_state <= RX_IDLE;
                end
            end else begin
                rx_cycle_count <= rx_cycle_count + 16'd1;
            end
        end

        RX_DATA: begin
            if (rx_cycle_count == BAUD_CYCLES - 16'd1) begin
                rx_cycle_count <= 16'd0;
                rx_shift[rx_bit_count] <= rx_pin_d1;
                if (rx_bit_count == 3'd7) begin
                    rx_bit_count <= 3'd0;
                    rx_state <= RX_STOP;
                end else begin
                    rx_bit_count <= rx_bit_count + 3'd1;
                end
            end else begin
                rx_cycle_count <= rx_cycle_count + 16'd1;
            end
        end

        RX_STOP: begin
            if (rx_cycle_count == BAUD_CYCLES - 16'd1) begin
                rx_cycle_count <= 16'd0;
                rx_state <= RX_HOLD;
                if (rx_pin_d1) begin
                    rx_data <= rx_shift;
                    rx_data_valid <= 1'b1;
                end else begin
                    rx_state <= RX_IDLE;
                end
            end else begin
                rx_cycle_count <= rx_cycle_count + 16'd1;
            end
        end

        RX_HOLD: begin
            if (!rx_data_valid || rx_data_ready) begin
                rx_state <= RX_IDLE;
            end
        end

        default: begin
            rx_state <= RX_IDLE;
        end
    endcase
end

localparam[2:0] TX_IDLE = 3'd0;
localparam[2:0] TX_START = 3'd1;
localparam[2:0] TX_DATA = 3'd2;
localparam[2:0] TX_STOP = 3'd3;

reg[2:0] tx_state = TX_IDLE;
reg[15:0] tx_cycle_count = 16'd0;
reg[2:0] tx_bit_count = 3'd0;
reg[7:0] tx_shift = 8'd0;
reg tx_reg = 1'b1;

assign tx_pin = tx_reg;

always @(posedge clk) begin
    case (tx_state)
        TX_IDLE: begin
            tx_reg <= 1'b1;
            tx_cycle_count <= 16'd0;
            tx_bit_count <= 3'd0;
            tx_data_ready <= 1'b1;
            if (tx_data_valid) begin
                tx_shift <= tx_data;
                tx_data_ready <= 1'b0;
                tx_reg <= 1'b0;
                tx_state <= TX_START;
            end
        end

        TX_START: begin
            tx_data_ready <= 1'b0;
            tx_reg <= 1'b0;
            if (tx_cycle_count == BAUD_CYCLES - 16'd1) begin
                tx_cycle_count <= 16'd0;
                tx_state <= TX_DATA;
            end else begin
                tx_cycle_count <= tx_cycle_count + 16'd1;
            end
        end

        TX_DATA: begin
            tx_data_ready <= 1'b0;
            tx_reg <= tx_shift[tx_bit_count];
            if (tx_cycle_count == BAUD_CYCLES - 16'd1) begin
                tx_cycle_count <= 16'd0;
                if (tx_bit_count == 3'd7) begin
                    tx_bit_count <= 3'd0;
                    tx_state <= TX_STOP;
                end else begin
                    tx_bit_count <= tx_bit_count + 3'd1;
                end
            end else begin
                tx_cycle_count <= tx_cycle_count + 16'd1;
            end
        end

        TX_STOP: begin
            tx_data_ready <= 1'b0;
            tx_reg <= 1'b1;
            if (tx_cycle_count == BAUD_CYCLES - 16'd1) begin
                tx_cycle_count <= 16'd0;
                tx_data_ready <= 1'b1;
                tx_state <= TX_IDLE;
            end else begin
                tx_cycle_count <= tx_cycle_count + 16'd1;
            end
        end

        default: begin
            tx_state <= TX_IDLE;
        end
    endcase
end

endmodule
