/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2018-2021 Johns Hopkins University.
 *
 * Module: DS2505
 *
 * Purpose: Interface to Dallas Semiconductor (Maxim) DS2505 16KB memory via
 *          1-wire interface. The code has been written specific to the DS2505,
 *          but could be generalized to other 1-wire devices. It assumes a
 *          hi-speed bidirectional transceiver, such as the one available in
 *          QLA Rev 1.4+.
 *          The DS2505 chip is used inside da Vinci instruments and contains
 *          useful information such as the instrument name.
 * 
 * Revision history
 *      8/29/18     Peter Kazanzides    Initial revision
 *      6/19/20     Shi Xin Sun         Adding support for DS2480B driver chip
 *      7/09/21     Simon Hao Yang      1-wire / DS2480B options successfully merged
 */

 `include "Constants.v"


module DS2505(
    input  wire clk,                 // input clock (49.152 MHz)
    input  wire[15:0] reg_raddr,     // read address
    input  wire[15:0] reg_waddr,     // write address
    output reg[31:0]  reg_rdata,     // read data (to Firewire)
    input  wire[31:0] reg_wdata,     // write data (from Firewire)
    output wire[31:0] ds_status,     // interface status (to BoardRegs)
    input  wire reg_wen,             // write enable signal

    input  wire rxd,                 // DS2480B Serial interface, UART RxD port
    input  wire dout_cfg_bidir,      // 1 -> bidirectional I/O available
    input  wire ds_data_in,          // 1-wire interface, data in
    output wire ds_data_out,         // 1-wire interface / DS2480B Serial interface, data out / TxD
    output reg ds_dir,               // direction for 1-wire interface (0=input to FPGA, 1=output from FPGA)
    output reg ds_enable             // enables this module to drive the digital I/O line
);

// State machine arguments
localparam[4:0]
    DS_IDLE = 0,
    /////////////////////////////////////////////////
    // Direct 1-wire option starts here
    ////////////////////////////////////////////////
    DS_RESET_BEGIN      = 1,     
    DS_RESET_END        = 2,
    DS_RESET_ACK_WAIT   = 3,
    DS_RESET_ACK_CHECK  = 4,
    DS_RESET_RECOVER    = 5,
    DS_READ_PROM_START  = 6,
    DS_READ_PROM        = 7,
    DS_SET_ADDR_LOW     = 8,
    DS_SET_ADDR_HIGH    = 9,
    DS_WRITE_BYTE       = 10,
    DS_READ_BYTE        = 11,
    /////////////////////////////////////////////////
    // DS2480B option starts here
    ////////////////////////////////////////////////
    DS_MASTER_RESET     = 12,        // Send 00 in 4800 baud to enable master reset and synchronize ds2480b
    DS_PROGRAMMER       = 13,        // DS2480 programmer, configuring DS2480B to read memory
    DS_CHECK_PROGRAMMER = 14,        // Check programmer feedback
    DS_READ_MEM_REQUEST = 15,        // Send 0xFF to request 1 byte memory data
    DS_READ_MEM_START   = 16,        // Read 1 byte memory data
    DS_READ_MEM         = 17;        // Store data into FPGA buffer
    

// Local registers and wires
reg[4:0]    state;                   // state machine
reg[4:0]    next_state;              // keeps track of next state
initial begin
    state = DS_IDLE;
    next_state = DS_IDLE;
end

reg[7:0]    out_byte;                // output byte to write to DS2505
reg[7:0]    in_byte;                 // input byte read from DS2505 or DS2840B
reg[7:0]    family_code;             // family code for DS2505 (0x0B)
reg[16:0]   cnt;                     // counter for timing; TODO: fix mixed use of 16 and 17 bits
reg[7:0]    rise_time;               // measured rise time (for debugging)
initial     rise_time = 8'hff;
reg[1:0]    ds_reset;                // 0=not attempted, 1=success, 2=failed (rise-time), 3=failed (no ack from DS2505)
reg[10:0]   mem_addr;                // memory address for reading
reg[7:0]    num_bytes;               // Number of bytes to read
reg         ds_data_out_1w;          // ds_data_out, data out pin for direct 1-wire option

reg         use_ds2480b;             // DS2480B usage check flag, communicating with software side
reg[7:0]    expected_rxd;            // expected response (from configuration command)
reg[9:0]    tx_data;                 // Transmit byte -- needs to be 10 bits -- could be merged with out_byte later
reg         DS2480B_ok;              // DS2480B configuration successfully done
reg[3:0]    cnt_bit;                 // index into bytes sent/received

wire        ds_reg_wen;              // main quadlet reg interface
assign      ds_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'd0, `REG_DSSTAT}) ? reg_wen : 1'b0;

