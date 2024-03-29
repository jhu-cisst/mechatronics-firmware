/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2022-2023 Johns Hopkins University.
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
 * The CLKBIT parameter determines SCLK period:
 *     CLKBIT=0   -->   40 ns period
 *     CLKBIT=1   -->   80 ns period
 *
 * Revision history
 *     07/27/22    Peter Kazanzides    Initial revision
 */

module Max7317
    #(parameter[3:0] IOEXP_ID = 4'd0,
      parameter CLKBIT = 0)        // CLKBIT determines SCLK timing
(
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
    output reg[1:0] P98,           // Ports 8-9, mv-fb (9), safety-fb (8)

    // Following output errors indicate whether value read from output
    // port (outputs_fb) does not match value written. One possible cause
    // would be a missing pull-up resistor.
    output wire[3:0] P30_error,
    output wire[3:0] P74_error
);
   
initial CSn = 1'bz;

reg[(5+CLKBIT):0] seqn;            // (6+N)-bit counter
reg[15:0] write_data;              // Data to write to I/O Expander
reg[15:0] read_data;               // Data read from I/O Expander

reg[15:0] reg_wdata_saved;         // Copy of data written from host PC
reg[15:0] read_data_saved;         // Saved copy for host PC to read
reg thisActive;                    // 1 -> this device most recently addressed

// Externally-generated write (e.g., from PC)
assign ioexp_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'd0, `REG_IO_EXP}) ? reg_wen : 1'b0;

// Locally-generated write
reg ioexp_wen;

assign sclk = seqn[CLKBIT]&(~CSn);

//   seqn   0  1   2   3   4   5      (for CLKBIT==0)
//   sclk   ___|---|___|---|___|---   (rising edge on odd numbers)
//   data  15     14      13          (data out on falling edge)

