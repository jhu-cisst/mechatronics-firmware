////////////////////////////////////////
// Driver for WS2811-based LED strips //
////////////////////////////////////////

module ws2811
  #(
    parameter NUM_LEDS          = 4,
    parameter SYSTEM_CLOCK      = 100_000_000
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
         value = value-1;
         for (log2=0; value>0; log2=log2+1)
           value = value>>1;
      end
   endfunction

   localparam integer LED_ADDRESS_WIDTH = log2(NUM_LEDS);
   localparam integer CYCLE_COUNT         = SYSTEM_CLOCK / 800000;
   // Match the upstream real-to-integer round-to-nearest behavior.
   localparam integer H0_CYCLE_COUNT      = (24 * CYCLE_COUNT + 50) / 100;
   localparam integer H1_CYCLE_COUNT      = (76 * CYCLE_COUNT + 50) / 100;
   localparam integer CLOCK_DIV_WIDTH     = log2(CYCLE_COUNT);
   localparam integer RESET_COUNT         = 250 * CYCLE_COUNT;
   localparam integer RESET_COUNTER_WIDTH = log2(RESET_COUNT);

   reg [CLOCK_DIV_WIDTH-1:0]             clock_div;
   reg [RESET_COUNTER_WIDTH-1:0]         reset_counter;

   localparam STATE_RESET    = 3'd0;
   localparam STATE_LATCH    = 3'd1;
   localparam STATE_PRE      = 3'd2;
   localparam STATE_TRANSMIT = 3'd3;
   localparam STATE_POST     = 3'd4;
   reg [2:0] state;

   localparam COLOR_G = 2'd0;
   localparam COLOR_R = 2'd1;
   localparam COLOR_B = 2'd2;
   reg [1:0] color;
   reg [7:0] red;
   reg [7:0] green;
   reg [7:0] blue;
   reg [7:0] current_byte;
   reg [2:0] current_bit;

   wire reset_almost_done;
   wire led_almost_done;

   assign reset_almost_done = (state == STATE_RESET) &&
                              (reset_counter == RESET_COUNT-1);
   assign led_almost_done = (state == STATE_POST) &&
                            (color == COLOR_B) &&
                            (current_bit == 0) && (address != 0);
   assign data_request = reset_almost_done || led_almost_done;
   assign new_address = (state == STATE_PRE) && (current_bit == 7);

   initial begin
      address <= 0;
      state <= STATE_RESET;
      DO <= 0;
      reset_counter <= 0;
      color <= COLOR_G;
      current_bit <= 7;
   end

   always @(posedge clk) begin
      case (state)
        STATE_RESET: begin
           DO <= 0;
           if (reset_counter == RESET_COUNT-1) begin
              reset_counter <= 0;
              state <= STATE_LATCH;
           end else begin
              reset_counter <= reset_counter + 1'b1;
           end
        end
        STATE_LATCH: begin
           red <= red_in;
           blue <= blue_in;
           address <= address + 1'b1;
           color <= COLOR_G;
           current_byte <= green_in;
           current_bit <= 7;
           state <= STATE_PRE;
        end
        STATE_PRE: begin
           clock_div <= 0;
           DO <= 1;
           state <= STATE_TRANSMIT;
        end
        STATE_TRANSMIT: begin
           if ((current_byte[7] == 0) &&
               (clock_div >= H0_CYCLE_COUNT)) begin
              DO <= 0;
           end else if ((current_byte[7] == 1) &&
                        (clock_div >= H1_CYCLE_COUNT)) begin
              DO <= 0;
           end
           if (clock_div == CYCLE_COUNT-1) begin
              state <= STATE_POST;
           end else begin
              clock_div <= clock_div + 1'b1;
           end
        end
        STATE_POST: begin
           if (current_bit != 0) begin
              current_byte <= {current_byte[6:0], 1'b0};
              case (current_bit)
                7: current_bit <= 6;
                6: current_bit <= 5;
                5: current_bit <= 4;
                4: current_bit <= 3;
                3: current_bit <= 2;
                2: current_bit <= 1;
                1: current_bit <= 0;
              endcase
              state <= STATE_PRE;
           end else begin
              case (color)
                COLOR_G: begin
                   color <= COLOR_R;
                   current_byte <= red;
                   current_bit <= 7;
                   state <= STATE_PRE;
                end
                COLOR_R: begin
                   color <= COLOR_B;
                   current_byte <= blue;
                   current_bit <= 7;
                   state <= STATE_PRE;
                end
                COLOR_B: begin
                   if (address == 0)
                     state <= STATE_RESET;
                   else
                     state <= STATE_LATCH;
                end
              endcase
           end
        end
      endcase
   end
endmodule
