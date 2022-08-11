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
    input  wire[31:0] reg_wdata,   // register write data
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
    output reg this_busy,          // 1 -> this chip using SPI

    // Signals to be passed to I/O expander
    input wire[3:0] P30,           // Ports 0-3, cur_ctrl[1:4]
    input wire[3:0] P74,           // Ports 4-7, disable_f[1:4]
    output reg[1:0] P98            // Ports 8-9, mv-fb (9), safety-fb (8)
);
   
initial CSn = 1'bz;

reg[5:0] seqn;                     // 6-bit counter (0-63)
reg[15:0] write_data;              // Data to write to I/O Expander
reg[15:0] read_data;               // Data read from I/O Expander

reg[15:0] reg_wdata_saved;         // Copy of data written from host PC
reg[15:0] read_data_saved;         // Saved copy for host PC to read

reg doWrite;                       // 1 -> write pending or in process

// Externally-generated write (e.g., from PC)
assign ioexp_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'd0, `REG_IO_EXP}) ? reg_wen : 1'b0;

// Locally-generated write
reg ioexp_wen;

// Debug counters
reg[3:0] num_p4;
reg[3:0] num_single;

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
        mosi <= write_data[15];  // Write first bit
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

// For stepping through the configuration, polling and output
reg[3:0] step;
reg[3:0] next_step;

// For polling the I/O expander
reg do_poll;
reg[5:0] poll_timer;
// read_error is set when we read an unexpected result during polling
reg read_error;

// Values read from I/O expander ports
reg[7:0] outputs_fb;
initial outputs_fb = 8'hff;

// Commands used to configure the Max7317
wire[15:0] ConfigCommands[0:1];
assign ConfigCommands[0] = 16'h0a01;    // Set all ports tri-state (input)
assign ConfigCommands[1] = 16'h0200;    // NOP

// Commands used to poll the Max7317
wire[15:0] PollCommands[0:3];
assign PollCommands[0] = 16'h8e00;    // Read ports 0-7
assign PollCommands[1] = 16'h8f00;    // Read ports 8-9
assign PollCommands[2] = 16'h0200;    // NOP
assign PollCommands[3] = 16'h0200;    // NOP (not used)

reg do_reg_io;                        // 1 -> pending register I/O from host PC

// P_Internal and P_Test are used for testing
reg P_Test;
reg[7:0] P_Internal;
initial P_Internal = 8'hff;

reg do_output;     // 1 -> start writing outputs to MAX7317

// Desired port outputs, normally specified by other parts of
// the firmware. Note that P_Test is for testing purposes.
wire[7:0] P_Outputs;
assign P_Outputs = P_Test ? P_Internal : {P74, P30};

// PK TEMP
reg[7:0] P_Outputs_saved;
initial P_Outputs_saved = 8'hff;

