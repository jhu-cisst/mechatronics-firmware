/*******************************************************************************
 *
 * Copyright(C) 2011-2020 ERC CISST, Johns Hopkins University.
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

`define SEQN_INIT 9'h100      // 9-bit counter init (from 256 to rollover) --> count from 256 to 512
`define SEQN_WORD 5'b11111    // command word boundary (every 64th count) --> used to set the word_edge
`define SEQN_DONE 9'h1ff      // final value of count sequence

module LTC2601x4(
    input wire clkin,         // system clock
    input wire trig,          // initiates sample transfers
    input wire[31:0] word,    // 32-bit command word from external memory
    output wire[3:0] addr,    // address of command word in external memory
    output wire sclk,         // clock to sync transfers bits with DACs
    output reg csel,          // signal to frame transfers to the DACs
    output wire mosi,         // serial data line into the DACs
    output wire busy,         // indicates transfer is in progress
    output wire flush         // signal to flush command word to nop
);

    initial csel = 1'b1;

    // local wires and registers
    reg[8:0] seqn;            // 9-bit counter for sequencing operation
    reg[31:0] data;           // capture of input command words
    wire word_edge;           // true if transfer is at command word boundary

    // state machine
    reg state;
    parameter
        ST_IDLE=0,
        ST_LOOP=1;

    initial state = ST_IDLE;

// -----------------------------------------------------------------------------
// hardware description
//

assign sclk = seqn[0];
assign mosi = data[31];
assign busy = ~csel;

assign addr = seqn[7:6] + word_edge; //seqn[7:6] increase every 64th time
assign flush = ((seqn[5:1]==5'b01111) ? 1'b1 : 1'b0); // if [5:1] is 15 (every 64nd sclk = every 128th clk) --> then 1, else 0
assign word_edge = ((seqn[5:1]==`SEQN_WORD) ? 1'b1 : 1'b0); // 2 sclks before seqn[7:6] is incrased by one, the seqn[5:1] is 5'b11111

// state machine
always @(posedge(clkin))
begin

    // spi interface to dac
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
            data <= (word_edge ? word : (data<<1)); //if every counter reached the threshold (every 64th time), a new value is loaded, otherwise serially shift out
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

endmodule
