/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2022 Johns Hopkins University.
 *
 * Module: Max7317
 *
 * Purpose: SPI to MAX7317 I/O Expander
 *
 * Data format:
 *
 *    | D15 |   D14:D8    |  D7:D0   |
 *    | R/W | Address (7) | Data (8) |
 *
 * When writing to MAX7317, send D15 first
 *
 * Read or Write to MAX7317:
 *   1) sclk <= 1'b0
 *   2) CSn <= 1'b0
 *   3) Send D15:D0  (D15=1'b0)
 *   4) CSn <= 1'b1, sclk <= 1'b0
 *
 * For a read, issue another command and read DOUT, last 8 bits are
 * the data.
 *
 * In this implementation, we always read from the chip, which
 * returns the previous command written. If the previous command
 * was a read, then the lower 8 bits contain the data.
 *
 * SCLK: maximum frequency = 26 MHz (period = 38.4 nsec)
 * Timing:
 *     CSn fall to SCLK rise = 9.5 nsec
 *     SCLK rise to CSn rise (hold time) = 2.5 nsec
 *     DIN setup = 9.5 nsec
 *     DIN hold = 2.5 nsec
 *
 * Revision history
 *     07/27/22    Peter Kazanzides    Initial revision
 */

module Max7317(
    input clk,                     // input clock

    //input  wire[15:0] reg_raddr,   // read address (not used)
    input  wire[15:0] reg_waddr,   // write address
    output wire[31:0] reg_rdata,   // register read data
    input  wire[15:0] reg_wdata,   // register write data 
    input  wire reg_wen,           // reg write enable

    // Configuration
    input wire ioexp_cfg_reset,    // reset configuration check
    output reg ioexp_cfg_present,  // 1 -> MAX7317 is present

    // SPI interface
    input wire miso,               // input from the MAX7317
    output reg mosi,               // output to the MAX7317
    output wire sclk,              // SPI clock
    output reg CSn,                // chip select (active low)
    input wire other_busy,         // 1 -> another chip using SPI
    output reg this_busy           // 1 -> this chip using SPI
);
   
initial CSn = 1'bz;

reg[5:0] seqn;                     // 6-bit counter (0-63)
reg[15:0] write_data;              // Data to write to I/O Expander
reg[15:0] read_data;               // Data read from I/O Expander
   
reg doWrite;                       // 1 -> write pending or in process

// Externally-generated write (e.g., from PC)
assign ioexp_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'd0, `REG_IO_EXP}) ? reg_wen : 1'b0;

// Locally-generated write
reg ioexp_wen;

// Data read by host PC
assign reg_rdata = { 13'd0, other_busy, this_busy, doWrite, read_data };

assign sclk = seqn[0]&(~CSn);

//   seqn   0  1   2   3   4   5
//   sclk   ___|---|___|---|___|---   (rising edge on odd numbers)
//   data  15     14      13          (data out on falling edge)

always @(posedge clk)
begin
    if (ioexp_wen) begin
        // There is no check whether a transaction is currently in
        // process (this_busy) or pending (doWrite&(~this_busy)),
        // so it is up to the caller to check the status bits by first
        // reading the register.
        // Note that write_data should already be set by caller.
        read_data <= 16'd0;
        doWrite <= 1'b1;
        seqn <= 6'd0;
        mosi <= reg_wdata[15];   // Write first bit
        CSn <= other_busy;       // Assert CSn (low) if SPI not busy
        this_busy <= ~other_busy;
    end
    else if (doWrite&(~other_busy)) begin
        this_busy <= 1'b1;
        seqn <= seqn + 6'd1;
        if ((seqn == 6'h20) || (seqn == 6'h21))  begin
            // Falling edge of SCLK after writing last bit; deassert CSn.
            // Hold CSn high for at least 2 clocks.
            CSn <= 1'b1;
        end
        else if (seqn == 6'h22) begin
            doWrite <= 1'b0;
            CSn <= 1'b1;
            seqn <= 6'd0;
        end
        else begin
            CSn <= 1'b0;
            // Write data via SPI.
            if (seqn[0]) mosi <= write_data[~(seqn[4:1]+1)];
            // Read data from SPI.
            read_data[~seqn[4:1]] <= miso;
        end
    end
    else begin
        // Idle state (or other_busy); make sure CSn is high
        CSn <= 1'b1;
        this_busy <= 1'b0;
    end
end

reg ioexp_cfg_valid;
reg[1:0] cfg_step;
reg[1:0] next_cfg_step;

always @(posedge clk)
begin
    if (ioexp_cfg_reset) begin
        // Restart check for MAX7317
        ioexp_cfg_valid <= 1'b0;
        ioexp_cfg_present <= 1'b0;
        cfg_step <= 2'd0;
        next_cfg_step <= 2'd0;
    end
    else if (!ioexp_cfg_valid) begin
        // This code attempts to initialize the MAX7317 by setting all
        // ports tri-state (input), and then reading back the command
        // after writing a NOP. If read_data is equal to the initial
        // command, then the MAX7317 I/O expander is present.
        if (this_busy) begin
            ioexp_wen <= 1'b0;
            cfg_step <= next_cfg_step;
        end
        else if (cfg_step == 2'd0) begin
            write_data <= 16'h0a01;    // Set all ports tri-state (input)
            ioexp_wen <= 1'b1;
            next_cfg_step <= 2'd1;
        end
        else if (cfg_step == 2'd1) begin
            write_data <= 16'h0200;    // NOP
            ioexp_wen <= 1'b1;
            next_cfg_step <= 2'd2;
        end
        else if (cfg_step == 2'd2) begin
            ioexp_cfg_present <= (read_data == 16'h0a01) ? 1'b1 : 1'b0;
            ioexp_cfg_valid <= 1'b1;
        end
    end
    else if (ioexp_reg_wen) begin
        // Following handles external writes (e.g., from PC).
        // Note that the write will be ignored if the SPI interface
        // is already active (this_busy).
        // We do not check ioexp_cfg_present so that the external PC can
        // still attempt to write to MAX7317 even if it was not detected.
        ioexp_wen <= ~this_busy;
        if (~this_busy) begin
            write_data <= reg_wdata[15:0];
        end
    end
    else begin
        ioexp_wen <= 1'b0;
    end
end
endmodule
