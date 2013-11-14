/*******************************************************************************
 *
 * Copyright(C) 2011-2012 ERC CISST, Johns Hopkins University.
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
 *        4 bits ignored: Value = 00
 *       16 bits of data
 *     - csel must be low before the first sclk+ and after the last sclk-.
 *     - data is changed on sclk-, in preparation for the next sclk+.
 *     - On trig, seqn is set to 0x100 and counts up till rollover (256 counts)
 *     - sclk is the LSB of seqn, so 128 sclks shift out 4x 32-bit words
 *
 * Revisionist history
 *     07/15/10                        Initial revision - MfgTest
 *     10/26/11    Paul Thienphrapa    Initial revision
 */

`define SEQN_INIT 9'h100      // 9-bit counter init (from 256 to rollover)
`define SEQN_WORD 5'b11111    // command word boundary (every 64th count)
`define SEQN_DONE 9'h1ff      // final value of count sequence

module LTC2601x4(
    input wire clkin,         // system clock
    input wire reset,         // system reset
    input wire trig,          // initiates sample transfers
    input wire[31:0] word,    // 32-bit command word from external memory
    output wire[3:0] addr,    // address of command word in external memory
    output wire sclk,         // clock to sync transfers bits with DACs
    output reg csel,          // signal to frame transfers to the DACs
    output wire mosi,         // serial data line into the DACs
    output wire busy,         // indicates transfer is in progress
    output wire flush         // signal to flush command word to nop
);

    // local wires and registers
    reg[8:0] seqn;            // 9-bit counter for sequencing operation
    reg[31:0] data;           // capture of input command words
    wire word_edge;           // true if transfer is at command word boundary
//    wire[5:0] count;          // debug

    // state machine
    reg state;
    parameter
        ST_IDLE=0,
        ST_LOOP=1;

// -----------------------------------------------------------------------------
// hardware description
//

assign sclk = seqn[0];
assign mosi = data[31];
assign busy = ~csel;

assign addr = seqn[7:6] + word_edge;
assign flush = ((seqn[5:1]==5'b01111) ? 1'b1 : 1'b0);
assign word_edge = ((seqn[5:1]==`SEQN_WORD) ? 1'b1 : 1'b0);
//assign count = seqn[5:0];   // debug

// state machine
always @(posedge(clkin) or negedge(reset))
begin

    // reset/startup initializes registers
    if (reset == 0) begin
        seqn <= 0;
        csel <= 1'b1;
        data <= 0;
        state <= ST_IDLE;
    end

    // spi interface to dac
    else begin
        case (state)

        // idle state
        ST_IDLE: begin
            seqn <= `SEQN_INIT;              // starting state of counter
            if (trig) begin                  // write trigger detected
                csel <= 1'b0;                // signal start of transfer
                data <= word;                // latch first command word
                state <= ST_LOOP;            // go to transfer loop state
            end
            else begin                       // idle state conditions
                csel <= 1'b1;
                data <= 0;
                state <= ST_IDLE;
            end
        end

        // spi transfer loop
        ST_LOOP: begin
            seqn <= seqn + 1'b1;             // counter, also creates sclk
            if (sclk == 1'b1) begin          // update data on falling sclk
                data <= (word_edge ? word : (data<<1));
            end
            if (seqn == `SEQN_DONE) begin    // transfer complete
                csel <= trig;                // finalize transfer, if necessary
                data <= 0;                   // to keep mosi line clear
                state <= ST_IDLE;            // go back to idle state
            end
        end

        // shouldn't get here
        default: begin
            state <= ST_IDLE;
        end

        endcase
    end
end

endmodule