reg read_debug;
// Data read by host PC
assign reg_rdata = read_debug ? { 16'd0, outputs_fb, P_Outputs } :
                   { 3'd0, read_error, num_p4, num_single, P_Test, other_busy, this_busy, do_reg_io, read_data_saved };

// Following signals are used to determine whether we can do more
// efficient updates for P0-P3 and/or P4-P7, since often these will
// change together (i.e., all 0 or all 1).
// Even more efficiency could be obtained by checking if P0-P7 are
// the same, but that would be overkill, especially since P0-P3
// and P4-P7 are different types of signals.

wire P30_changed;
assign P30_changed = (P_Outputs[3:0] != outputs_fb[3:0]) ? 1'b1 : 1'b0;
wire P30_same;
assign P30_same = ((P_Outputs[3:0] == 4'h0) || (P_Outputs[3:0] == 4'hf)) ? 1'b1 : 1'b0;

wire P74_changed;
assign P74_changed = (P_Outputs[7:4] != outputs_fb[7:4]) ? 1'b1 : 1'b0;
wire P74_same;
assign P74_same = ((P_Outputs[7:4] == 4'h0) || (P_Outputs[7:4] == 4'hf)) ? 1'b1 : 1'b0;

// Following commands write 4 values at a time (P0-P3 or P4-P7)
wire[15:0] P4_Commands[0:1];
assign P4_Commands[0] = { 8'h0b, 7'h0, P_Outputs[0] };   // Set P0-P3 to same value
assign P4_Commands[1] = { 8'h0c, 7'h0, P_Outputs[4] };   // Set P4-P7 to same value

always @(posedge clk)
begin
    if (this_busy) begin
        ioexp_wen <= 1'b0;
        step <= next_step;
    end
    else if (ioexp_cfg_reset) begin
        // Restart check for MAX7317
        ioexp_cfg_valid <= 1'b0;
        ioexp_cfg_present <= 1'b0;
        step <= 4'd0;
    end
    else if (!ioexp_cfg_valid) begin
        // This code attempts to initialize the MAX7317 by setting all
        // ports tri-state (input), and then reading back the command
        // after writing a NOP. If read_data is equal to the initial
        // command, then the MAX7317 I/O expander is present.
        write_data <= ConfigCommands[step[0]];
        ioexp_wen <= 1'b1;
        next_step <= step + 4'd1;
        if (step == 4'd2) begin
            ioexp_cfg_present <= (read_data == ConfigCommands[0]) ? 1'b1 : 1'b0;
            ioexp_cfg_valid <= 1'b1;
            step <= 4'd0;
        end
    end
    else if (do_poll) begin
        write_data <= PollCommands[step[1:0]];
        ioexp_wen <= 1'b1;
        next_step <= step + 4'd1;
        if (step == 4'd2) begin
            if (read_data[15:8] == PollCommands[0][15:8]) begin
                // PK TEMP
                //outputs_fb <= read_data[7:0];
            end
            else begin
                read_error <= 1'b1;
            end
        end
        else if (step == 4'd3) begin
            if (read_data[15:8] == PollCommands[1][15:8]) begin
                P98 <= read_data[1:0];
            end
            else begin
                read_error <= 1'b1;
            end
            do_poll <= 1'b0;
            step <= 4'd0;
            poll_timer <= 6'd0;
            do_output <= (outputs_fb != P_Outputs) ? 1'b1 : 1'b0;
        end
    end
    else if (do_output) begin
        if (step[3]) begin
            // All done, need to poll again to update outputs_fb
            do_output <= 1'b0;
            do_poll <= 1'b1;
            step <= 4'd0;
            // PK TEMP
            outputs_fb <= P_Outputs;
        end
        else if ( ((~step[2])&P30_changed) | (step[2]&P74_changed) ) begin
            // Output changed for steps 0-3 or 4-7
            if (((step == 4'd0) && P30_same) || ((step == 4'd4) && P74_same)) begin
                // All 4 values are the same
                write_data <= P4_Commands[step[2]];
                ioexp_wen <= 1'b1;
                next_step <= step + 4'd4;
                num_p4 <= num_p4 + 4'd1;
            end
            else begin
                if (outputs_fb[step[2:0]] != P_Outputs[step[2:0]]) begin
                    write_data <= { 4'h0, step, 7'h0, P_Outputs[step[2:0]] };
                    ioexp_wen <= 1'b1;
                    next_step <= step + 4'd1;
                    num_single <= num_single + 4'd1;
                end
                else begin
                    // Output is correct, skip to next step
                    step <= step + 4'd1;
                end
            end
        end
        else begin
            // All 4 outputs are correct, skip 4 steps
            step <= step + 4'd4;
        end
    end
    else if (do_reg_io) begin
        if (step == 4'd0) begin
            write_data <= reg_wdata_saved;
            ioexp_wen <= 1'b1;
            next_step <= 4'd1;
        end
        else begin
            read_data_saved <= read_data;
            do_reg_io <= 1'b0;
            step <= 4'd0;
        end
    end
    else begin
        // IDLE state (not writing or reading)
        ioexp_wen <= 1'b0;
        step <= 4'd0;
        next_step <= 4'd0;

        // PK TEMP START
        P_Outputs_saved <= P_Outputs;
        if (P_Outputs_saved != P_Outputs) begin
            outputs_fb <= P_Outputs_saved;
        end
        // PK TEMP END
        if (ioexp_cfg_present) begin
            // Poll timer waits for about 1.3 usec before starting next poll
            poll_timer <= poll_timer + 6'd1;
            if (outputs_fb != P_Outputs) begin
                // Output initiated when specified signals (P30, P74) do not match values read
                // from I/O expander. This has to be changed, because the value read from the
                // I/O expander may not be correct due to a hardware problem, such as a missing
                // pull-up resistor.
                do_output <= 1'b1;
            end
            else if (poll_timer == 6'h3f) begin
                do_poll <= 1'b1;
            end
        end
    end

    // Always check for register writes from host and set corresponding flag (do_reg_io).
    // The flag will not be acted upon until this_busy is false.
    if (ioexp_reg_wen) begin
        // Following handles external writes (e.g., from PC).
        // Note that the write will be ignored if another write is pending.
        // We do not check ioexp_cfg_present so that the external PC can
        // still attempt to write to MAX7317 even if it was not detected.
        read_debug <= reg_wdata[29];
        if (reg_wdata[30]) begin
            read_error <= 1'b0;
        end
        P_Test <= reg_wdata[31];
        if (reg_wdata[31]) begin
            P_Internal <= reg_wdata[23:16];
        end
        else begin
            do_reg_io <= 1'b1;
            reg_wdata_saved <= reg_wdata[15:0];
        end
    end
end
endmodule
