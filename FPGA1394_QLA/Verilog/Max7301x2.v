/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2022 Johns Hopkins University.
 *
 * Module: Max7301x2
 *
 * Purpose: SPI to 2 x MAX7301 I/O Expanders, which share a common SCLK, MOSI and MISO,
 * but separate CSn. This code is similar to Max7317.v, but there are enough differences
 * to warrant a separate implementation.
 *
 * When instantiating the module, specify two distinct IDs for the Max7301s. This is
 * only necessary for sending commands from the host PC directly to a specific Max7301 or
 * Max7317. All host register access to these I/O expanders is handled via REG_IO_EXP (14).
 *
 * Data format:
 *
 *    | D15 |   D14:D8    |  D7:D0   |
 *    | R/W | Address (7) | Data (8) |
 *
 * When writing to MAX7301, send D15 first
 *
 * SCLK: maximum frequency = 26 MHz (period = 38.4 nsec)
 * Output data propagation delay is 21 ns (max), measured from
 * falling edge of SCLK.
 *
 * Revision history
 *     12/19/22    Peter Kazanzides    Created from Max7317.v
 */

module Max7301x2
    #(parameter[3:0] IOEXP_ID1 = 4'd3,
      parameter[3:0] IOEXP_ID2 = 4'd4)
(
    input clk,                     // input clock

    //input  wire[15:0] reg_raddr,   // read address (not used)
    input  wire[15:0] reg_waddr,   // write address
    output wire[31:0] reg_rdata,   // register read data
    input  wire[31:0] reg_wdata,   // register write data
    input  wire reg_wen,           // reg write enable

    // Configuration
    output reg[2:1] ioexp_cfg_ok,  // 1 -> MAX7301 was detected

    // SPI interface
    input wire miso,               // input from the MAX7301
    output reg mosi,               // output to the MAX7301
    output wire sclk,              // SPI clock
    output reg[2:1] CSn,           // chip selects (active low)

    // Signals to/from I/O expander
    //    Outputs: [31:28] (LEDs), [16] (pwr_enable), [15:12] (amp_disable)
    //    Inputs:  everything else
    // Since we can efficiently read inputs in multiples of bytes, we read
    // a total of 24 bits [27:4], which includes outputs [16:12].
    // For [16:12], we therefore include a check that the value read matches
    // the desired output; if not, the corresponding IOPx_16_12_error bit
    // is set.  We do not bother checking [31:28] because they are just LED
    //  outputs and it would require an extra read.
    input wire[3:0] IOP1_31_28,     // Signals to write to port 1, [31:28]
    input wire[3:0] IOP2_31_28,     // Signals to write to port 2, [31:28]
    input wire[4:0] IOP1_16_12,     // Signals to write to port 1, [16:12]
    input wire[4:0] IOP2_16_12,     // Signals to write to port 2, [16:12]
    output wire[18:0] IOP1_read,    // Signals read from port 1
    output wire[18:0] IOP2_read,    // Signals read from port 2
    // Following output errors indicate whether value read from output
    // port does not match value written.
    output reg[4:0] IOP1_16_12_error,
    output reg[4:0] IOP2_16_12_error
);
   
//****************** Low-level SPI Interface ****************************

initial CSn = 2'b11;

reg spi_busy;                      // 1 -> SPI in process

reg[5:0] seqn;                     // 6-bit counter (0-63)
reg[15:0] write_data;              // Data to write to I/O Expander
reg[15:0] read_data;               // Data read from I/O Expander

reg doWrite;                       // 1 -> write pending or in process

// Write request from higher-level block
//    0 --> inactive
//    1 --> write to channel 1 requested
//    2 --> write to channel 2 requested
reg[1:0] chan_wen;

// Writes from host PC are interleaved with normal operation (e.g., polling),
// thus we need to save the result for later access by the host.
reg spi_save;                 // 1 -> save result for host
wire reg_io_read;             // 1 -> register read in process (from host PC)
reg[7:0] reg_io_addr;         // last register address (and r/w bit) from host PC
assign reg_io_read = reg_io_addr[7];
reg[15:0] read_data_saved;    // Saved copy for host PC to read

// SPI channel active
reg[1:0] chan_spi;

// Gate SCLK with ~CSn. Note that CSn[chan_spi] would be more correct,
// except we would have to handle the case of chan_spi == 0.
assign sclk = seqn[0]&((~CSn[1])|(~CSn[2]));

//   seqn   0  1   2   3   4   5
//   sclk   ___|---|___|---|___|---   (rising edge on odd numbers)
//   dout  15     14      13          (data to MAX7301 on falling edge)
//   din          15      14          (data from MAX7301)

