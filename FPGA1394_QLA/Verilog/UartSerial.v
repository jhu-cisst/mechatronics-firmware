/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2013 ERC CISST, Johns Hopkins University.
 *
 * Module: UART interface for QLA board
 *
 * Purpose: Modules for UART communication
 * 
 * Revision history
 *     10/26/13    Zihan Chen    Initial revision
 */
 
 /**************************************************************
  * NOTE:
  *  - UART: Universal Asynchronous Receive & Transmit
  *  - Hardware Connection
  *       / TX  ----->    RX \
  *    PC                      FPGA 
  *       \ RX  <-----    TX / 
  *    
  *    Chip: USB -> COM  
  *    PC: /dev/ttyUSBx   
  *
  *  - Testing: 
  *     - picocom -b 115200 /dev/ttyUSB0 
  **/

// ---------------------------------------------  
//    1-bit Start 8-bit Data 0-bit Disparity 1-bit Stop 
//    Baud = 115200 
// --------------------------------------------- 


// -----------------------------------------------------------------------------
//  UART Control Module 
//    - 1 Rx Module + 1 Tx Module 
//    - 1 clock module
//    - echo logic  
// ------------------------------------------------------------------------------  

module CtrlUart (
    input  wire clk_14_pll,
    input  wire clk_29_pll,
    input  wire reset,
    input  wire RxD,
    output wire TxD    
);

    // ------- Reg -------------
    reg[7:0] tx_data;     // data send via UartTx
    wire[7:0] rx_data;     // data received via UartRx
    reg tx_trig;
    wire tx_busy;         // wire for tx_busy signal
    wire rx_int;          // rx interrupt
    wire uart_mode;

    reg[3:0] Baud;
    wire BaudClk;

    // processor buffer
    reg[31:0] procBuffer[63:0];
    reg[5:0] procRdInd;
    reg[5:0] procWtInd;    

//-----------------------------------------------------
// hardware description
// ----------------------------------------------------

// -- Generate BaudClk
always @(posedge clk_29_pll) 
begin
  Baud <= Baud + 1'b1;
end
// buffer the baud rate divider
BUFG clkbaudclk(.I(Baud[3]), .O(BaudClk));

//---------- Tx & Rx Module --------
// tx module
UartTx uart_tx(
  .clkuart(BaudClk),
  .reset(reset),
  .tx_data(tx_data),
  .tx_trig(tx_trig),
  .TxD(TxD),
  .tx_busy(tx_busy),
  .control(control_uart_tx)
  );

// rx module 
UartRx uart_rx(
  .clkuart(BaudClk),
  .reset(reset),
  .RxD(RxD),
  .rx_data(rx_data),
  .rx_int(rx_int),
  .control(control_uart_rx)
  );