// SPI interface block
always @(posedge clk)
begin
    if (ioexp_wen) begin
        // There is no check whether a transaction is currently in
        // process (this_busy) or pending, so it is up to the caller
        // to check the status bits by first reading the register.
        // Note that write_data should already be set by caller.
        // This state ends when this_busy is set, which causes the
        // caller to clear ioexp_wen.
        read_data <= 16'd0;
        seqn <= {(6+CLKBIT){1'b0}};
        mosi <= write_data[15];  // Write first bit
        if (~other_busy) begin
            CSn <= 1'b0;
            this_busy <= 1'b1;
        end
    end
    else if (this_busy) begin
        seqn <= seqn + 1'b1;
        if (seqn[(5+CLKBIT):CLKBIT] == 6'h20)  begin       // 64 SCLKs
            // Falling edge of SCLK after writing last bit; deassert CSn.
            CSn <= 1'b1;
        end
        else if (CSn&this_busy) begin
            // CSn&this_busy are not both set initially, so they
            // are only both set at end (after 64 SCLKs)
            this_busy <= 1'b0;
            seqn <= {(6+CLKBIT){1'b0}};
        end
        else begin
            CSn <= 1'b0;
            // Write data via SPI.
            if (seqn[CLKBIT:0] == {(CLKBIT+1){1'b1}}) mosi <= write_data[~(seqn[(CLKBIT+4):(CLKBIT+1)]+1)];
            // Read data from SPI.
            read_data[~seqn[(CLKBIT+4):(CLKBIT+1)]] <= miso;
        end
    end
    else begin
        // Idle state: make sure CSn is high
        CSn <= 1'b1;
        this_busy <= 1'b0;
    end
end

reg ioexp_cfg_valid;

// For stepping through the configuration, polling and output
reg[3:0] step;

// For polling the I/O expander
reg do_poll;
reg[5:0] poll_timer;
// read_error is set when we read an unexpected result during polling
reg read_error;

// Values read from I/O expander ports
reg[7:0] outputs_fb;
initial outputs_fb = 8'hff;

// Indicates whether there is an output error (i.e., value read from
// I/O expander does not match shadow copy P_Shadow). The most likely
// cause is a missing pullup resistor on the port output.
wire output_error;
reg[7:0] output_error_mask;
assign P30_error = output_error_mask[3:0];
assign P74_error = output_error_mask[7:4];
assign output_error = (output_error_mask == 8'd0) ? 1'b0 : 1'b1;
reg[7:0] num_output_error;

// Commands used to configure the Max7317
wire[15:0] ConfigCommands[0:1];
assign ConfigCommands[0] = 16'h0a01;    // Set all ports tri-state (input)
assign ConfigCommands[1] = 16'h2000;    // NOP

// Commands used to poll the Max7317
wire[15:0] PollCommands[0:3];
assign PollCommands[0] = 16'h8e00;    // Read ports 0-7
assign PollCommands[1] = 16'h8f00;    // Read ports 8-9
assign PollCommands[2] = 16'h2000;    // NOP
assign PollCommands[3] = 16'h2000;    // NOP (not used)

reg do_reg_io;                        // 1 -> pending register I/O from host PC
wire reg_io_read;                     // 1 -> register read in process (from host PC)
reg[7:0] reg_io_addr;                 // last register address (and r/w bit) from host PC
assign reg_io_read = reg_io_addr[7];

reg do_output;     // 1 -> start writing outputs to MAX7317

// Desired port outputs, normally specified by other parts of the firmware.
wire[7:0] P_Outputs;
assign P_Outputs = {P74, P30};

// Shadow copy of desired port outputs
reg[7:0] P_Shadow;

reg read_debug;
// Data read by host PC
assign reg_rdata = thisActive ?
                       read_debug ? { output_error_mask, num_output_error, outputs_fb, P_Outputs } :
                       { 3'b010, other_busy, reg_io_read, do_reg_io, read_error, output_error,
                         output_error_mask, read_data_saved } :
                   32'd0;

// Following signals are used to determine whether we can do more
// efficient updates for P0-P3 and/or P4-P7, since often these will
// change together (i.e., all 0 or all 1).
// Even more efficiency could be obtained by checking if P0-P7 are
// the same, but that would be overkill, especially since P0-P3
// and P4-P7 are different types of signals.

wire P30_changed;
assign P30_changed = (P_Outputs[3:0] != P_Shadow[3:0]) ? 1'b1 : 1'b0;
wire P30_same;
assign P30_same = ((P_Outputs[3:0] == 4'h0) || (P_Outputs[3:0] == 4'hf)) ? 1'b1 : 1'b0;

wire P74_changed;
assign P74_changed = (P_Outputs[7:4] != P_Shadow[7:4]) ? 1'b1 : 1'b0;
wire P74_same;
assign P74_same = ((P_Outputs[7:4] == 4'h0) || (P_Outputs[7:4] == 4'hf)) ? 1'b1 : 1'b0;

always @(posedge clk)
begin
    if (this_busy) begin
        // We wait in this state until the SPI always block finishes processing
        // the request and clears this_busy. At that time, ioexp_wen should be
        // clear and we would process the next step or return to the idle state.
        ioexp_wen <= 1'b0;
    end
    else if (ioexp_wen) begin
        // We wait in this state until the SPI always block responds to the
        // ioexp_wen request and sets this_busy, which then causes a transition
        // to the state above.
    end
    else if (!ioexp_cfg_valid) begin
        // This code attempts to initialize the MAX7317 by setting all
        // ports tri-state (input), and then reading back the command
        // after writing a NOP. If read_data is equal to the initial
        // command, then the MAX7317 I/O expander is present.
        if (step == 4'd2) begin
            ioexp_cfg_present <= (read_data == ConfigCommands[0]) ? 1'b1 : 1'b0;
            ioexp_cfg_valid <= 1'b1;
            step <= 4'd0;
        end
        else begin
            write_data <= ConfigCommands[step[0]];
            ioexp_wen <= 1'b1;
            step <= step + 4'd1;
            P_Shadow <= 8'hff;
        end
    end
    else if (do_poll) begin
        write_data <= PollCommands[step[1:0]];
        ioexp_wen <= 1'b1;
        step <= step + 4'd1;
        if (step == 4'd2) begin
            if (read_data[15:8] == PollCommands[0][15:8]) begin
                outputs_fb <= read_data[7:0];
                output_error_mask <= read_data[7:0]^P_Shadow;
                if ((read_data[7:0]^P_Shadow) != 8'd0) begin
                    num_output_error <= num_output_error + 8'd1;
                    // Following removed since it does not seem to help
                    // Output again after 16 consecutive output errors
                    //if (num_output_error[3:0] == 4'd0)
                    //    do_output <= 1'b1;
                end
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
        end
    end
    else if (do_output) begin
        if (step[3]) begin
            do_output <= 1'b0;
            step <= 4'd0;
            // reset poll_timer so that there is enough time for output to
            // reach desired value before output_error check.
            poll_timer <= 6'd0;
        end
        else if ( ((~step[2])&P30_changed) | (step[2]&P74_changed) ) begin
            // Output changed for steps 0-3 or 4-7
            if (((step == 4'd0) && P30_same) || ((step == 4'd4) && P74_same)) begin
                // All 4 values are the same
                if (step == 4'd0) begin
                    // Set P0-P3 to same value
                    write_data <= { 8'h0b, 7'h0, P_Outputs[0] };
                    P_Shadow[3:0] <= P_Outputs[3:0];
                end
                else begin
                   // Set P4-P7 to same value
                   write_data <= { 8'h0c, 7'h0, P_Outputs[4] };
                   P_Shadow[7:4] <= P_Outputs[7:4];
                end
                ioexp_wen <= 1'b1;
                step <= step + 4'd4;
            end
            else begin
                if (P_Outputs[step[2:0]] != P_Shadow[step[2:0]]) begin
                    write_data <= { 4'h0, step, 7'h0, P_Outputs[step[2:0]] };
                    P_Shadow[step[2:0]] <= P_Outputs[step[2:0]];
                    ioexp_wen <= 1'b1;
                end
                step <= step + 4'd1;
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
            step <= 4'd1;
        end
        else begin
            // Indicate that a read was issued, so we can later save the
            // result in read_data_saved (note that setting reg_io_addr
            // will set reg_io_read if upper bit is set).
            reg_io_addr <= write_data[15:8];
            do_reg_io <= 1'b0;
            step <= 4'd0;
        end
    end
    else begin
        // IDLE state (not writing or reading)
        ioexp_wen <= 1'b0;
        step <= 4'd0;

        if (ioexp_cfg_reset) begin
            // Restart check for MAX7317
            ioexp_cfg_valid <= 1'b0;
            ioexp_cfg_present <= 1'b0;
        end
        else if (ioexp_cfg_present) begin
            // Poll timer waits for about 1.3 usec before starting next poll
            poll_timer <= poll_timer + 6'd1;
            if (P_Outputs != P_Shadow) begin
                // Output initiated when specified signals P_Outputs (P30, P74) do not match
                // shadow copy P_Shadow. Note that we cannot check against the values read
                // from the I/O expander, outputs_fb, because if it is incorrect (e.g., due to
                // a missing pullup resistor), do_output will constantly be set.
                // Instead, we note this problem (elsewhere) by comparing P_Shadow to outputs_fb
                // and set output_error_mask for any bits which do not match.
                do_output <= 1'b1;
            end
            else if (poll_timer == 6'h3f) begin
                do_poll <= 1'b1;
            end
        end
        else begin
            // Make sure output_error_mask is 0
            output_error_mask <= 8'd0;
        end
    end

    // Always check for register writes from host and set corresponding flag (do_reg_io).
    // The flag will not be acted upon until this_busy is false.
    if (ioexp_reg_wen) begin
        // Following handles external writes (e.g., from PC).
        // Note that the write will be ignored if another write is pending.
        // We do not check ioexp_cfg_present so that the external PC can
        // still attempt to write to MAX7317 even if it was not detected.
        //   reg_wdata[31]     1 --> clear errors
        //   reg_wdata[30]     1 --> switch to debug data
        //   reg_wdata[19:16]  I/O expander ID
        //   reg_wdata[15:0]   Command to I/O expander (if upper bits clear)
        if (reg_wdata[19:16] == IOEXP_ID) begin
            thisActive <= 1'b1;
            if (reg_wdata[31]) begin
                read_error <= 1'b0;
                num_output_error <= 8'd0;
            end
            read_debug <= reg_wdata[30];
            // If upper 12 bits clear, send command to I/O expander
            if (reg_wdata[31:20] == 12'd0) begin
                do_reg_io <= 1'b1;
                reg_wdata_saved <= reg_wdata[15:0];
            end
        end
        else begin
            thisActive <= 1'b0;
        end
    end

    // Check if a register read (from host PC) is in process. If so, we save the result
    // when we get a match on the command (upper 8 bits).
    if (reg_io_read && !this_busy && (read_data[15:8] == reg_io_addr)) begin
        read_data_saved <= read_data;
        reg_io_addr <= 8'd0;
    end

end
endmodule
