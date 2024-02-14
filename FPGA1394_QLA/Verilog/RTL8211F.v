/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************
 *
 * Copyright(C) 2022-2024 Johns Hopkins University.
 *
 * Module: RTL8211F
 *
 * Purpose: Link layer interface to RTL8211F Ethernet PHY
 *
 * MDC: Clock from FPGA to RTL8211F
 *      Low/high time must be at least 32 ns
 *      Period must be at least 80 ns
 * MDIO: Bidirectional data line, relative to rising MDC
 *      Setup/hold time must be at least 10 ns
 *      MDIO valid within 300 ns when driven by PHY
 *
 * Given the long MDIO valid time, use a clock period of
 * ~320 nsec (16 sysclks)
 *
 * Revision history
 *     04/30/22    Peter Kazanzides    Initial revision
 */

`include "Constants.v"

module RTL8211F
    #(parameter[3:0] CHANNEL = 4'd1)
(
    input  wire clk,               // input clock

    input  wire[15:0] reg_raddr,   // read address
    input  wire[15:0] reg_waddr,   // write address
    output wire[31:0] reg_rdata,   // register read data
    input  wire[31:0] reg_wdata,   // register write data 
    input  wire reg_wen,           // reg write enable
    input  wire reg_wen_ctrl,      // write enable to Ethernet control register

    output reg RSTn,               // Reset to RTL8211F (active low)
    input wire IRQn,               // Interrupt from RTL8211F (active low), FPGA V3.1+
    output reg resetActive,        // Indicates that reset is active

    // MDIO signals
    // When connecting directly to PHY, only need MDIO (inout) and
    // MDC, but when using GMII to RGMII core, it is necessary to
    // use MDIO_I, MDIO_O and MDIO_T instead of MDIO.
    output wire MDC,               // Clock to RTL8211F
    input wire MDIO_I,             // Input from PHY
    output reg MDIO_O,             // Output to PHY
    output reg MDIO_T,             // Tristate control
    output wire mdioBusy,          // 1 -> MDIO busy processing request

    output reg linkOK,             // 1 -> link on
    output reg[1:0] linkSpeed,     // 00 -> 10Mbps, 01 -> 100 Mbps, 10 -> 1000 Mbps

    input wire[1:0] clock_speed,   // Clock speed (Rx), detected by gmii_to_rgmii
    input wire[1:0] speed_mode,    // Speed mode (Tx), detected by gmii_to_rgmii

    // Feedback bits
    output wire[7:0] eth_status,      // Ethernet status bits
    output reg hasIRQ,                // 1 -> PHY IRQn available (FPGA V3.1+)

    output reg clearErrors            // Clear error flags  (TODO: No longer used)
);

initial RSTn = 1'b1;

initial MDIO_T = 1'b1;

reg initOK;                 // 1 -> Initialization successful

// ----------------------------------------------------------------------------
// MDIO (management) interface

// State machine
localparam[2:0]
    ST_MDIO_IDLE = 0,
    ST_MDIO_WRITE_PREAMBLE = 1,
    ST_MDIO_WRITE_DATA = 2,
    ST_MDIO_READ_TA = 3,
    ST_MDIO_READ_DATA = 4;

reg[2:0] mdioState;
initial  mdioState = ST_MDIO_IDLE;

reg[8:0] cnt;            // 9-bit counter
assign MDC = cnt[3];     // MDC toggles every 8 clocks (160 ns)

// Timing:
//    MDC period = 16 clocks (cnt[3:0])
//    Rising edges after cnt = 7, 23, 39, ... 7+16*N, where N=0,1,...
//    MDIO write setup at least 1 count before rising edge,
//        might as well make it 4 counts (cnt[3:0] == `WRITE_SETUP)
//    MDIO write hold at least 1 count after rising edge
//    MDIO read 15 clocks after rising edge (cnt[3:0] == `READ_READY)
//
// Packet length: 64  (cnt[9:4])
//    Preamble (32) + ST (2) + OP (2) + PHYAD (5) + REGAD (5) + TA (2) + DATA (16)
//
// We use a 9-bit counter, with the upper 5 bits counting output bits (0..31) and the
// lower 4 bits driving the waveforms (rising edge at 7, falling edge at 15).
//
// Because we are writing 64 bits, we run through the counter twice -- first for
// the 32-bit preamble and then for the remaining 32-bits.

