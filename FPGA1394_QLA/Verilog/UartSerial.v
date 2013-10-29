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
//  UART TX Module DEBUG
//    1-bit Start 8-bit Data 0-bit Disparity 1-bit Stop 
//    Baud = 115200 
// --------------------------------------------- 

module UartTxDebug (
	input wire Clk40m,      // 40 mHz clk
	input wire[1:32] IO1,   // IO1
	input wire[1:38] IO2,   // IO2
	input wire[3:0] Addr,   // wenid
	output reg TxD          // UART tx 
	);

// -- reg for UartTx -------
reg[7:0] TxReg;    
reg[7:0] TxState;    // state counter
reg[7:0] Mux;        // Mux selector for different device/register
reg[3:0] Baud;  // baud counter
wire BaudClk;        // BaudClk (115200 x 8)


// -- Baud Clk Generator -------
wire clk_29_pll;
wire clk_14_pll;

UartClkGen clkgen(
	.IN40(Clk40m),
	.OUT14(clk_14_pll),
	.OUT29(clk_29_pll)
	);

// -- Generate BaudClk
always @(posedge clk_29_pll) 
begin
	Baud <= Baud + 1'b1;
end
// buffer the baud rate divider
BUFG clkbaudclk(.I(Baud[3]), .O(BaudClk));



