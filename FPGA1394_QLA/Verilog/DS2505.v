/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2018-2020 Johns Hopkins University.
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

    input  wire dout_cfg_bidir,      // 1 -> bidirectional I/O available
    input  wire ds_data_in,          // 1-wire interface, data in
    output reg ds_data_out,          // 1-wire interface, data out
    output reg ds_dir,               // direction for 1-wire interface (0=input to FPGA, 1=output from FPGA)
    output reg ds_enable             // enables this module to drive the digital I/O line
);

initial ds_data_out = 1'b1;

// State machine
localparam[3:0]
    DS_IDLE = 0,
    DS_RESET_BEGIN = 1,
    DS_RESET_END = 2,
    DS_RESET_ACK_WAIT = 3,
    DS_RESET_ACK_CHECK = 4,
    DS_RESET_RECOVER = 5,
    DS_WRITE_BYTE = 6,
    DS_READ_BYTE = 7,
    DS_READ_PROM_START = 8,
    DS_READ_PROM = 9,
    DS_SET_ADDR_LOW = 10,
    DS_SET_ADDR_HIGH = 11,
    DS_READ_MEM_START = 12,
    DS_READ_MEM = 13;

// Local registers and wires
reg[3:0]  state;           // state machine 
reg[3:0]  next_state;      // keeps track of next state
initial begin
    state = DS_IDLE;
    next_state = DS_IDLE;
end

reg[7:0]  out_byte;        // output byte to write to DS2505
reg[7:0]  in_byte;         // input byte read from DS2505
reg[7:0]  family_code;     // family code for DS2505 (0x0B)
reg[15:0] cnt;             // counter for timing
reg[7:0]  rise_time;       // measured rise time (for debugging)
initial   rise_time = 8'hff;
reg[1:0]  ds_reset;        // 0=not attempted, 1=success, 2=failed (rise-time), 3=failed (no ack from DS2505)
reg[10:0] mem_addr;        // memory address for reading
reg[7:0]  num_bytes;       // Number of bytes to read

wire      ds_reg_wen;      // main quadlet reg interface
assign ds_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'd0, `REG_DSSTAT}) ? reg_wen : 1'b0;

reg[31:0] mem_data[0:64];  // Up to 64 quadlets (256 bytes) read from chip, provided via block read

wire[5:0] ds_blk_raddr;    // memory block read address (0-63)
assign ds_blk_raddr = reg_raddr[5:0];

// Definitions to use smaller counters
`define cnt3  cnt[15:13]   // upper 3 bits (range 0-7)
`define cnt13 cnt[12:0]    // lower 13 bits (range 0-8191)
`define cnt11 cnt[10:0]    // lower 11 bits (range 0-2047)
`define cnt8  cnt[7:0]     // lower 8 bits (range 0-255)
   
assign ds_status[31:24] = family_code;
assign ds_status[23:16] = rise_time;
assign ds_status[15:12] = 4'd0;
assign ds_status[11:8] = next_state;
assign ds_status[7:4] = state;
assign ds_status[3] = dout_cfg_bidir;
assign ds_status[2:1] = ds_reset;
assign ds_status[0] = ds_enable;
   

always @(posedge(clk))
begin
    // 1-wire state machine 
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
          //         bits 26:16
          //           11-bit address (0-2047 bytes)
          case (reg_wdata[1:0])
            2'b00: ds_enable <= 1'd0;
            2'b01: ds_enable <= 1'd1;
            2'b10: begin
                   ds_enable <= 1'd1;
                   state <= DS_RESET_BEGIN;
                   mem_addr <= reg_wdata[26:16];  // 11-bit address (0-2047 bytes)
                   rise_time <= 8'hff;
                   ds_reset <= 2'd0;
                   ds_dir <= 1'b1;       // enable driver
                   ds_data_out <= 1'b0;  // start reset pulse
                   cnt <= 16'd0;
                   end
            2'b11: begin
                   // ds_enable should already be 1
                   state <= DS_READ_MEM_START;
                   cnt <= 16'd0;
                   end
          endcase
       end
    end

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

    DS_WRITE_BYTE: begin
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
          ds_data_out <= 1'b0;      // pulse data line low
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

    DS_READ_BYTE: begin
       // Drive low for < 1 usec, then tri-state line and wait another 14 usec before
       // sampling data. We have a little extra time because the < 1 usec requirement
       // does not include the ramp down time. After sampling data, wait for maximum
       // slot time (120 usec) and minimum recovery time (1 usec).
       `cnt13 <= `cnt13 + 13'd1;
       if (`cnt13 == 13'd0) begin
          ds_dir <= 1'b1;           // Enable FPGA output
          ds_data_out <= 1'b0;      // pulse data line low
       end
       if (`cnt13 == 13'd49) begin        // 49 counts is about 1 usec
          ds_dir <= 1'b0;       // Tri-state FPGA output
       end
       else if (`cnt13 == 13'd737) begin  // 737 counts is about 15 usec
          in_byte[`cnt3] <= ds_data_in;       // read input
       end
       else if (`cnt13 == 13'd5948) begin    // 5948 counts is about 121 usec
          if (`cnt3 == 3'd7) begin
             state <= next_state;
             cnt <= 16'd0;
          end
          else begin
             `cnt3 <= `cnt3 + 3'd1;
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
       next_state <= DS_READ_MEM_START;
    end

    DS_READ_MEM_START: begin
       state <= DS_READ_BYTE;
       next_state <= DS_READ_MEM;
       num_bytes <= 8'd0;
    end

    DS_READ_MEM: begin
       state <= DS_READ_BYTE;
       next_state <= DS_READ_MEM;
       num_bytes <= num_bytes + 8'd1;
       mem_data[num_bytes[7:2]] <= (mem_data[num_bytes[7:2]] << 8) | in_byte;
       if (num_bytes == 8'hff) begin
          state <= DS_IDLE;
          next_state <= DS_IDLE;
       end
    end

    endcase // case (state)
end

endmodule
