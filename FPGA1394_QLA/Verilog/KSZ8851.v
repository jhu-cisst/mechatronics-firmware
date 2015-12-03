/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2014-2015 ERC CISST, Johns Hopkins University.
 *
 * This module is the interface to the KSZ8851-16mll Ethernet MAC/PHY chip.
 * Note that 0.05s is needed to warm up the device before any IO operation.
 *
 * Revision history
 *     08/14/14    Long Qian (as Initialization.v and RegIO.v)
 *     11/06/15    Peter Kazanzides
 */

`include "Constants.v"

// --------------------------------------------------------------------------
// Register Address Translator: from 8-bit offset to 16-bit address required by KSZ8851.
// The addressing is a bit unusual when the KSZ8851 is configured with a 16-bit bus;
// specifically, it appears to split the I/O space into 32-bit chunks. The 4 ByteEnable
// lines can select any one or two 8-bit registers from this 32-bit chunk. For an
// 8-bit transfer, only one ByteEnable should be set. For a 16-bit transfer, the most
// typical scenario would be to select the first two bytes (ByteEnable=4'b0011) or
// the last two bytes (ByteEnable=4'b1100).
// --------------------------------------------------------------------------
module getAddr(
    input wire[7:0] offset,     // register address (0x00-0xFF)
    input wire length,          // length: 0-byte(8-bit), 1-word(16-bit)
    output wire[15:0] Addr      // address recognized by ksz8851 (on SD lines)
    );
    
    // the rule of translation is available in the step-by-step guide of ksz8851-16mll
    wire[1:0] offsetTail;
    assign offsetTail = offset[1:0];

    // SD[15:12]  are for BE[3:0] (BE = Byte Enable)
    // The following code does not handle 16-bit transfers for odd addresses (i.e.,
    // if offsetTail is 1 or 3).
    //   BE[0]=1 if address is multiple of 4 (0x00, 0x04, 0x08, ...)
    //   BE[1]=1 if 16-bit access and multiple of 4 OR 8-bit access and odd (0x01, 0x03, ...)
    //   BE[2]=1 if address has 2 (0x02, 0x06, 0x0A, ...)
    //   BE[3]=1 if 16-bit access and has 2 OR 8-bit access and has 3
    assign Addr[12] = (offsetTail==0) ? 1'b1 : 1'b0;
    assign Addr[13] = ((~length && offsetTail==1) || (length && offsetTail==0)) ? 1'b1 : 1'b0;
    assign Addr[14] = (offsetTail==2) ? 1'b1 : 1'b0;
    assign Addr[15] = ((~length && offsetTail==3) || (length && offsetTail==2)) ? 1'b1 : 1'b0;  
    assign Addr[7:2] = offset[7:2];
    
    assign Addr[1:0] = offsetTail;  // not necessary, for better integrity
    assign Addr[11:8] = 4'h0;       // not necessary, for better integrity
    
endmodule

module KSZ8851(
    // global clock and reset
    input      sysclk,
    input      reset,

    // interface to KSZ8851
    output reg ETH_RSTn,  // chip reset (active low)
    output reg ETH_CMD,   // 0 for data, 1 for address
    output reg ETH_RDn,   // read strobe (active low)
    output reg ETH_WRn,   // write strobe (active low)
    inout[15:0] SD,       // address/data bus
    input wire ETH_IRQn,  // interrupt request
    input wire ETH_PME,   // power management event

    output wire[31:0] eth_result,

    input  wire reg_wen,             // write enable
    input  wire[15:0] reg_waddr,     // write address
    input  wire[31:0] reg_wdata      // write data
);

// tri-state bus configuration
// Drive bus except when ETH_RDn is active (low)
reg[15:0] SDReg;
assign SD = ETH_RDn ? SDReg : 16'hz;

// address decode for KSZ8851 I/O access
wire   eth_reg_wen;
assign eth_reg_wen = (reg_waddr == {`ADDR_MAIN, 8'h0, `REG_ETHRES}) ? reg_wen : 1'b0;

// Following registers hold address/data for requested register reads/writes
reg[7:0]  eth_addr;   // I/O register address (0-0xFF)
reg       isWord;     // Data length (0->byte, 1->word)
reg[15:0] eth_data;   // Data to/from KSZ8851
reg       isWrite;    // Write (1) or Read (0)

// Address translator
wire[15:0] Addr16;
getAddr newAddr(
    .offset(eth_addr),
    .length(isWord),
    .Addr(Addr16)
);

reg eth_error;        // I/O request received when not in idle state
reg[3:0] state;
reg[20:0] count;