// output state machine.... this needs to much more work that it is embarassing
always @(posedge BaudClk)
begin
    // update TxD register every 16 clocks; upper 4 bits determines tx state
    //   (whether to send start, data, or stop bit
    if (TxState[3:0] == 4'h2) begin
        if      (TxState[7:4]==4'h0) TxD <= 1'b0;       // start bit
        else if (TxState[7:4]==4'h1) TxD <= TxReg[0];
        else if (TxState[7:4]==4'h2) TxD <= TxReg[1];
        else if (TxState[7:4]==4'h3) TxD <= TxReg[2];
        else if (TxState[7:4]==4'h4) TxD <= TxReg[3];
        else if (TxState[7:4]==4'h5) TxD <= TxReg[4];
        else if (TxState[7:4]==4'h6) TxD <= TxReg[5];
        else if (TxState[7:4]==4'h7) TxD <= TxReg[6];
        else if (TxState[7:4]==4'h8) TxD <= TxReg[7];
        else                         TxD <= 1'b1;       // stop bit, then idle bus
    end

    // after each transmitted byte (0xA0 clocks), reset counter, update TxReg
    // with next data byte, and update Mux (reset if overflowed)
    if (TxState < 8'hA0)
        TxState <= TxState + 1'b1;
    else begin
        TxState <= 8'h00;
        if (Mux == 8'h4D) begin
            Mux   <= 8'h00;
            TxReg <= 8'h0D;    // ASCII Carriage return
        end
        else begin
            Mux   <= Mux + 1'b1;
            TxReg <= (Mux==8'h00) ? ({7'h18,~Addr[3]})
                   : (Mux==8'h01) ? ({7'h18,~Addr[2]})
                   : (Mux==8'h02) ? ({7'h18,~Addr[1]})
                   : (Mux==8'h03) ? ({7'h18,~Addr[0]})
                   : (Mux==8'h04) ? ( 8'h3A)              // ASCII colon

                   : (Mux==8'h05) ? ({7'h18,~IO1[1]})
                   : (Mux==8'h06) ? ({7'h18,~IO1[2]})
                   : (Mux==8'h07) ? ({7'h18,~IO1[3]})
                   : (Mux==8'h08) ? ({7'h18,~IO1[4]})
                   : (Mux==8'h09) ? ({7'h18,~IO1[5]})
                   : (Mux==8'h0A) ? ({7'h18,~IO1[6]})
                   : (Mux==8'h0B) ? ({7'h18,~IO1[7]})
                   : (Mux==8'h0C) ? ({7'h18,~IO1[8]})
                   : (Mux==8'h0D) ? ({7'h18,~IO1[9]})
                   : (Mux==8'h0E) ? ({7'h18,~IO1[10]})
                   : (Mux==8'h0F) ? ({7'h18,~IO1[11]})
                   : (Mux==8'h10) ? ({7'h18,~IO1[12]})
                   : (Mux==8'h11) ? ({7'h18,~IO1[13]})
                   : (Mux==8'h12) ? ({7'h18,~IO1[14]})
                   : (Mux==8'h13) ? ({7'h18,~IO1[15]})
                   : (Mux==8'h14) ? ({7'h18,~IO1[16]})
                   : (Mux==8'h15) ? ({7'h18,~IO1[17]})
                   : (Mux==8'h16) ? ({7'h18,~IO1[18]})
                   : (Mux==8'h17) ? ({7'h18,~IO1[19]})
                   : (Mux==8'h18) ? ({7'h18,~IO1[20]})
                   : (Mux==8'h19) ? ({7'h18,~IO1[21]})
                   : (Mux==8'h1A) ? ({7'h18,~IO1[22]})
                   : (Mux==8'h1B) ? ({7'h18,~IO1[23]})
                   : (Mux==8'h1C) ? ({7'h18,~IO1[24]})
                   : (Mux==8'h1D) ? ({7'h18,~IO1[25]})
                   : (Mux==8'h1E) ? ({7'h18,~IO1[26]})
                   : (Mux==8'h1F) ? ({7'h18,~IO1[27]})
                   : (Mux==8'h20) ? ({7'h18,~IO1[28]})
                   : (Mux==8'h21) ? ({7'h18,~IO1[29]})
                   : (Mux==8'h22) ? ({7'h18,~IO1[30]})
                   : (Mux==8'h23) ? ({7'h18,~IO1[31]})
                   : (Mux==8'h24) ? ({7'h18,~IO1[32]})
                   : (Mux==8'h25) ? ( 8'h3A)              // ASCII colon

                   : (Mux==8'h26) ? ({7'h18,~IO2[1]})
                   : (Mux==8'h27) ? ({7'h18,~IO2[2]})
                   : (Mux==8'h28) ? ({7'h18,~IO2[3]})
                   : (Mux==8'h29) ? ({7'h18,~IO2[4]})
                   : (Mux==8'h2A) ? ({7'h18,~IO2[5]})
                   : (Mux==8'h2B) ? ({7'h18,~IO2[6]})
                   : (Mux==8'h2C) ? ({7'h18,~IO2[7]})
                   : (Mux==8'h2D) ? ({7'h18,~IO2[8]})
                   : (Mux==8'h2E) ? ({7'h18,~IO2[9]})
                   : (Mux==8'h2F) ? ({7'h18,~IO2[10]})
                   : (Mux==8'h30) ? ({7'h18,~IO2[11]})
                   : (Mux==8'h31) ? ({7'h18,~IO2[12]})
                   : (Mux==8'h32) ? ({7'h18,~IO2[13]})
                   : (Mux==8'h33) ? ({7'h18,~IO2[14]})
                   : (Mux==8'h34) ? ({7'h18,~IO2[15]})
                   : (Mux==8'h35) ? ({7'h18,~IO2[16]})
                   : (Mux==8'h36) ? ({7'h18,~IO2[17]})
                   : (Mux==8'h37) ? ({7'h18,~IO2[18]})
                   : (Mux==8'h38) ? ({7'h18,~IO2[19]})
                   : (Mux==8'h39) ? ({7'h18,~IO2[20]})
                   : (Mux==8'h3A) ? ({7'h18,~IO2[21]})
                   : (Mux==8'h3B) ? ({7'h18,~IO2[22]})
                   : (Mux==8'h3C) ? ({7'h18,~IO2[23]})
                   : (Mux==8'h3D) ? ({7'h18,~IO2[24]})
                   : (Mux==8'h3E) ? ({7'h18,~IO2[25]})
                   : (Mux==8'h3F) ? ({7'h18,~IO2[26]})
                   : (Mux==8'h40) ? ({7'h18,~IO2[27]})
                   : (Mux==8'h41) ? ({7'h18,~IO2[28]})
                   : (Mux==8'h42) ? ({7'h18,~IO2[29]})
                   : (Mux==8'h43) ? ({7'h18,~IO2[30]})
                   : (Mux==8'h44) ? ({7'h18,~IO2[31]})
                   : (Mux==8'h45) ? ({7'h18,~IO2[32]})
                   : (Mux==8'h46) ? ({7'h18,~IO2[33]})
                   : (Mux==8'h47) ? ({7'h18,~IO2[34]})
                   : (Mux==8'h48) ? ({7'h18,~IO2[35]})
                   : (Mux==8'h49) ? ({7'h18,~IO2[36]})
                   : (Mux==8'h4A) ? ({7'h18,~IO2[37]})
                   : (Mux==8'h4B) ? ({7'h18,~IO2[38]})
                   : (Mux==8'h4C) ? ( 8'h3A)              // ASCII colon
                   : 8'h3F;                               // ASCII question mark
        end
    end
