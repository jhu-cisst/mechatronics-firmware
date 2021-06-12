/*******************************************************************************    
 *
 * Copyright(C) 2017 Johns Hopkins University
 *
 * Module:  CtrlUart
 *
 * Purpose: This module manages the RS232 communication to the DS2480B 
 *          from parallel data. 
 *
 * Revision history
 *     08/09/17    Jie Ying Wu         Initial revision
 */

module ds_CtrlUart 
(
	// Control signals signals 
	input  wire       clk,         // 5 MHz clock input
    input  wire       reset,       // global reset
    input  wire       pwr_cycle,   // power cycle at 4800 bps
	
	output wire       ser_out,     // serial data out
    input  wire [7:0] tx_data,     // parallel data to transmit
    input  wire       new_tx_data, // load new transmit data
    output wire       tx_busy,     // busy transmitting data

    input  wire       ser_in,      // serial data in
    output wire [7:0] rx_data,     // parallel data in
    output wire       new_rx_data  // new received data to load
);

// Internal variables
wire clk9600;
wire clk4800;
wire baud_clk; 

// Power cycle requires 4800 Hz while otherwise, communicate at 9600 Hz
assign baud_clk = pwr_cycle ? clk4800 : clk9600;

// Generate clock frequencies for uart communication
ds_GenBaud baud(
    .clk(clk), 
    .reset(reset),
    .clk9600(clk9600),
    .clk4800(clk4800) 
);
// Receive RS232 stream into parallel data
ds_UartRx rx(
	.clk(baud_clk), 
    .reset(reset),
    .ser_in(ser_in), 
	.rx_data(rx_data), 
    .new_rx_data(new_rx_data) 
);
// Transmit RS232 stream from parallel data
ds_UartTx tx(
	.clk(baud_clk), 
    .reset(reset),
    .tx_data(tx_data), 
    .new_tx_data(new_tx_data), 
	.ser_out(ser_out), 
    .tx_busy(tx_busy) 
);

endmodule
