/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2011-2023 ERC CISST, Johns Hopkins University.
 *
 * This module serially shifts samples out to 4 LTC2601 DACs set up in a chain.
 * Transfers are initiated by a trigger signal. Commands for each dac are read
 * from an external memory one word at a time, so memory addresses are updated
 * during a transfer to obtain the appropriate word at the appropriate time.
 *
 * Theory of operation:
 *     - Each LTC2601 requires a 32-bit sequence consisting of:
 *        8 bits ignored: Value = 00
 *        4 bits command: Value = 03 (write & update) or 07 (nop)
 *        4 bits ignored: Value = 00 (NOTE: address for LTC2604)
 *       16 bits of data
 *     - csel must be low before the first sclk+ and after the last sclk-.
 *     - data is changed on sclk-, in preparation for the next sclk+.
 *     - On trig, seqn is set to 0x100 and counts up till rollover (256 counts)
 *     - sclk is the LSB of seqn, so 128 sclks shift out 4x 32-bit words
 *
 * Starting with QLA 1.5, it is possible to use one LTC2604 Quad DAC instead of
 * 4 LTC2601 DACs. The operation is almost identical -- the primary difference is
 * that it is necessary to toggle /CS (csel) between the data for each LTC2604 channel.
 * To do this, we take advantage of the fact that the LTC supports both 24-bit
 * and 32-bit word transfers. The LTC2601s are daisy-chained and therefore must
 * use 32-bit word transfers, but the LTC2604 can use multiple 24-bit transfers.
 * Thus, for the LTC2604, it is only necessary to deassert /CS (csel) for the
 * first 8 bits of each 32-bit transfer.
 *
 * Revision history
 *     07/15/10                        Initial revision - MfgTest
 *     10/26/11    Paul Thienphrapa    Initial revision
 *     06/27/22    Peter Kazanzides    Modified to also support LTC2604
 *     12/17/22    Peter Kazanzides    Parameterized with NUM_CS
 */

`define SEQN_INIT 9'h100      // 9-bit counter init (from 256 to rollover)
`define SEQN_WORD 5'b11111    // command word boundary (every 64th count)
`define SEQN_DONE 9'h1ff      // final value of count sequence

module LTC2601x4
    #(parameter NUM_CS = 1)           // Number of CS (chip select) and MOSI
(
    input wire clkin,                 // system clock
    input wire trig,                  // initiates sample transfers
    input wire[(32*NUM_CS-1):0] word, // 32-bit command word(s) from external memory
    output wire[3:0] addr,            // address of command word in external memory
    output wire sclk,                 // clock to sync transfers bits with DACs
    output wire[NUM_CS:1] csel,       // signal to frame transfers to the DACs
    output wire[NUM_CS:1] mosi,       // serial data line into the DACs
    output wire busy,                 // indicates transfer is in progress
    output wire flush,                // signal to flush command word to nop
    input wire[NUM_CS:1] isQuadDac    // type of DAC: 0 = 4xLTC2601, 1 = 1xLTC2604
);

    reg CSn;         // chip select for 4xLTC2601
    reg CSQn;        // chip select for 1xLTC2604
    initial CSn = 1'b1;
    initial CSQn = 1'b1;

    // local wires and registers
    reg[8:0] seqn;            // 9-bit counter for sequencing operation
    wire start;               // true if transfer is starting
    wire word_edge;           // true if transfer is at command word boundary

    // state machine
    reg state;
    localparam
        ST_IDLE=0,
        ST_LOOP=1;

    initial state = ST_IDLE;

// -----------------------------------------------------------------------------
// hardware description
//

assign sclk = seqn[0];
assign busy = (state == ST_LOOP) ? 1'b1 : 1'b0;

assign addr = seqn[7:6] + word_edge;
assign flush = ((seqn[5:1]==5'b01111) ? 1'b1 : 1'b0);
assign word_edge = ((seqn[5:1]==`SEQN_WORD) ? 1'b1 : 1'b0);
assign start = (state == ST_IDLE) ? trig : 1'b0;

// state machine
always @(posedge(clkin))
begin

    // spi interface to dac
    case (state)

    // idle state
    ST_IDLE: begin
        seqn <= `SEQN_INIT;              // starting state of counter
        if (trig) begin                  // write trigger detected
            CSn <= 1'b0;                 // signal start of transfer (for LTC2601)
            state <= ST_LOOP;            // go to transfer loop state
        end
        else begin                       // idle state conditions
            CSn <= 1'b1;
            CSQn <= 1'b1;
            state <= ST_IDLE;
        end
    end

    // spi transfer loop
    ST_LOOP: begin
        seqn <= seqn + 1'b1;             // counter, also creates sclk
        if (sclk == 1'b1) begin          // update data on falling sclk
            if (word_edge) begin
                // For LTC2604, need to deassert /CS (CSQn) at start of each word
                CSQn <= 1'b1;
            end
            if (seqn[5:1] == 5'b00111) begin
                // For LTC2604, need to assert /CS (CSQn) 16 counts (8 SCLKs) later.
                // For LTC2601, /CS (CSn) is already asserted (0)
                CSQn <= 1'b0;
           end
        end
        if (seqn == `SEQN_DONE) begin    // transfer complete
            CSn <= trig;                 // finalize transfer, if necessary
            CSQn <= trig;                // finalize transfer, if necessary
            state <= ST_IDLE;            // go back to idle state
        end
    end

    // shouldn't get here
    default: begin
        state <= ST_IDLE;
    end

    endcase
end

genvar i;
generate
for (i = 1; i <= NUM_CS; i = i+1) begin : mosi_loop

    // Set chip select based on DAC type
    assign csel[i] = isQuadDac[i] ? CSQn : CSn;

    reg[31:0] data;               // capture of input command words

    assign mosi[i] = data[31];

    always @(posedge(clkin))
    begin
        if (start) begin
            data <= word[(32*i-1):(32*(i-1))]; // latch first command word
        end
        else if (sclk) begin
            data <= word_edge ? word[(32*i-1):(32*(i-1))] : (data<<1);
        end
        // Original implementation set data to 0 at end,
        // but this is not necessary.
    end
end
endgenerate

endmodule