// ----------- Control Logic ------------
// echo interface
always @(posedge(BaudClk) or negedge(reset)) begin
   if (reset == 0) begin
        tx_trig <= 1'b0;  
   end
   else if (rx_int) begin
       tx_trig <= 1'b1;
       tx_data <= rx_data;
   end
   else if (tx_trig == 1'b1) begin
       tx_trig <= 1'b0;   
   end
end

endmodule





// ---------------------------------------------
// NOTE on UART data packet 
//   - This is a limited implementation 
//   - Data format
//     - 1 start bit 
//     - 8 data bit 
//     - 0 odd/even parity bit 
//     - 1 stop bit
//   - Baud rate = 115200 bps
// ---------------------------------------------


// ---------------------------------------------  
//  UART Tx Module
//     - Assumption on clkuart 
//        - 115200 x 256 / 16 = 29.491 MHz / 16 = 1.8432 MHz  
//        - input clk should be close enough 
// ---------------------------------------------  
module UartTx (
    input  wire clkuart,          // uart clock 1.8432 MHz (ideal clk)
    input  wire reset,            // reset
    input  wire[7:0] tx_data,     // tx data
    input  wire tx_trig,          // trigger to start

    output reg  TxD,              // UART Tx Data Pin
    output reg tx_busy,           // HIGH when tranxmitting 

    input wire[35:0] control
);

reg[7:0] tx_counter;    // tx time counter
reg[7:0] tx_reg;     // reg to latch tx_data 

// tx_counter 
//    counts from 0x00 -> 0x97, then stop
//    when tx_trig, clear and start counting
 always @(posedge(clkuart) or negedge(reset)) begin
     if (reset == 0) begin
         tx_counter <= 8'h97;    // stop counter
         tx_busy <= 1'b0;  
     end
     else if (tx_trig) begin
         tx_counter <= 8'h00;   // start counting
         tx_reg <= tx_data;     // latch data
         tx_busy <= 1'b1;       // set tx_busy
     end
     else if (tx_counter < 8'h97) begin
         tx_counter <= tx_counter + 1'b1;
     end
     else if (tx_counter == 8'h97) begin
         tx_busy <= 1'b0;       // clear tx_busy
     end
 end


// transmit data out
always @(posedge(clkuart) or negedge(reset)) begin
    if (reset == 0) begin
        TxD <= 1'b1;
    end
    else if (tx_counter[3:0] == 4'h2) begin
        if      (tx_counter[7:4]==4'h0) TxD <= 1'b0;       // start bit
        else if (tx_counter[7:4]==4'h1) TxD <= tx_reg[0];  // data 
        else if (tx_counter[7:4]==4'h2) TxD <= tx_reg[1];  
        else if (tx_counter[7:4]==4'h3) TxD <= tx_reg[2];  
        else if (tx_counter[7:4]==4'h4) TxD <= tx_reg[3];  
        else if (tx_counter[7:4]==4'h5) TxD <= tx_reg[4];  
        else if (tx_counter[7:4]==4'h6) TxD <= tx_reg[5];  
        else if (tx_counter[7:4]==4'h7) TxD <= tx_reg[6];
        else if (tx_counter[7:4]==4'h8) TxD <= tx_reg[7];  
        else                            TxD <= 1'b1;       // stop bit, then idle bus 
    end
end


wire[2:0] tx_status;
assign tx_status = {TxD, tx_busy, tx_trig};

endmodule




// -----------------------------------------------------------------------------  
//  UART Rx Module 
//   - step 1: receive and connect to chipscope 
//   ????? DO I REALLY care if the rx is busy ? 
// -----------------------------------------------------------------------------  
module UartRx (
    input  wire clkuart,           // uart clock 1.8432 MHz (ideal clk)
    input  wire reset,             // reset
    input  wire RxD,               // UART Rx Data Pin 
    output reg[7:0] rx_data,       // rx data, hold till next data byte
    output reg rx_int,             // rx interrupt, rx received

    input wire[35:0] control
);

// ---- Receive Start Detection ---------------
reg rxd0, rxd1, rxd2, rxd3;      // RxD cache for filtering
wire rxd_negedge;  

// if reset sets rxdx to 1, it may false trigger
always @(posedge(clkuart) or negedge(reset)) begin
    if (reset == 0) begin
        rxd0 <= 1'b0; rxd1 <= 1'b0; 
        rxd2 <= 1'b0; rxd3 <= 1'b0;   
    end
    else begin
        rxd0 <= RxD; rxd1 <= rxd0;
        rxd2 <= rxd1; rxd3 <= rxd2;
    end
end

// set rxd_negedge HIGH for 1 clk cycle, if neg edge
assign rxd_negedge = (rxd3 & rxd2 & ~rxd1 & ~rxd0);  

// ----- Receive counter -------------
reg[7:0] rx_counter;    // rx time counter
reg rx_recv;            // uart_rx receiving 

always @(posedge(clkuart) or negedge(reset)) begin
    if (reset == 0) begin
        rx_counter <= 8'h97;    // stop rx_counter
        rx_int <= 1'b0;
        rx_recv <= 1'b0;
    end
    else if (rxd_negedge && ~rx_recv) begin
        rx_counter <= 8'h00;    // start rx counter
        rx_recv <= 1'b1;
        rx_int <= 1'b0;
    end
    else if (rx_counter < 8'h97) begin
        rx_counter <= rx_counter + 1'b1;
    end
    else if (rx_counter == 8'h97) begin
        rx_counter <= rx_counter + 1'b1;
        rx_int <= 1'b1;
    end
    else if (rx_counter == 8'h98) begin
        rx_recv <= 1'b0;
        rx_int <= 1'b0;        // clear 
    end
end

// ----- Latch data --------------------
reg[7:0] rx_reg;        // reg to hold temp rx value

always @(posedge(clkuart) or negedge(reset)) begin
    if (reset == 0) begin
        rx_reg <= 8'h00;        // clear tmp rx_reg
    end
    else if (rx_counter[3:0] == 4'h2) begin                // start bit nothing
        if      (rx_counter[7:4]==4'h1) rx_reg[0] <= RxD;  // data bit 0
        else if (rx_counter[7:4]==4'h2) rx_reg[1] <= RxD;  
        else if (rx_counter[7:4]==4'h3) rx_reg[2] <= RxD;  
        else if (rx_counter[7:4]==4'h4) rx_reg[3] <= RxD;  
        else if (rx_counter[7:4]==4'h5) rx_reg[4] <= RxD;  
        else if (rx_counter[7:4]==4'h6) rx_reg[5] <= RxD;  
        else if (rx_counter[7:4]==4'h7) rx_reg[6] <= RxD;  // data bit 7
        else if (rx_counter[7:4]==4'h8) rx_data <= rx_reg; // latch data to rx_data
    end
end


wire[2:0] rx_status;
assign rx_status = {RxD, rxd_negedge, rx_int};

endmodule