end

endmodule  // UartTx 



// -----------------------------------------------------------------------------
//  UART Control Module 
//    - 1 Rx Module + 1 Tx Module 
//    - Logical 
//  
//  The rest rx_rdata, rx_wdata, rx_addr will remain the same as 1394 interface. 
//  UART Protocal 
//    - 1 byte: 3-bit cmd + 5-bit data length
//    - 2 byte: 8-bit addr 
//    ------ END READ -------
//    - 3-n write byte
//   
//  Command Table 
//    000: quadlet read
//    001: block read
//    010: quadlet write
//    011: block write
//    100: start UART control
//    101: close UART control 
//  
//  NOTE: by default, system is under 1394 mode. UART mode needs to be switch
//        on/off manually using start/stop UART control cmd 
// 
//  Examples: 
// ------------------------------------------------------------------------------  

module CtrlUart (
  input  wire clk40m,
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


//-------- Clock -----------
// clock module
wire clk_14_pll;
wire clk_29_pll;

UartClkGen clkgen(
  .IN40(clk40m),
  .OUT14(clk_14_pll),
  .OUT29(clk_29_pll)
  );

// -- Generate BaudClk
reg[3:0] Baud;
wire BaudClk;
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
  .tx_busy(tx_busy)
  );

// rx module 
UartRx uart_rx(
  .clkuart(BaudClk),
  .reset(reset),
  .RxD(RxD),
  .rx_data(rx_data),
  .rx_int(rx_int)
  );


// ----------- Control Logic ------------
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
  output reg tx_busy           // HIGH when tranxmitting 
  );

reg[7:0] tx_counter;    // tx time counter
reg[7:0] tx_reg;     // reg to latch tx_data 

// tx_counter 
//    counts from 0x00 -> 0x97, then stop
//    when tx_trig, clear and start counting
// always @(posedge(clkuart) or negedge(reset)) begin
//     if (reset == 0) begin
//         tx_counter <= 8'h97;    // stop counter
//         tx_busy <= 1'b0;  
//     end
//     else if (tx_trig) begin
//         tx_counter <= 8'h00;   // start counting
//         tx_reg <= tx_data;     // latch data
//         tx_busy <= 1'b1;       // set tx_busy
//     end
//     else if (tx_counter <= 8'h97) begin
//         tx_counter <= tx_counter + 1'b1;
//     end
//     else if (tx_counter == 8'h97) begin
//         tx_busy <= 1'b0;       // clear tx_busy
//     end
// end

// transmit data out
always @(posedge(clkuart) or negedge(reset)) begin
    if (reset == 0) begin
        tx_counter <= 8'd0;
        tx_reg <= 8'd67;
    end
    else begin
        tx_counter <= tx_counter + 1'b1;
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

endmodule


