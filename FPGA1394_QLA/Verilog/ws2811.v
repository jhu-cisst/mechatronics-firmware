/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/***********************************************************************************
 *
 * This module implements a serial interface to a set of LEDs.
 */

module ws2811
  #(
    parameter NUM_LEDS     = 7,
    parameter SYSTEM_CLOCK = 49_152_000
    )
   (
    input                              clk,
    output                             data_request,
    output                             new_address,
    output reg [LED_ADDRESS_WIDTH-1:0] address,
    input [7:0]                        red_in,
    input [7:0]                        green_in,
    input [7:0]                        blue_in,
    output reg                         DO
    );

   function integer log2;
      input integer value;
      begin
         value = value - 1;
         for (log2 = 0; value > 0; log2 = log2 + 1)
           value = value >> 1;
      end
   endfunction

   localparam integer LED_ADDRESS_WIDTH = log2(NUM_LEDS);
   localparam integer BIT_CYCLES        = SYSTEM_CLOCK / 800000;
   localparam integer ZERO_HIGH_CYCLES  = (24 * BIT_CYCLES + 50) / 100;
   localparam integer ONE_HIGH_CYCLES   = (76 * BIT_CYCLES + 50) / 100;
   localparam integer BIT_COUNTER_WIDTH = log2(BIT_CYCLES);
   localparam integer RESET_CYCLES      = 250 * BIT_CYCLES;
   localparam integer RESET_COUNT_WIDTH = log2(RESET_CYCLES);

   localparam [2:0] RESET     = 3'd0;
   localparam [2:0] LOAD_LED  = 3'd1;
   localparam [2:0] START_BIT = 3'd2;
   localparam [2:0] SEND_BIT  = 3'd3;
   localparam [2:0] NEXT_BIT  = 3'd4;

   localparam [1:0] GREEN = 2'd0;
   localparam [1:0] RED   = 2'd1;
   localparam [1:0] BLUE  = 2'd2;

   reg [2:0] state;
   reg [1:0] color;
   reg [2:0] bit_index;
   reg [7:0] shift_reg;
   reg [7:0] red;
   reg [7:0] blue;
   reg [BIT_COUNTER_WIDTH-1:0] bit_counter;
   reg [RESET_COUNT_WIDTH-1:0] reset_counter;

   assign data_request = ((state == RESET) &&
                          (reset_counter == RESET_CYCLES - 1)) ||
                         ((state == NEXT_BIT) && (color == BLUE) &&
                          (bit_index == 0) && (address != 0));
   assign new_address = (state == START_BIT) && (bit_index == 7);

   initial begin
      address <= 0;
      state <= RESET;
      DO <= 0;
      reset_counter <= 0;
      color <= GREEN;
      bit_index <= 7;
   end

   always @(posedge clk) begin
      case (state)
        RESET: begin
           DO <= 0;
           if (reset_counter == RESET_CYCLES - 1) begin
              reset_counter <= 0;
              state <= LOAD_LED;
           end else begin
              reset_counter <= reset_counter + 1'b1;
           end
        end

        LOAD_LED: begin
           red <= red_in;
           blue <= blue_in;
           address <= address + 1'b1;
           color <= GREEN;
           shift_reg <= green_in;
           bit_index <= 7;
           state <= START_BIT;
        end

        START_BIT: begin
           bit_counter <= 0;
           DO <= 1;
           state <= SEND_BIT;
        end

        SEND_BIT: begin
           if (bit_counter >=
               (shift_reg[7] ? ONE_HIGH_CYCLES : ZERO_HIGH_CYCLES))
             DO <= 0;

           if (bit_counter == BIT_CYCLES - 1)
             state <= NEXT_BIT;
           else
             bit_counter <= bit_counter + 1'b1;
        end

        NEXT_BIT: begin
           if (bit_index != 0) begin
              shift_reg <= {shift_reg[6:0], 1'b0};
              bit_index <= bit_index - 3'd1;
              state <= START_BIT;
           end else begin
              case (color)
                GREEN: begin
                   color <= RED;
                   shift_reg <= red;
                   bit_index <= 7;
                   state <= START_BIT;
                end
                RED: begin
                   color <= BLUE;
                   shift_reg <= blue;
                   bit_index <= 7;
                   state <= START_BIT;
                end
                BLUE: begin
                   if (address == 0)
                     state <= RESET;
                   else
                     state <= LOAD_LED;
                end
              endcase
           end
        end
      endcase
   end
endmodule