reg[31:0]   mem_data[0:63];          // Up to 64 quadlets (256 bytes) read from chip, provided via block read

wire[5:0]   ds_blk_raddr;            // memory block read address (0-63)
assign      ds_blk_raddr = reg_raddr[5:0];

// Definitions to use smaller counters
`define     cnt3  cnt[15:13]         // upper 3 bits (range 0-7)
`define     cnt13 cnt[12:0]          // lower 13 bits (range 0-8191)
`define     cnt11 cnt[10:0]          // lower 11 bits (range 0-2047)
`define     cnt8  cnt[7:0]           // lower 8 bits (range 0-255)

// Status register, communication with software side
assign      ds_status[31:24] = family_code;
assign      ds_status[23:16] = use_ds2480b ? in_byte : rise_time;
assign      ds_status[15]    = use_ds2480b;
assign      ds_status[14]    = DS2480B_ok;
assign      ds_status[13]    = (state == DS_IDLE) ? 1'b0 : 1'b1;  // 0 if idle, 1 if busy
assign      ds_status[12]    = 1'd0;
assign      ds_status[8:4]   = state;
assign      ds_status[3]     = dout_cfg_bidir;
assign      ds_status[2:1]   = ds_reset;
assign      ds_status[0]     = ds_enable;

// DS2480B programmer, configure DS2480B to read DS2505 memory data
wire[15:0]  ds_program[0:8];         // Program arguments
reg[3:0]    progCnt;                 // Program counter

assign ds_program[0] = { 8'hC1, 8'h00 };                                      // Reset 1-wire in CMD mode
assign ds_program[1] = { 8'hE1, 8'h00 };                                      // Enter DATA mode
assign ds_program[2] = { 8'hCC, 8'hCC };                                      // Skip ROM check
assign ds_program[3] = { 8'hF0, 8'hF0 };                                      // Read memory command
assign ds_program[4] = { mem_addr[7:0], mem_addr[7:0] };                      // Memory read start addr, upper byte
assign ds_program[5] = { {5'd0, mem_addr[10:8]}, {5'd0, mem_addr[10:8]} };    // Memory read start addr, lower byte 
assign ds_program[6] = { 8'hE3, 8'h00 };                                      // Enter CMD mode
assign ds_program[7] = { 8'hC1, 8'hCD };                                      // Flush & reset DS2480B, 1-wire reset

// Assign DS2480B_ok to 1, may be removed later in both firmware & software
initial DS2480B_ok <= 1'b1;

// UART instantiation
wire        recv_done;          // recv data loading done flag 
wire[7:0]   recv_data;          // recv data buffer
reg         send_en;            // send enable
reg         master_rst;         // send master reset flag
wire        send_done;          // send data load done flag 
wire        ds_data_out_2480;   // TxD for DS2480B serial option, connected to uart_txd in uart_send_2480

UartRx_2480B UartRx_2480B(
    .sys_clk(clk), 
    .uart_rxd(rxd), 
    .uart_data(recv_data),
    .uart_done(recv_done)
);

UartTx_2480B UartTx_2480B(
    .sys_clk(clk), 
    .uart_en(send_en), 
    .uart_din(tx_data),
    .uart_done(send_done),
    .uart_txd(ds_data_out_2480),
    .master_rst(master_rst)
);