// ---------------------------------------------  
//  UART Rx Module 
//   - step 1: receive and connect to chipscope 
//   ????? DO I REALLY care if the rx is busy ? 
// ---------------------------------------------  
module UartRx (
  input  wire clkuart,           // uart clock 1.8432 MHz (ideal clk)
  input  wire reset,             // reset
  input  wire RxD,               // UART Rx Data Pin 
  output reg[7:0] rx_data,       // rx data, hold till next data byte
  output reg rx_int              // rx interrupt, rx received
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

always @(posedge(clkuart) or negedge(reset)) begin
    if (reset == 0) begin
        rx_counter <= 8'h97;    // stop rx_counter
        rx_int <= 1'b0;         
    end
    else if (rxd_negedge) begin
        rx_counter <= 8'h00;    // start rx counter
        rx_int <= 1'b0; 
    end
    else if (rx_counter <= 8'h97) begin
        rx_counter <= rx_counter + 1'b1;
    end
    else if (rx_counter == 8'h97) begin
        rx_counter <= rx_counter + 1'b1;
        rx_int <= 1'b1;        // set 
    end
    else if (rx_counter == 8'h98) begin
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

endmodule





// ---------------------------------------------  
//  UART BAUD Clk Generator 
// ---------------------------------------------  
module UartClkGen (
	input  IN40,    // 40.000 MHz Clock In
	output OUT14,   // 14.476 MHz Clock signal (PLL Generated)
	output OUT29    // 29.491 MHz Clock signal (PLL Generated)
	);

wire clkfb;    // Click feedback
wire _out29;   // 29.491 MHz Clock signal
wire _out14;   // 14.746 MHz Clock signal
wire _ref40;   // 40.000 MHz Clock reference (Input)

//-----------------------------------------------------------------------------
//
// PLL Primitive
//
//   The "Base PLL" primitive has a PLL, a feedback path and 6 clock outputs,
//   each with its own 7 bit divider to generate 6 different output frequencies
//   that are integer division of the PLL frequency. The "Base" PLL provides
//   basic PLL/Clock-Generation capabilities. For detailed information, see
//   Chapter 3, "General Usage Description" section of the Spartan-6 FPGA 
//   Clocking Resource, Xilinx Document # UG382.
//
//   The PLL has a dedicated Feedback Output and Feedback Input. This output
//   must be connected to this input outside the primitive. For applications
//   where the phase relationship between the reference input and the output
//   clock is not critical (present application), this connection can be made
//   in the module. Where this phase relationship is critical, the feedback
//   path can include routing on the FPGA or even off-chip connections.
//
//   The Input/Output of the PLL module are ordinary signals, NOT clocks.
//   These signals must be routed through specialized buffers in order for
//   them to be connected to the global clock buses and be used as clocks.
//
//-----------------------------------------------------------------------------
PLL_BASE # (.BANDWIDTH         ("OPTIMIZED"),
	.CLK_FEEDBACK      ("CLKFBOUT"),
	.COMPENSATION      ("INTERNAL"),
	.DIVCLK_DIVIDE     (1),
            .CLKFBOUT_MULT     (14),        // VCO = 40.000* 14/1 = 560.0000MHz
            .CLKFBOUT_PHASE    (0.000),
            .CLKOUT0_DIVIDE    (  19  ),    // CLK0 = 560.00/19 = 29.474
            .CLKOUT0_PHASE     (  0.00),
            .CLKOUT0_DUTY_CYCLE(  0.50),
            .CLKOUT1_DIVIDE    (  38  ),    // CLK1 = 560.00/38 = 14.737
            .CLKOUT1_PHASE     (  0.00),
            .CLKOUT1_DUTY_CYCLE(  0.50),
            .CLKOUT2_DIVIDE    (  32  ),    // Unused Output. The divider still needs a
            .CLKOUT3_DIVIDE    (  32  ),    //    reasonable value because the clock is
            .CLKOUT4_DIVIDE    (  32  ),    //    still being generated even if unconnected.
            .CLKOUT5_DIVIDE    (  32  ))    //
_PLL1 (     .CLKFBOUT          (clkfb),     // The FB-Out is connected to FB-In inside
            .CLKFBIN           (clkfb),     //    the module.
            .CLKIN             (_ref40),    // 40.00 MHz reference clock
            .CLKOUT0           (_out29),    // 29.49 MHz Output signal
            .CLKOUT1           (_out14),    // 14.75 MHz Output signal
            .CLKOUT2           (),          // Unused outputs
            .CLKOUT3           (),          //
            .CLKOUT4           (),          //
            .CLKOUT5           (),          //
            .LOCKED            (),          //
            .RST               (1'b0));     // Reset Disable



//-----------------------------------------------------------------------------
//
// Input/Output Buffering
//
//   The Inputs/Outputs of the PLL module are regular signals, NOT clocks.
//
//   The output signals have to connected to BUFG buffers, which are among the
//   specialized primitives that can drive the global clock lines.
//
//   Similarly, an external reference clock connected to a clock pin on the
//   FPGA needs to be routed through an IBUFG primitive to get an ordinary
//   signal that can be used by the PLL Module
//
//-----------------------------------------------------------------------------
BUFG clk_buf1 (.I(IN40),    .O(_ref40));
BUFG  clk_buf2 (.I(_out29),  .O(OUT29 ));
BUFG  clk_buf3 (.I(_out14),  .O(OUT14 ));

endmodule  // UartClkGen 