always @(posedge clk)
begin
    if (chan_wen != 2'd0) begin
        // Note that write_data should already be set by caller.
        read_data <= 16'd0;
        doWrite <= 1'b1;
        seqn <= 6'd0;
        mosi <= write_data[15];   // Write first bit
        CSn[chan_wen] <= 1'b0;    // Assert CSn (low)
        chan_spi <= chan_wen;
        if (spi_save) begin
            read_data_saved <= 16'd0;
            reg_io_addr <= write_data[15:8];
        end
        spi_busy <= 1'b1;
    end
    else if (doWrite) begin
        seqn <= seqn + 6'd1;
        if ((seqn == 6'h20) || (seqn == 6'h21))  begin
            // Falling edge of SCLK after writing last bit; deassert CSn.
            // Hold CSn high for at least 2 clocks.
            CSn[chan_spi] <= 1'b1;
        end
        else if (seqn == 6'h22) begin
            doWrite <= 1'b0;
            CSn[chan_spi] <= 1'b1;
            seqn <= 6'd0;
            if (reg_io_read && (read_data[15:8] == reg_io_addr)) begin
                // Save data for host PC
                read_data_saved <= read_data;
                reg_io_addr <= 8'd0;
            end
        end
        else begin
            CSn[chan_spi] <= 1'b0;
            // Write data via SPI.
            if (seqn[0]) mosi <= write_data[~(seqn[4:1]+1)];
            // Read data from SPI. In this case, it doesn't hurt to latch
            // each value because only the last one (when seqn[0] == 1)
            // will be kept.
            read_data[~seqn[4:1]] <= miso;
        end
    end
    else begin
        // Idle state; make sure CSn is high
        CSn[1] <= 1'b1;
        CSn[2] <= 1'b1;
        spi_busy <= 1'b0;
    end
end

//************************ High-level interface **************************************

// Data read from I/O expander
reg[18:0] IOP_read[1:2];
assign IOP1_read = IOP_read[1];
assign IOP2_read = IOP_read[2];

// Shadow copy of desired port outputs (power-up configuration is to output 0)
reg[4:0] Shadow_16_12[1:2];
reg[3:0] Shadow_31_28[1:2];

// Whether I/O expander has been configured
reg[2:1] ioexp_cfg_done;

// For stepping through the configuration, polling and output
reg[3:0] step;
reg[3:0] next_step;

// For polling the I/O expander
reg[5:0] poll_timer;

// read_error is set when we read an unexpected result during polling
reg[2:1] read_error;

// Indicates whether there is an output error (i.e., value read from
// I/O expander does not match shadow copy).
wire output_error[1:2];
assign output_error[1] = (IOP1_16_12_error == 5'd0) ? 1'b0 : 1'b1;
assign output_error[2] = (IOP2_16_12_error == 5'd0) ? 1'b0 : 1'b1;
// Number of output errors
reg[7:0] num_output_error[1:2];

// Commands used to configure the Max7301
// Could also set initial values of output ports
wire[15:0] ConfigCommands[0:7];
assign ConfigCommands[0] = 16'h09ff;  // IOP[7:4] is input with pullup
assign ConfigCommands[1] = 16'h0aff;  // IOP[11:8] is input with pullup
assign ConfigCommands[2] = 16'h0b55;  // IOP[15:12] is output
assign ConfigCommands[3] = 16'h0c57;  // IOP[16] is output, IOP[19:17] is input with pullup
assign ConfigCommands[4] = 16'h0dff;  // IOP[23:20] is input with pullup
assign ConfigCommands[5] = 16'h0eff;  // IOP[27:24] is input with pullup
assign ConfigCommands[6] = 16'h0f55;  // IOP[31:28] is output
assign ConfigCommands[7] = 16'h0401;  // Set normal operation (exit shutdown mode)

// Commands used to poll the Max7301
wire[15:0] PollCommands[0:3];
assign PollCommands[0] = 16'hc400;    // Read ports 4-11
assign PollCommands[1] = 16'hcc00;    // Read ports 12-19
assign PollCommands[2] = 16'hd400;    // Read ports 20-27
assign PollCommands[3] = 16'h0000;    // NOP

// Interface to host PC is used for testing (not needed during normal operation)

// Externally-generated write (e.g., from PC)
assign ioexp_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'd0, `REG_IO_EXP}) ? reg_wen : 1'b0;

wire do_reg_io;               // 1 -> processing command (register read or write) from host PC

reg[15:0] reg_wdata_saved;    // Copy of data written from host PC

reg[2:1] read_debug;

reg[3:0] chan_id;             // Last channel ID written by host

// Which channel being addressed by write from host PC
wire[3:0] chan_wdata_id;
assign chan_wdata_id = reg_wdata[19:16];

wire[1:0] chan_wdata;
assign chan_wdata = (chan_wdata_id == IOEXP_ID1) ? 2'd1 :
                    (chan_wdata_id == IOEXP_ID2) ? 2'd2 : 2'd0;

// Latched copy of chan_wdata
reg[1:0] chan_reg;

assign do_reg_io = (chan_reg == 2'd0) ? 1'b0 : 1'b1;

// Data read by host PC (must match last channel ID written by host)
assign reg_rdata = (chan_id == IOEXP_ID1) ?
                      { 3'b010, spi_busy, reg_io_read, do_reg_io, read_error[1], output_error[1],
                      (read_debug[1] ? num_output_error[1] : {~ioexp_cfg_ok[1], ~ioexp_cfg_done[1], 1'b0, IOP1_16_12_error}),
                      read_data_saved } :
                   (chan_id == IOEXP_ID2) ?
                      { 3'b010, spi_busy, reg_io_read, do_reg_io, read_error[2], output_error[2],
                      (read_debug[2] ? num_output_error[2] : {~ioexp_cfg_ok[2], ~ioexp_cfg_done[2], 1'b0, IOP2_16_12_error}),
                      read_data_saved } :
                   32'd0;

// Which channel to configure
wire[1:0] chan_cfg;
assign chan_cfg = ~ioexp_cfg_done[1] ? 2'd1 :
                  ~ioexp_cfg_done[2] ? 2'd2 : 2'd0;

// Which channel to poll
reg[1:0] chan_poll;

// Flags to detect signal changes and trigger output
wire P16_12_changed[1:2];
assign P16_12_changed[1] = (IOP1_16_12 != Shadow_16_12[1]) ? 1'b1 : 1'b0;
assign P16_12_changed[2] = (IOP2_16_12 != Shadow_16_12[2]) ? 1'b1 : 1'b0;

wire P31_28_changed[1:2];
assign P31_28_changed[1] = (IOP1_31_28 != Shadow_31_28[1]) ? 1'b1 : 1'b0;
assign P31_28_changed[2] = (IOP2_31_28 != Shadow_31_28[2]) ? 1'b1 : 1'b0;

always @(posedge clk)
begin
    if (spi_busy) begin
        step <= next_step;
        chan_wen <= 2'd0;
    end
    else if (chan_cfg != 2'd0) begin
        // This section initializes the MAX7301. Note that chan_cfg==2'd0 when both channels
        // have been configured.
        if (step == 4'd8) begin
            step <= 4'd0;
            ioexp_cfg_done[chan_cfg] <= 1'b1;
        end            
        else begin
            // Verify that the MAX7301 is present by reading back the first command.
            // If read_data is equal to the initial command, then the ioexp_cfg_ok flag is set to
            // indicate that the MAX7301 I/O expander has been detected.
            if (step == 4'd2) begin
                //ioexp_cfg_ok[chan_cfg] <= (read_data == ConfigCommands[0]) ? 1'b1 : 1'b0;
                ioexp_cfg_ok[chan_cfg] <= 1'b1;
            end
            write_data <= ConfigCommands[step[2:0]];
            chan_wen <= chan_cfg;
            next_step <= step + 4'd1;
        end
    end
    else if (chan_poll != 2'd0) begin
        // This section reads the inputs from the Max7301. Note that 5 of the inputs [16:12]
        // actually correspond to outputs, so we verify consistency.
        if (step == 4'd4) begin
            // Finished with current channel -- just need to get data (read_data)
            // from prior command.
            if (read_data[15:8] == PollCommands[2][15:8]) begin
                IOP_read[chan_poll][18:11] <= read_data[7:0];    // Ports[27:20] (8)
            end
            else begin
                read_error[chan_poll] <= 1'b1;
            end
            step <= 4'd0;
            if ((chan_poll == 2'd1) && ioexp_cfg_ok[2]) begin
                // Start polling second channel
                chan_poll <= 2'd2;
            end
            else begin
                // All done with polling, reset timer
                chan_poll <= 2'd0;
                poll_timer <= 6'd0;
            end
        end
        else begin
            // Send next poll command. Note that read_data is available
            // two steps later.
            write_data <= PollCommands[step[1:0]];
            chan_wen <= chan_poll;
            next_step <= step + 4'd1;
            if (step == 4'd2) begin
                if (read_data[15:8] == PollCommands[0][15:8]) begin
                    IOP_read[chan_poll][7:0] <= read_data[7:0];   // Ports[11:4] (8)
                end
                else begin
                    read_error[chan_poll] <= 1'b1;
                end
            end
            else if (step == 4'd3) begin
                if (read_data[15:8] == PollCommands[1][15:8]) begin
                    IOP_read[chan_poll][10:8] <= read_data[7:5]; // Ports[19:17] (3)
                    // Check that outputs [16:12] are correct
                    if (chan_poll == 2'd1)
                        IOP1_16_12_error <= read_data[4:0]^Shadow_16_12[1];
                    else
                        IOP2_16_12_error <= read_data[4:0]^Shadow_16_12[2];
                    if ((read_data[4:0]^Shadow_16_12[chan_poll]) != 5'd0) begin
                        num_output_error[chan_poll] <= num_output_error[chan_poll] + 8'd1;
                    end
                end
                else begin
                    read_error[chan_poll] <= 1'b1;
                end
            end
        end
    end
    else if (chan_reg != 2'd0) begin
        // This section handles commands from host PC
        if (step == 4'd0) begin
            write_data <= reg_wdata_saved;
            chan_wen <= chan_reg;
            // Save read data for host
            spi_save <= reg_wdata_saved[15];
            next_step <= 4'd1;
        end
        else begin
            chan_reg <= 2'd0;
            spi_save <= 1'b0;
            step <= 4'd0;
        end
    end
    // Following 4 sections output data if any changes are detected
    else if (ioexp_cfg_ok[1] & P16_12_changed[1]) begin
        write_data <= { 8'h4c, 3'h0, IOP1_16_12 };
        Shadow_16_12[1] <= IOP1_16_12;
        chan_wen <= 2'd1;
    end
    else if (ioexp_cfg_ok[2] & P16_12_changed[2]) begin
        write_data <= { 8'h4c, 3'h0, IOP2_16_12 };
        Shadow_16_12[2] <= IOP2_16_12;
        chan_wen <= 2'd2;
    end
    else if (ioexp_cfg_ok[1] & P31_28_changed[1]) begin
        write_data <= { 8'h5c, 4'h0, IOP1_31_28 };
        Shadow_31_28[1] <= IOP1_31_28;
        chan_wen <= 2'd1;
    end
    else if (ioexp_cfg_ok[2] & P31_28_changed[2]) begin
        write_data <= { 8'h5c, 4'h0, IOP2_31_28 };
        Shadow_31_28[2] <= IOP2_31_28;
        chan_wen <= 2'd2;
    end
    else begin
        // IDLE state (not writing or reading)
        chan_wen <= 2'd0;
        spi_save <= 1'b0;
        step <= 4'd0;
        next_step <= 4'd0;

        if (ioexp_cfg_ok[1]|ioexp_cfg_ok[2]) begin
            // Poll timer waits for about 1.3 usec before starting next poll
            poll_timer <= poll_timer + 6'd1;
            if (poll_timer == 6'h3f) begin
                chan_poll <= ioexp_cfg_ok[1] ? 2'd1 : 2'd2;
            end
        end
    end

    // Always check for register writes from host and set corresponding flag (chan_reg)
    // The flag will not be acted upon until spi_busy is false.
    if (ioexp_reg_wen) begin
        // Following handles external writes (e.g., from PC).
        // Note that the write will be ignored if another write is pending.
        // We do not check ioexp_cfg_ok so that the external PC can
        // still attempt to write to MAX7301 even if it was not detected.
        //   reg_wdata[31]     1 --> clear errors
        //   reg_wdata[30]     1 --> switch to debug data
        //   reg_wdata[19:16]  I/O expander ID
        //   reg_wdata[15:0]   Command to I/O expander (if upper bits clear)
        chan_id <= chan_wdata_id;
        if ((chan_reg == 2'd0) && (chan_wdata != 2'd0)) begin
            if (reg_wdata[31]) begin
                read_error[chan_wdata] <= 1'b0;
                num_output_error[chan_wdata] <= 8'd0;
            end
            read_debug[chan_wdata] <= reg_wdata[30];
            // If upper 12 bits clear, send command to I/O expander
            if (reg_wdata[31:20] == 12'd0) begin
                reg_wdata_saved <= reg_wdata[15:0];
                chan_reg <= chan_wdata;
            end
        end
    end
end

endmodule