assign ds_data_out = use_ds2480b ? ds_data_out_2480 : ds_data_out_1w;  // Use ds_data_out as serial TxD / 1-wire output

// State machine begins
always @(posedge(clk))
begin
    case (state)

    DS_IDLE: begin
       ds_dir <= 1'b0;   // tri-state driver

       // handle block read, data is muxed in top module
       reg_rdata <= mem_data[ds_blk_raddr];

       if (ds_reg_wen && dout_cfg_bidir) begin
          // Write:  bits 1:0
          //           00 -> disable interface (release control of DOUT3)
          //           01 -> enable interface (take control of DOUT3)
          //           10 -> enable, initialize and read first 64 bytes from memory address
          //           11 -> continue reading next 64 bytes
          //         bit 2
          //            0 -> direct 1-wire interface
          //            1 -> interface via DS2480B driver
          //         bit 3
          //            0 -> block read still running
          //            1 -> block read ends
          //         bits 26:16
          //           11-bit address (0-2047 bytes)
          case (reg_wdata[1:0])
            2'b00: ds_enable <= 1'd0;
            2'b01: ds_enable <= 1'd1;
            2'b10: begin
                   ds_enable <= 1'd1;
                   use_ds2480b <= reg_wdata[2];
                   // If using DS2480B, jump to DS2480B configuration.
                   // If using direct 1-wire, reset 1-wire interface.
                   state <= reg_wdata[2] ? DS_MASTER_RESET : DS_RESET_BEGIN;
                   mem_addr <= reg_wdata[26:16];  // 11-bit address (0-2047 bytes)
                   rise_time <= 8'hff;
                   ds_reset <= 2'd0;
                   ds_dir <= 1'b1;                // enable driver
                   ds_data_out_1w <= 1'd0;        // for 1-wire, start reset pulse
                   cnt <= 17'd0;
                   end
            2'b11: begin
                   // ds_enable should already be 1
                   // If using DS2480B, send next 64 0xFF requests and read 64 bytes memory
                   // If using 1-wire, directly read 64 bytes memory.
                   state <= reg_wdata[2] ? DS_READ_MEM_REQUEST : DS_READ_MEM_START;
                   use_ds2480b <= reg_wdata[2];
                   cnt <= 17'd0;
                   end
          endcase
          // all 2048 bytes read over, DS2480B flush & reset
          if (reg_wdata[3] == 1)
             state <= DS_PROGRAMMER;
             progCnt <= 4'd6;
       end
    end

    /////////////////////////////////////////////////////////////////////////////////////////////
    // Direct 1-wire option state machine starts here
    /////////////////////////////////////////////////////////////////////////////////////////////
    DS_RESET_BEGIN: begin
       if (cnt == 16'd30000) begin   // 30,000 counts is about 610 usec
          state <= DS_RESET_END;
          ds_dir <= 1'b0;    // tri-state bi-directional transceiver (input to FPGA)
          cnt <= 16'd0;
       end
       else begin
          cnt <= cnt + 16'd1;
       end
    end

    DS_RESET_END: begin
       // Wait for 1-wire to return to high state. We use a timeout of 5 usec,
       // which is more than enough, unless the pull-up resistor is missing.
       // Note that 5 usec is 246 counts, which fits in 8 bits (255)
       if (ds_data_in == 1'b1) begin
          state <= DS_RESET_ACK_WAIT;
          rise_time <= `cnt8;
          `cnt8 <= 8'd0;
       end
       else if (`cnt8 == 8'd246) begin  // 246 is about 5 usec
          state <= DS_IDLE;
          ds_reset <= 2'd2;   // failed (1-wire did not reach high state)
       end
       else begin
          `cnt8 <= `cnt8 + 8'd1;
       end
    end

    DS_RESET_ACK_WAIT: begin
       // Wait 15-60 usec before checking for low pulse from DS2505
       if (`cnt11 == 11'd1475) begin  // 1,475 counts is about 30 usec
          state <= DS_RESET_ACK_CHECK;
          `cnt11 <= 11'd0;
       end
       else begin
          `cnt11 <= `cnt11 + 11'd1;
       end
    end

    DS_RESET_ACK_CHECK: begin
       // Check for low pulse from DS2505, with timeout of 300 usec
       // (tPDH+tPDL) from when high state was detected.
       if (ds_data_in == 1'b0) begin
          state <= DS_RESET_RECOVER;
          ds_reset <= 2'd1;    // success
          cnt <= 16'd0;
       end
       else if (cnt == 16'd14750) begin  // 14,750 counts is about 300 usec
          state <= DS_IDLE;
          ds_reset <= 2'd3;    // failed (no ack pulse from DS2505)
          cnt <= 16'd0;
       end
       else begin
          cnt <= cnt + 16'd1;
       end
    end

    DS_RESET_RECOVER: begin
       // Wait at least 480 usec from when high pulse detected
       if (ds_data_in == 1'b1) begin
          cnt <= cnt + 16'd1;
          if (cnt == 16'd24576) begin // 24,576 counts is about 500 usec
             state <= DS_WRITE_BYTE;
             out_byte <= 8'h33;   // Read PROM command
             next_state <= DS_READ_PROM_START;
             cnt <= 16'd0;
          end
       end
    end

    DS_READ_PROM_START: begin
       state <= DS_READ_BYTE;
       next_state <= DS_READ_PROM;
       num_bytes[2:0] <= 3'd0;
    end

    DS_READ_PROM: begin
       state <= DS_READ_BYTE;
       next_state <= DS_READ_PROM;
       num_bytes[2:0] <= num_bytes[2:0] + 3'd1;
       if (num_bytes[2:0] == 3'd0) begin
          family_code <= in_byte;
       end
       else if (num_bytes[2:0] == 3'd7) begin
          state <= DS_WRITE_BYTE;
          out_byte <= 8'hF0;   // Read Memory command
          next_state <= DS_SET_ADDR_LOW;
          num_bytes[2:0] <= 3'd0;
       end
    end

    DS_SET_ADDR_LOW: begin
       out_byte <= mem_addr[7:0];           // Memory address (low byte)
       state <= DS_WRITE_BYTE;
       next_state <= DS_SET_ADDR_HIGH;
    end

    DS_SET_ADDR_HIGH: begin
       out_byte <= {5'd0, mem_addr[10:8]};  // Memory address (high byte)
       state <= DS_WRITE_BYTE;
       num_bytes <= 8'd0;
       next_state <= DS_READ_MEM_START;
    end

    // DS_WRITE_BYTE, DS_READ_BYTE are muxed by both two options
    DS_WRITE_BYTE: begin
       if (use_ds2480b) begin
          ds_dir <= 1'b1;
          send_en <= 1'b1;               // enable uart send module
          if (send_done == 1'b1) begin   // detect data load successfully  
             state <= next_state;
             send_en <= 1'b0;            // disable send module
             master_rst <= 1'b0;         // after initial master reset, flag always pulled low
	       end
       end
       else begin
          // Upper 3 bits of cnt go from 0 to 7; lower 13 bits go from 0 to 4424.
          // In all cases, we first pulse the data line low. If writing a 0, then
          // keep the line low for 80 usec (3932 counts). If writing a 1, then
          // keep the line low for 8 usec (393 counts).
          // Then, release (tri-state) the line and wait until a total of 90 usec
          // (4424 counts) have passed to satisfy the slot time and recovery time
          // requirements.
          `cnt13 <= `cnt13 + 13'd1;
          if (`cnt13 == 13'd0) begin
             ds_dir <= 1'b1;           // Enable FPGA output
             ds_data_out_1w <= 1'b0;   // pulse data line low
             // Pulse low for 80 usec (3932 counts) or 8 usec (393 counts) depending on
             // state of bit.
          end
          else if ((out_byte[0] && (`cnt13 == 13'd393)) ||
                   (!out_byte[0] && (`cnt13 == 13'd3932))) begin
             ds_dir <= 1'b0;
          end
          else if (`cnt13 == 13'd4424) begin
             // Total slot needs to be at least 60 usec (no more than 120 usec),
             // so make sure we wait 90 usec. This includes some time for recovery.
             if (`cnt3 == 3'd7) begin
                state <= next_state;
                cnt <= 16'd0;
             end
             else begin
                `cnt3 <= `cnt3 + 3'd1;
                out_byte <= (out_byte >> 1);
             end
          end
       end
    end

    DS_READ_BYTE: begin
       if (use_ds2480b) begin
          if (recv_done == 1'b1) begin           //recv data cnt counts to the final baud cycle    
             in_byte <= recv_data;               //register received data
             state <= next_state;
	       end
       end
       else begin
          // Drive low for < 1 usec, then tri-state line and wait another 14 usec before
          // sampling data. We have a little extra time because the < 1 usec requirement
          // does not include the ramp down time. After sampling data, wait for maximum
          // slot time (120 usec) and minimum recovery time (1 usec).
          `cnt13 <= `cnt13 + 13'd1;
          if (`cnt13 == 13'd0) begin
             ds_dir <= 1'b1;                 // Enable FPGA output
             ds_data_out_1w <= 1'b0;         // pulse data line low
          end
          if (`cnt13 == 13'd49) begin        // 49 counts is about 1 usec
             ds_dir <= 1'b0;                // Tri-state FPGA output
          end
          else if (`cnt13 == 13'd737) begin  // 737 counts is about 15 usec
             in_byte[`cnt3] <= ds_data_in;  // read input
          end
          else if (`cnt13 == 13'd5948) begin // 5948 counts is about 121 usec
             if (`cnt3 == 3'd7) begin
                state <= next_state;
                cnt <= 16'd0;
             end
             else begin
                `cnt3 <= `cnt3 + 3'd1;
             end
          end
       end
    end

    /////////////////////////////////////////////////////////////////////////////////////////////
    // DS2480B option state machine starts here
    /////////////////////////////////////////////////////////////////////////////////////////////
    DS_MASTER_RESET:   begin
       tx_data <= {1'b1, 8'h00, 1'b0};
       master_rst <= 1'b1;              // master reset enable
       state <= DS_WRITE_BYTE;
       next_state <= DS_PROGRAMMER;
       cnt <= 17'd0;
       progCnt <= 4'd0;                 // start from programmer arg 0
       DS2480B_ok <= 1;
       ds_reset <= 2'd1;
    end

    DS_PROGRAMMER: begin
       tx_data <= {1'b1, ds_program[progCnt][15:8], 1'b0};
       expected_rxd <= ds_program[progCnt][7:0];
       progCnt <= progCnt + 4'd1;
       state <= DS_WRITE_BYTE;
       next_state <= DS_CHECK_PROGRAMMER;
    end

    DS_CHECK_PROGRAMMER: begin
       state <= DS_READ_BYTE;
       case (progCnt)
          4'd1 :   state      <= DS_PROGRAMMER;        // No response in CMD mode, jump to next state without read
          4'd2 :   state      <= DS_PROGRAMMER;        // No response in CMD mode, jump to next state without read
          4'd6 :   next_state <= DS_READ_MEM_REQUEST;  // Start reading memory, send first 0xFF request
          4'd7 :   state      <= DS_PROGRAMMER;        // No response in CMD mode, jump to next state without read
          4'd8 :   state      <= DS_IDLE;              // back to IDLE, wait for chip flush
          default: next_state <= DS_PROGRAMMER;        // other states read feedback after send commands
       endcase
       family_code <= 8'h0B;                           // assign family code directly, maybe check in the future
       num_bytes <= 8'd0;
    end

    DS_READ_MEM_REQUEST: begin
       tx_data <= {1'b1, 8'hFF, 1'b0};
       state <= DS_WRITE_BYTE;
       next_state <= DS_READ_MEM_START;
    end

    // DS_READ_MEM_START, DS_READ_MEM are muxed by both two options    
    DS_READ_MEM_START: begin
       state <= DS_READ_BYTE;
       next_state <= DS_READ_MEM;
    end

    DS_READ_MEM: begin
       state <= use_ds2480b ? DS_READ_MEM_REQUEST : DS_READ_BYTE;
       next_state <= DS_READ_MEM;
       num_bytes <= num_bytes + 8'd1;
       mem_data[num_bytes[7:2]] <= (mem_data[num_bytes[7:2]] << 8) | in_byte;
       if (num_bytes == 8'hff) begin
          state <= DS_IDLE;  // back to IDLE state, direct 1-wire stop, DS2480B jump to flush states
       end
    end

    endcase 
end

endmodule


module UartTx_2480B (
	input               sys_clk,           // sys clk
	
	input               uart_en,           // send enable sig                                
	input   [9:0]       uart_din,          // data-to-be-sent
	input   wire        master_rst,        // master reset flag
	output  reg         uart_done,         // send 1 frame over flag
	output  reg         uart_txd           // UART send port
);

// parameter define
parameter    CLK_FREQ = 49152000;         // define sys clk freq
parameter    UART_BPS_9600 = 9600;        // define serial baud - 9600
parameter    UART_BPS_4800 = 4800;        // define serial baud - 4800
localparam   BPS_CNT_9600  = CLK_FREQ / UART_BPS_9600;  // count 9600 bits per second
localparam   BPS_CNT_4800  = CLK_FREQ / UART_BPS_4800;  // count 4800 bits per second

// reg define
reg          uart_en_d0;                  
reg          uart_en_d1;
reg  [15:0]  clk_cnt;                     // sys clk counter
reg  [ 3:0]  tx_cnt;                      // send data counter
reg          tx_flag;                     // send process flag
reg  [ 9:0]  tx_data;                     // send data buffer

// wire define
wire         en_flag;      

//**************************************************************
//                       main  code
//**************************************************************

// capture uart_en rising edge, get 1 clk cycle pulse
assign  en_flag = (~uart_en_d1) & uart_en_d0;

// delay 2 clk cycle for send enable sig uart_en
always @(posedge sys_clk) begin
	 uart_en_d0 <= uart_en;
	 uart_en_d1 <= uart_en_d0;
end
		  
// when en_flag pulled high, register data-to-be-sent and start send process
always @(posedge sys_clk) begin
	 if (en_flag) begin                           // detect send enable rising edge
       tx_flag   <= 1'b1;                        // enter send process, tx_flag pull high
       uart_done <= 1'b0;
       tx_data   <= uart_din;                    // register data-to-be-sent	
	 end
	 else if ((tx_cnt == 4'd9) && (clk_cnt == BPS_CNT_9600/2) && (!master_rst))
	 begin                                        // In 9600 baud, stop send process a half baud cycle after stop bit
       tx_flag   <= 1'b0;                        // send process end, tx_flag pull low
       uart_done <= 1'b1;                        // issue send done flag to DS2505.v
       tx_data   <= 10'd0; 
	 end
	 else if ((tx_cnt == 4'd9) && (clk_cnt == BPS_CNT_4800/2) && (master_rst))
	 begin                                        // For initial master reset in 4800 baud
       tx_flag   <= 1'b0;                        // send process end, tx_flag pull low
       uart_done <= 1'b1;                        // issue send done flag to DS2505.v
       tx_data   <= 10'd0; 
	 end 
	 else begin
       tx_flag   <= tx_flag;
       uart_done <= 1'b0;
       tx_data   <= tx_data;
	 end
end

// after entering send process, start sys clk cnt & send data cnt
always @(posedge sys_clk) begin
     if (tx_flag) begin                          // still in send process
        if (master_rst) begin
             if (clk_cnt == BPS_CNT_4800 - 1) begin
                clk_cnt <= 16'd0;               // sys cnt reset after 1 baud cycle
                tx_cnt  <= tx_cnt + 1'b1;       // while send data cnt add 1
             end
             else
                 clk_cnt <= clk_cnt + 1'b1;
         end
         else begin
             if (clk_cnt == BPS_CNT_9600 - 1) begin
                clk_cnt <= 16'd0;               // sys cnt reset after 1 baud cycle
                tx_cnt  <= tx_cnt + 1'b1;       // while send data cnt add 1
             end
             else begin
                 clk_cnt <= clk_cnt + 1'b1;
             end
         end
     end
     else begin                                 // send process end, counter reset
         clk_cnt <= 16'd0;
         tx_cnt  <= 4'd0; 
     end        
end

// assign data to UART sent port according to send cnt
always @(posedge sys_clk) begin
     if (tx_flag)  
          uart_txd <= tx_data[tx_cnt];          // load data bits to send port
     else
          uart_txd <= 1'b1;                     // send port pulled high when free 
end

endmodule


module  UartRx_2480B (
    input               sys_clk,             // sys clk
    
    input               uart_rxd,            // UART recv port
    output  reg         uart_done,           // recv 1 frame over flag
    output  reg  [7:0]  uart_data            // recv data
);

//parameter define
parameter    CLK_FREQ = 49152000;            // define sys clk freq
parameter    UART_BPS = 9600;                // define serial baud
localparam   BPS_CNT  = CLK_FREQ / UART_BPS; // count 9600 bits per second

//reg define
reg          uart_rxd_d0;                  
reg          uart_rxd_d1;
reg   [15:0] clk_cnt;                        // sys clk counter
reg   [ 3:0] rx_cnt;                         // recv data counter
reg          rx_flag;                        // recv process flag
reg   [ 7:0] rxdata;                         // recv data buffer

//wire define
wire         start_flag;                  

//**************************************************************
//                       main  code
//**************************************************************

// capture recv port falling edge (start bit), get 1 clk cycle pulse
assign  start_flag = uart_rxd_d1 & (~uart_rxd_d0);

// delay 2 clk cycle for UART recv port data
always @(posedge sys_clk) begin
	 begin
	    uart_rxd_d0 <= uart_rxd;
		 uart_rxd_d1 <= uart_rxd_d0;
	 end
end
		  
// when pulse start_flag arrives, start recv process
always @(posedge sys_clk) begin
    if (start_flag)                     // detect start bit
       rx_flag <= 1'b1;                 // enter recv process, rx_flag pull up
    else if ((rx_cnt == 4'd9) && (clk_cnt == BPS_CNT/2)) 
       rx_flag <= 1'b0;                 // stop recv process when counting to next half baud cycle of stop bit
    else
       rx_flag <= rx_flag; 
end

//after entering recv process, start sys clk cnt & recv data cnt
always @(posedge sys_clk) begin
    if (rx_flag) begin                     // still in recv process
       if (clk_cnt == BPS_CNT - 1) begin
          clk_cnt <= 16'd0;                // sys clk cnt reset after 1 baud cycle
          rx_cnt  <= rx_cnt + 1'b1;        // while recv data cnt add 1
       end
       else begin
          clk_cnt <= clk_cnt + 1'b1;
       end
    end
    else begin                             // recv process end, counter reset
       clk_cnt <= 16'd0;
       rx_cnt  <= 4'd0;
    end 
end

//store UART recv data according to recv counter
always @(posedge sys_clk) begin
    if (rx_flag)                           // system in recv process
       if (clk_cnt == BPS_CNT/2)           // clk counts to half of a data bit
          rxdata[rx_cnt-1] <= uart_rxd_d1; // recv cnt is 1 bit later than current data bit
       else
          rxdata <= rxdata;
    else
       rxdata <= 8'd0;	 
end

//data recv process finish, then issue a flag sig and register buffer data
always @(posedge sys_clk) begin
    if (rx_cnt == 4'd9) begin              //counts to the final bit
       uart_data <= rxdata;                //register received data
       uart_done <= 1'b1;                  //pull up recv done flag
    end
    else begin
       uart_data <= 8'd0;
       uart_done <= 1'b0;
    end
end

endmodule