// For reading
// VALID(1) 0(6) ERROR(1) PME(1) IRQ(1) State(4) Data(16)
assign eth_result[31] = 1'b1;         // 31: 1 -> Ethernet is present
assign eth_result[30] = eth_error;    // 30: 1 -> error occurred
assign eth_result[29:22] = 8'b0;      // 29-22: 0 (unused)
assign eth_result[21] = ETH_PME;      // 21: Power Management Event
assign eth_result[20] = ETH_IRQn;     // 20: Interrupt request
assign eth_result[19:16] = state;     // 19-16: Current state
assign eth_result[15:0] = eth_data;   // 15-0: Last data read or written

// KSZ8851 timing:
//    RDn, WRn pulses must be kept low for 40 ns (min)
//    RDn to read data valid is 32 ns (max)

// state machine states
parameter[3:0]
    ST_IDLE = 0,
    ST_RESET_ASSERT = 1,    // assert reset (low) -- 10 msec
    ST_RESET_WAIT = 2,      // wait after bringing reset high -- 50 msec
    ST_ADDR_START = 3,
    ST_ADDR_HOLD = 4,
    ST_ADDR_END = 5,
    ST_READ_START = 6,
    ST_READ_HOLD = 7,
    ST_READ_END = 8,
    ST_WRITE_START = 9,
    ST_WRITE_HOLD = 10,
    ST_WRITE_END = 11;

always @(posedge sysclk or negedge reset) begin
    if (reset == 0) begin
        count <= 0;            // Clear counter
        state <= ST_RESET_ASSERT;
    end
    else begin

        // Format of 32-bit reg_wdata:
        // 0(4) DMA(1) Reset(1) R/W(1) W/B(1) Addr(8) Data(16)
        if (eth_reg_wen) begin
            if (reg_wdata[26]) begin   // if reset
                count <= 0;            // Clear counter
                state <= ST_RESET_ASSERT;
            end
            else if (state == ST_IDLE) begin
                isWord <= reg_wdata[24];
                eth_addr <= reg_wdata[23:16];
                eth_data <= reg_wdata[15:0];
                eth_error <= 0;
                isWrite <= reg_wdata[25];
                // If DMA bit (reg_wdata[27]) is set, next state is either ST_WRITE_START or ST_READ_START;
                // otherwise, starting state is ST_ADDR_START
                state <= (reg_wdata[27] ? (reg_wdata[25] ? ST_WRITE_START : ST_READ_START) : ST_ADDR_START);
            end
            else begin
                eth_error <= 1;
            end
        end

        case (state)

        ST_IDLE:
        begin
        end

        // Assert the reset and wait 10 ms before removing it.
        ST_RESET_ASSERT:
        begin
            if (count == 21'd491520) begin  // 10 ms (49.152 MHz sysclk)
                ETH_RSTn <= 1;   // Remove the reset
                count <= 0;
                state <= ST_RESET_WAIT;
            end
            else begin
                ETH_RSTn <= 0;
                ETH_WRn <= 1;
                ETH_RDn <= 1;
                count <= count + 1;
            end
        end

        // The reset has ended, wait 50 ms before doing anything else
        ST_RESET_WAIT:
        begin
            if (count == 21'h1FFFFF) begin
                count <= 0;
                state <= ST_IDLE;
            end
        else
            count <= count + 1;
        end

        ST_ADDR_START:
        begin
            ETH_CMD <= 1;
            ETH_WRn <= 0;
            SDReg <= Addr16;
            state <= ST_ADDR_HOLD;
        end

        ST_ADDR_HOLD:
        begin
           state <= ST_ADDR_END;
        end

        ST_ADDR_END:
        begin
            ETH_WRn <= 1;
            state <= isWrite ? ST_WRITE_START : ST_READ_START;
        end

        ST_WRITE_START:
        begin
            ETH_CMD <= 0;
            ETH_WRn <= 0;
            SDReg <= eth_data;
            state <= ST_WRITE_HOLD;
        end

        ST_WRITE_HOLD:
        begin
           state <= ST_WRITE_END;
        end

        ST_WRITE_END:
        begin
            ETH_WRn <= 1;
            state <= ST_IDLE;
        end

        ST_READ_START:
        begin
            ETH_CMD <= 0;
            ETH_RDn <= 0;
            state <= ST_READ_HOLD;
        end

        ST_READ_HOLD:
        begin
           state <= ST_READ_END;
        end

        ST_READ_END:
        begin
            ETH_RDn <= 1;
            eth_data <= SD;
            state <= ST_IDLE;
        end

        endcase
    end
end

endmodule