`define WRITE_SETUP  3
`define READ_READY   6   // Wrap-around from 7 to 6 (15 counts)

reg mdioRequest;         // 1 -> Request MDIO transaction (write_data was set)
assign mdioBusy = (mdioState == ST_MDIO_IDLE) ? 1'b0 : 1'b1;

// For MDIO requests from PC
reg mdioRequest_pending;
reg[31:0] write_data_pending;
reg[31:0] mdio_result;

// Following is the 32-bits of data written to the RTL8211F after the preamble.
// Note that for a read command, the last 18 bits (TA + DATA) are ignored and
// handled in separate states (ST_MDIO_READ_TA and ST_MDIO_READ_DATA).
reg[31:0] write_data;

// Following is the 16-bits of data read from the RTL8211F (read commands only)
reg[15:0] read_data;
// Register address for read
reg[4:0] read_reg_addr;

// Whether a read command
wire isRead;
assign isRead = (write_data[29:28] == 2'b10) ? 1'b1 : 1'b0;

// PHY address
wire[4:0] phyAddr;
assign phyAddr = write_data[27:23];

// Register address
wire[4:0] regAddr;
assign regAddr = write_data[22:18];

// -----------------------------------------
// command processing
// ------------------------------------------
always @(posedge(clk))
begin

    if (mdioState != ST_MDIO_IDLE)
        cnt <= cnt + 9'd1;

    case (mdioState)

    ST_MDIO_IDLE:
        begin
            MDIO_T <= 1'b1;
            cnt <= 9'd0;
            if (mdioRequest) begin
                // write_data already set by caller
                MDIO_T <= 1'b0;
                MDIO_O <= 1'b1;
                mdioState <= ST_MDIO_WRITE_PREAMBLE;
            end
        end

    ST_MDIO_WRITE_PREAMBLE:
        begin
            if (cnt == {5'd31, 4'hf})
                mdioState <= ST_MDIO_WRITE_DATA;
            // cnt == 9'd0 when moving to ST_MDIO_WRITE_DATA
        end

    ST_MDIO_WRITE_DATA:
        begin
            if (cnt[3:0] == `WRITE_SETUP) begin
                MDIO_O <= write_data[~cnt[8:4]];
            end
            if (isRead && (cnt == {5'd13, 4'hf}))
                mdioState <= ST_MDIO_READ_TA;
            else if (cnt == {5'd31, 4'hf})
                mdioState <= ST_MDIO_IDLE;
        end

    ST_MDIO_READ_TA:
        begin
            if (cnt[3:0] == `WRITE_SETUP) begin
                MDIO_T <= 1'b1;
            end
            if (cnt == {5'd15, 4'hf}) begin
                read_reg_addr <= regAddr;
                mdioState <= ST_MDIO_READ_DATA;
            end
        end

    ST_MDIO_READ_DATA:
        begin
            if (cnt[3:0] == `READ_READY)
                read_data <= {read_data[14:0], MDIO_I};
            if (cnt == {5'd31, 4'hf})
                mdioState <= ST_MDIO_IDLE;
        end

    default:
        // Could note this as an error
        mdioState <= ST_MDIO_IDLE;

    endcase // case (mdioState)
end

// ----------------------------------------------------------------------------
// MDIO state machine
// ----------------------------------------------------------------------------

localparam[3:0]
    ST_IDLE = 4'd0,
    ST_RESET_ASSERT = 4'd1,         // assert reset (low) -- 10 msec
    ST_RESET_WAIT = 4'd2,           // wait after bringing reset high -- at least 50 msec
    ST_RUN_PROGRAM_EXECUTE = 4'd3,
    ST_WAIT_MDIO_RESULT = 4'd4,
    ST_INIT_CHECK_CHIPID1 = 4'd5,
    ST_INIT_CHECK_CHIPID2 = 4'd6,
    ST_GET_PHYSR_DATA = 4'd7,
    ST_SET_GMII_SPEED = 4'd8;

reg[3:0] state = ST_RESET_ASSERT;

localparam[4:0]
        ADDR_BMCR = 5'd0,       // Basic Mode Control Register, page 0
        ADDR_PHYID1 = 5'd2,     // PHY Identifier Register 1, page 0
        ADDR_PHYID2 = 5'd3,     // PHY Identifier Register 2, page 0
        ADDR_INER = 5'd18,      // Interrupt Enable Register, page 0xa42
        ADDR_PHYSR = 5'd26,     // PHY Specific Status Register, page 0xa43
        ADDR_INSR = 5'd29,      // Interrupt Status Register, page 0xa43
        ADDR_PAGSR = 5'd31;     // Page Select Register, 0xa43

// Speed bits in BMCR (and GMII control register)
`define SPEED_LSB 13
`define SPEED_MSB  6

//***************************************************************************************
// Microcode for RTL8211F register access
//
// A simple microcode is defined to streamline access to the RTL8211F registers.
//
// The instruction length is 27 bits, defined as follows:
// | R/W (1) | Phy (5) | Reg (5) | Data (16) |
// |    26   |  25:21  |  20:16  |   15:0    |
//
// Bit 26      Write (0) or Read (1)
// Bits 25:21  PHY address (00001 for RTL8211F, 01000 for RGMII-to-GMII)
// Bits 20:16  Address of register to read or write
// Bits 15:0   Data to write to register; for Read commands, the 4 LSB indicate
//             the next state

`define READ_BIT 26
`define PHY_BITS 25:21
`define REG_BITS 20:16
`define PHY_REG_BITS 25:16
`define DATA_BITS 15:0
`define NEXT_BITS 3:0

localparam CMD_WRITE = 1'b0,        // Write to register
           CMD_READ  = 1'b1;        // Read from register

localparam[4:0] PHY_RTL  = 5'd1,    // PHY address for RTL8211F
                PHY_GMII = 5'd8;    // PHY address for GMII core

// Program for initialization (0-10) and IRQ handler (4-10)
reg[26:0] RunProgram[0:10];
reg[3:0] runPC;    // Program counter for RunProgram

localparam[3:0] PC_RESET_BEGIN = 4'd0,   // Program counter for starting reset handler
                PC_IRQ_BEGIN = 4'd4,     // Program counter for starting IRQ handler
                PC_END = 4'd10;          // End (also used for MDIO requests from PC)

initial begin
    // Read Chip ID1 (should be 001c)
    RunProgram[0] = {CMD_READ,  PHY_RTL, ADDR_PHYID1, 12'd0, ST_INIT_CHECK_CHIPID1};
    // Read Chip ID2 (should be c916)
    RunProgram[1] = {CMD_READ,  PHY_RTL, ADDR_PHYID2, 12'd0, ST_INIT_CHECK_CHIPID2};
    // Change page to 0xa42 to access INER
    RunProgram[2] = {CMD_WRITE, PHY_RTL, ADDR_PAGSR, 16'h0a42};
    // Enable link change interrupt
    RunProgram[3] = {CMD_WRITE, PHY_RTL, ADDR_INER, 16'h0010};
    // Change page to 0xa43 to access INSR
    RunProgram[4] = {CMD_WRITE, PHY_RTL, ADDR_PAGSR, 16'h0a43};
    // Read interrupt status register (clears interrupt)
    RunProgram[5] = {CMD_READ,  PHY_RTL, ADDR_INSR, 12'd0, ST_RUN_PROGRAM_EXECUTE};
    // Read PHYSR to get link status
    RunProgram[6] = {CMD_READ,  PHY_RTL, ADDR_PHYSR, 12'd0, ST_GET_PHYSR_DATA};
    // Change page to 0 to access BMCR (might not be necessary)
    RunProgram[7] = {CMD_WRITE, PHY_RTL, ADDR_PAGSR, 16'd0};
    // Read BMCR to get speed bits, which are used to update RunProgram[9]
    // Note that speed bits are also available in PHYSR.
    RunProgram[8] = {CMD_READ,  PHY_RTL, ADDR_BMCR, 12'd0, ST_SET_GMII_SPEED};
    // Write speed bits to GMII core register 16 (ST_SET_GMII_SPEED updates the data field)
    RunProgram[9] = {CMD_WRITE, PHY_GMII, 5'd16, 16'd0};
    // Change page to 0xa42 since that is the default page (probably not necessary)
    RunProgram[10] = {CMD_WRITE, PHY_RTL, ADDR_PAGSR, 16'h0a42};
end

reg[23:0] initCount;
reg resetRequest;            // 1 -> Request PHY reset
reg[7:0] numReset;           // Number of times reset called
reg[7:0] numIRQ;             // Number of times IRQ handler called

reg IRQn_latched;            // 1 -> IRQn synchronized with sysclk
reg IRQn_disable;            // 1 -> disable handling of IRQn
reg IRQ_sw;                  // 1 -> software-generated IRQ (active high)
reg IRQ_cs;                  // 1 -> IRQ generated by change in Rx clock_speed

// Following is to generate an interrupt (IRQ_cs) for FPGA V3.0,
// which does not have the hardware IRQn.
reg[1:0] clock_speed_latch1;
reg[1:0] clock_speed_latch2;

// validChannel is used when the implementation only supports 2 channels
wire validChannel;
assign validChannel = ((CHANNEL == 4'd1) || (CHANNEL == 4'd2)) ? 1'b1 : 1'b0;

// Bit offset within status register (0 for Eth1, 8 for Eth2)
localparam BIT_OFFSET = 8*(CHANNEL-1);

always @(posedge(clk))
begin

    // Synchronize IRQn with clk
    IRQn_latched <= IRQn;

    // Generate IRQ_cs for boards without IRQ (~hasIRQ)
    clock_speed_latch1 <= clock_speed;
    clock_speed_latch2 <= clock_speed_latch1;
    if (clock_speed_latch1 != clock_speed_latch2) begin
        IRQ_cs <= initOK&(~hasIRQ);
    end

    // Write to Ethernet status register
    if (reg_wen_ctrl) begin
        // Ignore reset request if already in reset
        resetRequest <= validChannel&reg_wdata[26]&reg_wdata[BIT_OFFSET+7]&RSTn;
        IRQn_disable <= validChannel&reg_wdata[27]&reg_wdata[BIT_OFFSET+6];
        IRQ_sw <= validChannel&reg_wdata[28]&reg_wdata[BIT_OFFSET+5];
        clearErrors <= validChannel&reg_wdata[28]&reg_wdata[BIT_OFFSET+4];
    end
    else begin
        clearErrors <= 0;
    end

    // Request write to RTL8211F register via MDIO, address = 4xa0,
    // where x is channel number.
    // Store it as pending and handle it when in IDLE state.
    if (reg_wen && (reg_waddr[3:0] == 4'd0)) begin
        write_data_pending <= reg_wdata;
        mdioRequest_pending <= 1;
    end

    case (state)

    ST_IDLE:
    begin
        initCount <= 24'd0;
        if (resetRequest) begin
            state <= ST_RESET_ASSERT;
        end
        else if (mdioRequest_pending) begin
            // Allow MDIO write even if initOK is false (could be useful for debugging)
            write_data <= write_data_pending;
            mdioRequest <= 1'b1;
            state <= ST_WAIT_MDIO_RESULT;
            runPC <= PC_END;
        end
        else if (initOK) begin
            if (((~IRQn_latched)&(~IRQn_disable)) | IRQ_sw | IRQ_cs) begin
                // Link change interrupt: clear interrupt,then read speed bits from
                // RTL8211F BMCR register and write them to GMII control register.
                state <= ST_RUN_PROGRAM_EXECUTE;
                runPC <= PC_IRQ_BEGIN;
                numIRQ <= numIRQ + 8'd1;
            end
        end
    end

    //******************* RESET STATES ***********************
    ST_RESET_ASSERT:
    begin
        if (initCount == 24'd491520) begin  // 10 ms (49.152 MHz sysclk)
            state <= ST_RESET_WAIT;
            RSTn <= 1;   // Remove the reset
            resetRequest <= 1'b0;
            numReset <= numReset + 8'd1;
        end
        else begin
            RSTn <= 0;
            initOK <= 0;
            resetActive <= 1;
            initCount <= initCount + 24'd1;
        end
    end

    ST_RESET_WAIT:
    begin
        // Wait until IRQn is asserted (low). Experimentally, this
        // seems to take about 160 ms, so we have a timeout at
        // 0xFFFFFF (340 msec).
        if ((initCount == 24'hFFFFFF) || (~IRQn_latched)) begin
            hasIRQ <= ~IRQn_latched;
            resetActive <= 0;
            state <= ST_RUN_PROGRAM_EXECUTE;
            runPC <= PC_RESET_BEGIN;
        end
        else begin
            initCount <= initCount + 21'd1;
        end
    end

    ST_RUN_PROGRAM_EXECUTE:
    begin
        write_data <= { 2'b01, RunProgram[runPC][`READ_BIT], ~RunProgram[runPC][`READ_BIT],
                        RunProgram[runPC][`PHY_REG_BITS], 2'b10,
                        RunProgram[runPC][`DATA_BITS] };
        mdioRequest <= 1'b1;
        state <= ST_WAIT_MDIO_RESULT;
    end

    ST_WAIT_MDIO_RESULT:
    begin
        if (mdioRequest&mdioBusy) begin
            mdioRequest <= 1'b0;
        end
        else if (~(mdioRequest|mdioBusy)) begin
            if (runPC == PC_END) begin
                state <= ST_IDLE;
                if (mdioRequest_pending) begin
                    mdio_result <= { 5'd0, mdioState, 3'd0, read_reg_addr, read_data};
                end
                mdioRequest_pending <= 1'b0;
                IRQ_sw <= 1'b0;
                IRQ_cs <= 1'b0;
            end
            else begin
                state <= RunProgram[runPC][`READ_BIT] ? RunProgram[runPC][`NEXT_BITS]
                         : ST_RUN_PROGRAM_EXECUTE;
                runPC <= runPC + 4'd1;
            end
        end
    end

    ST_INIT_CHECK_CHIPID1:
    begin
        // ChipID1 should be 001c; if not, go to IDLE
        state <= (read_data == 16'h001c) ? ST_RUN_PROGRAM_EXECUTE : ST_IDLE;
    end

    ST_INIT_CHECK_CHIPID2:
    begin
        // ChipID2 should be c916; if not, go to IDLE
        state <= (read_data == 16'hc916) ? ST_RUN_PROGRAM_EXECUTE : ST_IDLE;
        initOK <= (read_data == 16'hc916) ? 1'b1 : 1'b0;
    end

    ST_GET_PHYSR_DATA:
    begin
        linkOK <= read_data[2];
        linkSpeed <= read_data[5:4];
        state <= ST_RUN_PROGRAM_EXECUTE;
    end

    ST_SET_GMII_SPEED:
    begin
        RunProgram[runPC][`SPEED_LSB] <= read_data[`SPEED_LSB];
        RunProgram[runPC][`SPEED_MSB] <= read_data[`SPEED_MSB];
        state <= ST_RUN_PROGRAM_EXECUTE;
    end

    default:
    begin
        // Could note this as an error
        state <= ST_IDLE;
    end

    endcase
end

// Ethernet status bits for this port
//assign eth_status = { initOK, hasIRQ, linkOK, linkSpeed, recv_fifo_error, send_fifo_overflow, ps_eth_enable };
assign eth_status = { initOK, hasIRQ, linkOK, linkSpeed, 1'b0, 1'b0, 1'b1 };

assign reg_rdata = (reg_raddr[7:0] == 8'ha0) ? mdio_result : 32'd0;

endmodule
