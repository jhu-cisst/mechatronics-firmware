/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2014-2016 ERC CISST, Johns Hopkins University.
 *
 * This module implements the higher-level Ethernet I/O, which interfaces
 * to the KSZ8851 MAC/PHY chip.
 *
 * Revision history
 *     12/21/15    Peter Kazanzides
 */

// global constant e.g. register & device address
`include "Constants.v"

module EthernetIO(
    // global clock and reset
    input wire sysclk,
    input wire reset,

    // board id (rotary switch)
    input wire[3:0] board_id,

    // KSZ8851 interrupt
    input wire ETH_IRQn,          // interrupt request

    // Debugging
    output wire[31:16] eth_status,
    input wire sendReq,
    output reg sendAck,
    input wire ksz_isIdle,

    // Interface to board registers
    input wire[31:0] reg_rdata,
    output reg[15:0] reg_raddr,
    output reg       eth_read_en,
    output reg[31:0] reg_wdata,
    output reg[15:0] reg_waddr,
    output reg       eth_write_en,
    output reg       eth_block_en,
    output reg       eth_block_start,

    // Interface to lower layer (KSZ8851)
    input wire initReq,           // 1 -> Chip has been reset; initialization requested
    output reg initAck,           // 1 -> Acknowledge (clear) initReq
    output reg cmdReq,            // 1 -> higher-level requesting a command
    input wire cmdAck,            // 1 -> command accepted (can request next command)
    input wire readValid,         // 1 -> ReadData is valid
    output reg isDMA,             // 1 -> DMA mode active
    output reg isWrite,           // 0 -> Read, 1 -> Write
    output reg isWord,            // 0 -> Byte, 1 -> Word
    output reg[7:0] RegAddr,      // Register address (N/A for DMA mode)
    output reg[15:0] WriteData,   // Data to be written to chip (N/A for read)
    input wire[15:0] ReadData,    // Data read from chip (N/A for write)
    output reg initOK,            // 1 -> Initialization successful
    output reg ethIoError,        // 1 -> Ethernet I/O error
    input wire eth_error,         // 1 -> I/O request received when not in idle state

    output reg lreq_trig,         // trigger signal for a FireWire phy request
    output reg[2:0] lreq_type     // type of request to give to the FireWire phy    
);

parameter num_channels = 4;

// Current state and next state
reg[5:0] state;
reg[5:0] nextState;
   
// state machine states
parameter[5:0]
    ST_IDLE = 6'd0,
    ST_WAIT_ACK = 6'd1,
    ST_WAIT_ACK_CLEAR = 6'd2,
    ST_INIT_CHECK_CHIPID = 6'd3,      // Read chip ID
    ST_INIT_WRITE_MAC_LOW = 6'd4,     // Write MAC address low
    ST_INIT_WRITE_MAC_MID = 6'd5,     // Write MAC address middle
    ST_INIT_WRITE_MAC_HIGH = 6'd6,    // Write MAC address high
    ST_INIT_REG_84 = 6'd7,
    ST_INIT_REG_70 = 6'd8,
    ST_INIT_REG_86 = 6'd9,
    ST_INIT_REG_9C = 6'd10,
    ST_INIT_REG_74 = 6'd11,
    ST_INIT_MULTICAST = 6'd12,
    ST_INIT_REG_82 = 6'd13,
    ST_INIT_IRQ_CLEAR = 6'd14,
    ST_INIT_IRQ_ENABLE = 6'd15,
    ST_INIT_TRANSMIT_ENABLE_READ = 6'd16,
    ST_INIT_TRANSMIT_ENABLE_WRITE = 6'd17,
    ST_INIT_RECEIVE_ENABLE_READ = 6'd18,
    ST_INIT_RECEIVE_ENABLE_WRITE = 6'd19,
    ST_INIT_DONE = 6'd20,
    ST_RECEIVE_CLEAR_RXIS = 6'd21,
    ST_RECEIVE_FRAME_COUNT_START = 6'd22,
    ST_RECEIVE_FRAME_COUNT_END = 6'd23,
    ST_RECEIVE_FRAME_STATUS = 6'd24,
    ST_RECEIVE_FRAME_LENGTH = 6'd25,
    ST_RECEIVE_DMA_STATUS_READ = 6'd26,
    ST_RECEIVE_DMA_STATUS_WRITE = 6'd27,
    ST_RECEIVE_DMA_SKIP = 6'd28,
    ST_RECEIVE_DMA_FRAME_HEADER = 6'd29,
    ST_RECEIVE_DMA_FIREWIRE_PACKET = 6'd30,
    ST_RECEIVE_FLUSH_START = 6'd31,
    ST_RECEIVE_FLUSH_EXECUTE = 6'd32,
    ST_RECEIVE_FLUSH_WAIT_START = 6'd33,
    ST_RECEIVE_FLUSH_WAIT_CHECK = 6'd34,
    ST_SEND_DMA_STATUS_READ = 6'd35,
    ST_SEND_DMA_STATUS_WRITE = 6'd36,
    ST_SEND_DMA_CONTROLWORD = 6'd37,
    ST_SEND_DMA_BYTECOUNT = 6'd38,
    ST_SEND_DMA_DESTADDR = 6'd39,
    ST_SEND_DMA_SRCADDR = 6'd40,
    ST_SEND_DMA_LENGTH = 6'd41,
    ST_SEND_DMA_PACKETDATA_HEADER = 6'd42,
    ST_SEND_DMA_PACKETDATA_QUAD = 6'd43,
    ST_SEND_DMA_PACKETDATA_BLOCK_START = 6'd44,
    ST_SEND_DMA_PACKETDATA_BLOCK_MAIN = 6'd45,
    ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL = 6'd46,
    ST_SEND_DMA_PACKETDATA_BLOCK_PROM = 6'd47,
    ST_SEND_DMA_PACKETDATA_CHECKSUM = 6'd48,
    ST_SEND_DMA_STOP_READ = 6'd49,
    ST_SEND_DMA_STOP_WRITE = 6'd50,
    ST_SEND_TXQ_ENQUEUE_START = 6'd51,
    ST_SEND_TXQ_ENQUEUE_END = 6'd52,
    ST_SEND_TXQ_ENQUEUE_WAIT_START = 6'd53,
    ST_SEND_TXQ_ENQUEUE_WAIT_CHECK = 6'd54;

// Debugging support

assign eth_io_isIdle = (state == ST_IDLE) ? 1 : 0;

// Keep track of areas where state machine may wait
// for unknown amount of time (for debugging)
parameter[1:0]
    WAIT_NONE = 0,
    WAIT_ACK = 1,
    WAIT_ACK_CLEAR = 2,
    WAIT_FLUSH = 3;

reg[1:0] waitInfo;

// Following flags are set based on the destination address. Note that a
// a FireWire broadcast packet will set both isLocal and isRemote.
reg isLocal;       // 1 -> FireWire packet should be processed locally
reg isRemote;      // 1 -> FireWire packet should be forwarded

reg quadRead;
reg quadWrite;
reg blockRead;
reg blockWrite;
reg isMulticast;

// VALID(1) 0(6) ERROR(1) PME(1) IRQ(1) State(4) Data(16)
assign eth_status[31] = 1'b1;          // 31: 1 -> Ethernet is present
assign eth_status[30] = eth_error;     // 30: 1 -> error occurred
assign eth_status[29] = initOK;        // 29: 1 -> Initialization OK
assign eth_status[28] = initReq;       // 28: 1 -> Reset executed, init requested
assign eth_status[27] = ethIoError;    // 27: 1 -> ethernet I/O error (higher layer)
//assign eth_status[26] = cmdReq;        // 26: 1 -> command requested by higher level
//assign eth_status[25] = cmdAck;        // 25: 1 -> command acknowledged by lower level
assign eth_status[26] = isLocal;       // 26: 1 -> command requested by higher level
assign eth_status[25] = isRemote;      // 25: 1 -> command acknowledged by lower level
assign eth_status[24] = quadRead;      // 24: quadRead (debugging)
assign eth_status[23] = quadWrite;     // 23: quadWrite (debugging)
assign eth_status[22] = blockRead;     // 22: blockRead (debugging)
assign eth_status[21] = blockWrite;    // 21: blockWrite (debugging)
assign eth_status[20] = isMulticast;   // 20: multicast received
assign eth_status[19] = ksz_isIdle;    // 19: KSZ8851 state machine is idle
assign eth_status[18] = eth_io_isIdle; // 18: Ethernet I/O state machine is idle
assign eth_status[17:16] = waitInfo;   // 17-16: Wait points in EthernetIO.v

reg[7:0] FrameCount;   // Number of received frames
reg[4:0] count;        // General use counter
reg[3:0] readCount;    // Wait for read valid
reg[4:0] maxCount;     // For reading FireWire packets
reg[2:0] next_addr;    // Address of next device (for block read)

reg[15:0] destMac[0:2];  // Not currently used
reg[15:0] srcMac[0:2];
reg[15:0] Length;        // Not currently used

// Firewire packet received from host
//    - 16 bytes (8 words) for quadlet read request
//    - 20 bytes (10 words) for quadlet write
//    - (24+block_data_length) bytes for block write
//      - currently, block_data_length = 4*4 = 16
//      - thus, max size in words is 20
// Consider making this 32-bit.
reg[15:0] FireWirePacket[0:19];  // FireWire packet memory (max 20 words)

wire[3:0] fw_tcode;            // FireWire transaction code
wire[5:0] fw_tl;               // FireWire transaction label
wire[15:0] block_data_length;  // Data length (in bytes) for block read/write requests

assign fw_tcode = FireWirePacket[1][15:12];
assign fw_tl = FireWirePacket[1][7:2];
assign block_data_length = {FireWirePacket[6][7:0], FireWirePacket[6][15:8]};

// TEMP: Timestamp copied from Firewire.v -- should consolidate
reg[31:0] timestamp;          // timestamp counter register
reg ts_reset;                 // timestamp counter reset signal
// -------------------------------------------------------
// Timestamp
// -------------------------------------------------------
// timestamp counts number of clocks between block reads
always @(posedge(sysclk) or posedge(ts_reset) or negedge(reset))
begin
    if (reset==0 || ts_reset)
        timestamp <= 0;
    else
        timestamp <= timestamp + 1'b1;
end

always @(posedge sysclk or negedge reset) begin
    if (reset == 0) begin
       cmdReq <= 0;
       isDMA <= 0;
       isWrite <= 0;
       isWord <= 1;   // all transfers are word
       state <= ST_IDLE;
       nextState <= ST_IDLE;
       initAck <= 0;
       initOK <= 0;
       ethIoError <= 0;
       isMulticast <= 0;
       isLocal <= 0;
       isRemote <= 0;
       quadRead <= 0;
       quadWrite <= 0;
       blockRead <= 0;
       blockWrite <= 0;
       sendAck <= 0;
       srcMac[0] <= 16'd0;
       srcMac[1] <= 16'd0;
       srcMac[2] <= 16'd0;
       Length <= 16'd0;
       eth_read_en <= 0;
       eth_write_en <= 0;
       eth_block_en <= 0;
       eth_block_start <= 0;
       ts_reset <= 0;
       waitInfo <= WAIT_NONE;
       lreq_trig <= 0;
       lreq_type <= 0;
    end
    else begin

       case (state)

         ST_IDLE:
         begin
            isDMA <= 0;
            isWord <= 1;       // all transfers are word
            eth_read_en <= 0;
            eth_write_en <= 0;
            eth_block_en <= 0;
            eth_block_start <= 0;
            waitInfo <= WAIT_NONE;
            if (initReq) begin
               cmdReq <= 1;
               isWrite <= 0;
               RegAddr <= 8'hC0;  // Read Chip ID
               state <= ST_WAIT_ACK;
               nextState <= ST_INIT_CHECK_CHIPID;
               initAck <= 1;
               initOK <= 0;
               ethIoError <= 0;
            end
            else if (~ETH_IRQn) begin
               cmdReq <= 1;
               isWrite <= 0;
               RegAddr <= 8'h92;
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_CLEAR_RXIS;
            end
            else if (sendReq) begin
               // Not yet used. Will need this mechanism in the future,
               // but will need a way to specify what is to be sent
               // (e.g., FireWirePacket).
               state <= ST_SEND_DMA_STATUS_READ;
               sendAck <= 1;
            end
         end

         ST_WAIT_ACK:
         begin
            if (initReq && !initAck)
               state <= ST_IDLE;
            else if (cmdAck) begin
               cmdReq <= 0;
               state <= ST_WAIT_ACK_CLEAR;
               readCount <= 4'd0;
            end
            else if (!cmdReq)
               state <= ST_WAIT_ACK_CLEAR;
            else
               waitInfo <= WAIT_ACK;
         end

         ST_WAIT_ACK_CLEAR:
         begin
            if (initReq && !initAck)
               state <= ST_IDLE;
            else if (~cmdAck) begin
               if (isWrite || readValid) begin
                   state <= nextState;
                   waitInfo <= WAIT_NONE;
               end
               else begin
                  // Shouldn't take more than 12 cycles to read data.
                  if (readCount == 4'hf) begin
                     ethIoError <= 1;
                     // Moving to IDLE state may not be the best action,
                     // since there may be some cleanup needed, such as
                     // getting out of DMA mode.
                     state <= ST_IDLE;
                     waitInfo <= WAIT_NONE;
                  end
                  readCount <= readCount + 4'd1;
               end
            end
            else
                waitInfo <= WAIT_ACK_CLEAR;
         end
         
         //*************** States for initializing Ethernet ******************

         ST_INIT_CHECK_CHIPID:
         begin
            initAck <= 0;   // By now, it is fine to finish acknowledgement of init request
            if (ReadData[15:4] == 12'h887) begin
               // Chip ID is ok, go to next state
               // (could have started next state here, but code would be less readable)
               state <= ST_INIT_WRITE_MAC_LOW;
            end
            else begin
               initOK <= 0;
               state <= ST_IDLE;
            end
         end
         
         ST_INIT_WRITE_MAC_LOW:
         begin
            cmdReq <= 1;
            isWrite <= 1;
            RegAddr <= 8'h10;                 // MAC address low
            WriteData <= {12'h940,board_id};  //   0x940n (n = board id)
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_WRITE_MAC_MID;
         end

         ST_INIT_WRITE_MAC_MID:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h12;       // MAC address mid
            WriteData <= 16'h0E13;  //   0x0E13
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_WRITE_MAC_HIGH;
         end
         
         ST_INIT_WRITE_MAC_HIGH:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h14;       // MAC address high
            WriteData <= 16'hFA61;  //   0xFA61
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_84;
         end
              
         ST_INIT_REG_84:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h84;
            WriteData <= 16'h4000;   // Enable QMU transmit frame data pointer auto increment
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_70;
         end

         ST_INIT_REG_70:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h70;
            WriteData <= 16'h01EE;   // Enable QMU transmit flow control, CRC, and padding
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_86;
         end

         ST_INIT_REG_86:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h86;
            // Enable QMU receive frame data pointer auto increment and decrease write data
            // valid sample time to 4 nS (max).
            WriteData <= 16'h5000;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_9C;
         end

         ST_INIT_REG_9C:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h9C;
            WriteData <= 16'h0001;   // Configure receive frame threshold for 1 frame
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_74;
         end

         ST_INIT_REG_74:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h74;
            // 7: enable UDP, TCP, and IP checksums
            // C: enable MAC address filtering, enable flow control (for receive in full duplex mode)
            // E: enable broadcast, multicast, and unicast
            // Bit 4 = 0, Bit 1 = 0, Bit 11 = 1, Bit 8 = 0 (hash perfect, default)
            WriteData <= 16'h7CE0;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_MULTICAST;
         end

         ST_INIT_MULTICAST:
         begin
            cmdReq <= 1;
            // Following are hard-coded values for which hash register to use and which bit to set
            // for multicast address FB:61:0E:13:19:FF. This is obtained by computing the CRC for
            // this MAC address and then using the first two (most significant) bits to determine
            // the register and the next four bits to determine which bit to set.
            // See code in mainEth1394.cpp.
            RegAddr <= 8'hA2;   // MAHTR1
            WriteData <= 16'h0008;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_REG_82;
         end

         ST_INIT_REG_82:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h82;
            WriteData <= 16'h0020;   // Enable QMU frame count threshold (1), no auto-dequeue
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_IRQ_CLEAR;
         end

         ST_INIT_IRQ_CLEAR:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h92;
            WriteData <= 16'hFFFF;   // Clear all pending interrupts
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_IRQ_ENABLE;
         end

         ST_INIT_IRQ_ENABLE:
         begin
            cmdReq <= 1;
            RegAddr <= 8'h90;
            WriteData <= 16'h2000;   // Enable receive interrupts (TODO: also consider link change interrupt)
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_TRANSMIT_ENABLE_READ;
         end

         ST_INIT_TRANSMIT_ENABLE_READ:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h70;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_TRANSMIT_ENABLE_WRITE;
         end

         ST_INIT_TRANSMIT_ENABLE_WRITE:
         begin
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= {ReadData[15:1],1'b1};
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_RECEIVE_ENABLE_READ;
         end

         ST_INIT_RECEIVE_ENABLE_READ:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h74;
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_RECEIVE_ENABLE_WRITE;
         end

         ST_INIT_RECEIVE_ENABLE_WRITE:
         begin
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= {ReadData[15:1],1'b1};
            state <= ST_WAIT_ACK;
            nextState <= ST_INIT_DONE;
         end


         ST_INIT_DONE:
         begin
            initOK <= 1;
            state <= ST_IDLE;
         end

         //*************** States for receiving Ethernet packets ******************

         ST_RECEIVE_CLEAR_RXIS:
         begin
            if (ReadData[13] == 1'b1) begin   // RXIS asserted
               cmdReq <= 1;
               isWrite <= 1;
               // RegAddr is already set to 8'h92
               WriteData <= 16'h2000;  // clear interrupt
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_FRAME_COUNT_START;
            end
            else begin
               state <= ST_IDLE;
            end
         end

         ST_RECEIVE_FRAME_COUNT_START:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h9C;
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_FRAME_COUNT_END;
         end

         ST_RECEIVE_FRAME_COUNT_END:
         begin
            FrameCount <= ReadData[15:8];
            if (ReadData[15:8] == 0)
               state <= ST_IDLE;
            else begin
               cmdReq <= 1;
               RegAddr <= 8'h7C;
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_FRAME_STATUS;
            end
         end

         ST_RECEIVE_FRAME_STATUS:
         begin
            FrameCount <= FrameCount-8'd1;
            quadRead <= 0;
            quadWrite <= 0;
            blockRead <= 0;
            blockWrite <= 0;
            isLocal <= 0;
            isRemote <= 0;
            if (ReadData[15]) begin // if valid
               cmdReq <= 1;
               isMulticast <= ReadData[6];
               isWrite <= 0;
               RegAddr <= 8'h7E;
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_FRAME_LENGTH;
            end
            else begin
               state <= ST_RECEIVE_FLUSH_START;
            end
         end

         ST_RECEIVE_FRAME_LENGTH:
         begin
            // Probably don't need the following
            // PacketWords <= ((ReadData[11:0]+12'd3)>>1)&12'hffe;
            // Set QMU RXQ frame pointer to 0
            cmdReq <= 1;
            isWrite <= 1;
            RegAddr <= 8'h86;
            WriteData <= 16'h5000;
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_DMA_STATUS_READ;
         end
         
         ST_RECEIVE_DMA_STATUS_READ:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h82;
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_DMA_STATUS_WRITE;
         end

         ST_RECEIVE_DMA_STATUS_WRITE:
         begin
            // Enable DMA transfers
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= {ReadData[15:4],1'b1,ReadData[2:0]};
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_DMA_SKIP;
            count <= 5'd0;
         end

         ST_RECEIVE_DMA_SKIP:
         begin
            // Skip first 3 words in the packet (ignore, status, byte-count)
            cmdReq <= 1;
            isDMA <= 1;
            isWrite <= 0;
            state <= ST_WAIT_ACK;
            if (count[1:0] == 2'd3) begin
               nextState <= ST_RECEIVE_DMA_FRAME_HEADER;
               count[1:0] <= 2'd0;
            end
            else begin
               nextState <= ST_RECEIVE_DMA_SKIP;
               count[1:0] <= count[1:0]+2'd1;
            end
         end

         ST_RECEIVE_DMA_FRAME_HEADER:
         begin
            // Read dest MAC, source MAC, and length (7 words, byte-swapped).
            // Don't byte swap srcMAC because we need to send it back byte-swapped.
            case (count[2:0])
              3'd0: destMac[0] <= {ReadData[7:0],ReadData[15:8]};
              3'd1: destMac[1] <= {ReadData[7:0],ReadData[15:8]};
              3'd2: destMac[2] <= {ReadData[7:0],ReadData[15:8]};
              3'd3: srcMac[0] <= ReadData;
              3'd4: srcMac[1] <= ReadData;
              3'd5: srcMac[2] <= ReadData;
              3'd6: Length <= {ReadData[7:0],ReadData[15:8]};
            endcase
            if (count[2:0] == 3'd6) begin
               // Check for packets of expected length and ignore (flush) others; note that
               // we cannot use Length below because it is not yet updated
               if (ReadData[7:0] == 8'd0) begin
                  if (ReadData[15:8] == 8'd16) begin       // quadlet read request
                     cmdReq <= 1;
                     state <= ST_WAIT_ACK;
                     nextState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
                     maxCount <= 5'd7;
                  end
                  else if (ReadData[15:8] == 8'd20) begin  // quadlet write or block read request
                     cmdReq <= 1;
                     state <= ST_WAIT_ACK;
                     nextState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
                     maxCount <= 5'd9;
                  end
                  else if (ReadData[15:8] == 8'd40) begin  // block write (6+4 quadlets)
                     cmdReq <= 1;
                     state <= ST_WAIT_ACK;
                     nextState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
                     maxCount <= 5'd19;
                     eth_block_start <= 1;
                  end
                  else begin
                     state <= ST_RECEIVE_FLUSH_START;
                  end
               end
               else begin
                  state <= ST_RECEIVE_FLUSH_START;
               end
               count <= 5'd0;
            end
            else begin
               cmdReq <= 1;
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_DMA_FRAME_HEADER;
               count[2:0] <= count[2:0]+3'd1;
            end
         end

         ST_RECEIVE_DMA_FIREWIRE_PACKET:
         begin
            // Read FireWire packet; don't byteswap because
            // FireWire is also big endian.
            FireWirePacket[count] <= ReadData;
            // Clear block started signal (replicates FireWire.v implementation)
            eth_block_start <= 0;
            if (count == maxCount) begin
               state <= ST_RECEIVE_FLUSH_START;
               // In parallel, can start processing FireWire packet (for writes)
               if (isLocal) begin
                  if (fw_tcode == `TC_QREAD) begin
                     quadRead <= 1;
                  end
                  else if (fw_tcode == `TC_QWRITE) begin
                     quadWrite <= 1;
                     reg_waddr <= {FireWirePacket[5][7:0], FireWirePacket[5][15:8]};
                     reg_wdata <= {FireWirePacket[6][7:0], FireWirePacket[6][15:8],
                                   FireWirePacket[7][7:0], FireWirePacket[7][15:8]};
                     // Special case: write to FireWire PHY register
                     if ({FireWirePacket[5][7:0], FireWirePacket[5][15:8]} == {`ADDR_MAIN, 8'h0, `REG_PHYCTRL}) begin
                        // check the RW bit to determine access type (bit 12, after byte-swap)
                        lreq_type <= (FireWirePacket[7][4] ? `LREQ_REG_WR : `LREQ_REG_RD);
                        lreq_trig <= 1;
                     end
                  end
                  else if (fw_tcode == `TC_BREAD) begin
                     blockRead <= 1;
                  end
                  else if (fw_tcode == `TC_BWRITE) begin
                      blockWrite <= 1;
                      // For now, hard-code as write to ADDR_MAIN
                      reg_waddr[15:12] <= `ADDR_MAIN;
                      reg_waddr[7:4] <= 4'd1;  // start with channel 1
                      reg_waddr[3:0] <= `OFF_DAC_CTRL;
                      // MSB is "valid" bit
                      eth_write_en <= FireWirePacket[10][7];
                      reg_wdata[15:0] <= {FireWirePacket[11][7:0], FireWirePacket[11][15:8]};
                  end
                  else begin
                     ethIoError <= 1;
                  end
               end
               if (isRemote) begin
               end
            end
            else if (count == 5'd0) begin
               // Check the destination of this packet
               if ({ReadData[7:0],ReadData[15:12]} == 12'hFFC) begin
                  // all ok, keep going
                  // Handle Ethernet multicast as a direct write to this board (i.e., local
                  // only); this could change in the future.
                  if (isMulticast || (ReadData[11:8] == board_id)) begin
                     isLocal <= 1;
                     isRemote <= 0;
                  end
                  else if (ReadData[11:8] == 4'hf) begin  // Firewire broadcast (maybe 8'hff?)
                     isLocal <= 1;
                     isRemote <= 1;
                  end
                  else begin
                     isLocal <= 0;
                     isRemote <= 1;
                  end
                  cmdReq <= 1;
                  state <= ST_WAIT_ACK;
                  nextState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
                  count <= 5'd1;
               end
               else begin
                  // invalid destination address, flush packet
                  state <= ST_RECEIVE_FLUSH_START;
               end
            end
            else begin
               cmdReq <= 1;
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_DMA_FIREWIRE_PACKET;
               count <= count + 5'd1;
            end
         end

         ST_RECEIVE_FLUSH_START:
         begin
            cmdReq <= 1;
            isDMA <= 0;
            isWrite <= 0;
            RegAddr <= 8'h82;
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_FLUSH_EXECUTE;
            if (quadWrite) begin
               eth_write_en <= 1;
               eth_block_en <= 1;
            end
            else if (blockWrite) begin
               reg_waddr[7:4] <= 4'd2;
               // MSB is "valid" bit
               eth_write_en <= FireWirePacket[12][7];
               reg_wdata[15:0] <= {FireWirePacket[13][7:0], FireWirePacket[13][15:8]};
            end
         end

         ST_RECEIVE_FLUSH_EXECUTE:
         begin
            // Flush the rest of the packet (also clears DMA bit)
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= {ReadData[15:4],1'b0,ReadData[2:1],1'b1};
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_FLUSH_WAIT_START;
            if (quadWrite) begin
               eth_write_en <= 0;
               eth_block_en <= 0;
               lreq_trig <= 0;     // Clear lreq_trig in case it was set
            end
            else if (blockWrite) begin
               reg_waddr[7:4] <= 4'd3;
               // MSB is "valid" bit
               eth_write_en <= FireWirePacket[14][7];
               reg_wdata[15:0] <= {FireWirePacket[15][7:0], FireWirePacket[15][15:8]};
            end
         end

         ST_RECEIVE_FLUSH_WAIT_START:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            // RegAddr is already set to 8'h82
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_FLUSH_WAIT_CHECK;
            if (blockWrite) begin
               reg_waddr[7:4] <= 4'd4;
               // MSB is "valid" bit
               eth_write_en <= FireWirePacket[16][7];
               reg_wdata[15:0] <= {FireWirePacket[17][7:0], FireWirePacket[17][15:8]};
               eth_block_en <= 1;
            end
         end

         ST_RECEIVE_FLUSH_WAIT_CHECK:
         begin
            // Wait for bit 0 in Register 0x82 to be cleared; then
            //   - if a read command, start sending response (check FrameCount after send complete)
            //   - else if more frames available, receive status of next frame
            //   - else go to idle state
            // TODO: check node id and forward via FireWire if necessary
            if (ReadData[0] == 1'b0) begin
              if (quadRead || blockRead)
                 state <= ST_SEND_DMA_STATUS_READ;
              else
                 state <= (FrameCount == 8'd0) ? ST_IDLE : ST_RECEIVE_FRAME_STATUS;
              if (blockWrite) begin
                 // Already did write in parallel with flush
                 eth_write_en <= 0;
                 eth_block_en <= 0;
               end
               waitInfo <= WAIT_NONE;
            end
            else begin
               state <= ST_RECEIVE_FLUSH_WAIT_START;
               waitInfo <= WAIT_FLUSH;
            end
         end

         //*************** States for sending Ethernet packets ******************
         // First, should check if enough memory on QMU TXQ

         ST_SEND_DMA_STATUS_READ:  // same as ST_RECEIVE_DMA_STATUS_READ
         begin
            sendAck <= 0;  // TEMP
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h82;
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_STATUS_WRITE;
         end

         ST_SEND_DMA_STATUS_WRITE:  // same as ST_RECEIVE_DMA_STATUS_WRITE
         begin
            // Enable DMA transfers
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= {ReadData[15:4],1'b1,ReadData[2:0]};
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_CONTROLWORD;
         end

         ST_SEND_DMA_CONTROLWORD:
         begin
            cmdReq <= 1;
            isDMA <= 1;
            WriteData <= 16'h0;  // Control word = 0
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_BYTECOUNT;
         end

         ST_SEND_DMA_BYTECOUNT:
         begin
            cmdReq <= 1;
            // Set byte count:
            //   + 34 for quadlet read response (14+20)
            //   + (14+24+block_data_length) for block read response
            //     (block_data_length must be a multiple of 4)
            WriteData <= quadRead ? 16'd34 : (16'd38 + block_data_length);
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_DESTADDR;
            count <= 5'd0;
         end

         ST_SEND_DMA_DESTADDR:
         begin
            cmdReq <= 1;
            WriteData <= srcMac[count[1:0]];
            state <= ST_WAIT_ACK;
            if (count[1:0] == 2'd2) begin
               nextState <= ST_SEND_DMA_SRCADDR;
               count[1:0] <= 2'd0;
            end
            else begin
               nextState <= ST_SEND_DMA_DESTADDR;
               count[1:0] <= count[1:0]+2'd1;
            end
         end

         ST_SEND_DMA_SRCADDR:
           begin
            // Rather than using destAddr from last received packet,
            // use our own MAC addr.
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            if (count[1:0] == 2'd0) begin
               WriteData <= 16'h61FA;    // 0xFA61 (byte-swapped)
               nextState <= ST_SEND_DMA_SRCADDR;
               count[1:0] <= 2'd1;
            end
            else if (count[1:0] == 2'd1) begin
               WriteData <= 16'h130E;    // 0x0E13 (byte-swapped)
               nextState <= ST_SEND_DMA_SRCADDR;
               count[1:0] <= 2'd2;
            end
            else if (count[1:0] == 2'd2) begin
               WriteData <= {4'h0,board_id,8'h94};  // 0x940n (n = board id, byte-swapped)
               nextState <= ST_SEND_DMA_LENGTH;
            end
         end

         ST_SEND_DMA_LENGTH:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            count <= 5'd0;
            // 20 bytes for quadlet read response
            // (24 + block_data_length) bytes for block read response
            WriteData <= quadRead ? 16'd20 : (16'd24 + block_data_length);
            nextState <= ST_SEND_DMA_PACKETDATA_HEADER;
         end

         // Send first 5 quadlets, which are nearly identical between quadlet read response
         // and block read response (only difference is tcode).
         ST_SEND_DMA_PACKETDATA_HEADER:
         begin
            cmdReq <= 1;
            case (count[2:0])
               //0:  WriteData <= 16'h0;     // dest-id
               3'd1: WriteData <= {quadRead ? `TC_QRESP : `TC_BRESP, 4'd0, fw_tl, 2'd0};
               //2:  WriteData <= 16'h0;     // src-id
               //3:  WriteData <= 16'h0;     // rcode, reserved
               3'd4: WriteData <= {FrameCount, 8'h2b};     // reserved, but use it for debugging
               3'd5:
                  begin
                     WriteData <= eth_status[31:16]; // normally reserved, but use it for debugging
                     count[2:0] <= 3'd0;
                     reg_raddr <= {FireWirePacket[5][7:0], FireWirePacket[5][15:8]};
                     if (quadRead) begin
                        // Get ready to read data from the board.
                        eth_read_en <= 1;
                        nextState <= ST_SEND_DMA_PACKETDATA_QUAD;
                     end
                     else  // blockRead
                        nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_START;
                  end
               default: WriteData <= 16'h0;
            endcase
            state <= ST_WAIT_ACK;
            if (count[2:0] != 3'd5) begin
               nextState <= ST_SEND_DMA_PACKETDATA_HEADER;
               count[2:0] <= count[2:0]+3'd1;
            end
         end

         ST_SEND_DMA_PACKETDATA_QUAD:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            if (count[0] == 0) begin
               WriteData <= {reg_rdata[23:16], reg_rdata[31:24]};
               count[0] <= 1;
               nextState <= ST_SEND_DMA_PACKETDATA_QUAD;
            end
            else begin
               WriteData <= {reg_rdata[7:0], reg_rdata[15:8]};
               // Stop accessing FPGA registers
               eth_read_en <= 0;
               count[0] <= 0;
               nextState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
            end
         end

         // All block reads start with length, extended_tcode, and header_CRC
         ST_SEND_DMA_PACKETDATA_BLOCK_START:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            if (count[1:0] == 2'd0) begin
                WriteData <= {block_data_length[7:0], block_data_length[15:8]};    // data_length
            end
            else begin
                //1:  WriteData <= 16'h0;     // extended_tcode (0)
                //2:  WriteData <= 16'h0;     // header_CRC
                //3:  WriteData <= 16'h0;     // header_CRC
                WriteData <= 16'h0;
            end
            if (count[1:0] == 2'd3) begin
                count[1:0] <= 2'd0;
                if (reg_raddr[15:12] == `ADDR_MAIN) begin
                   nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_MAIN;
                end
                else if ((reg_raddr[15:12] == `ADDR_PROM) ||
                         (reg_raddr[15:12] == `ADDR_PROM_QLA)) begin
                   // Get ready to read data
                   eth_read_en <= 1;
                   reg_raddr[5:0] <= 6'd0;  // Just to be sure
                   nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_PROM;
                end
                else begin
                   // Abort and let the KSZ8851 chip pad the packet
                   nextState <= ST_SEND_DMA_STOP_READ;
                end
            end
            else begin
                nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_START;
                count[1:0] <= count[1:0]+2'd1;
            end
         end

         ST_SEND_DMA_PACKETDATA_BLOCK_MAIN:
         begin
            cmdReq <= 1;
            case (count[2:0])
              3'd0: WriteData <= {timestamp[23:16], timestamp[31:24]};
              3'd1:
                 begin
                    WriteData <= {timestamp[7:0], timestamp[15:8]};
                    // Reset timestamp
                    ts_reset <= 1;
                    // Get ready to read data from the board.
                    eth_read_en <= 1;
                    reg_raddr <= {12'd0, `REG_STATUS};   // address of status register
                 end
              3'd2:
                 begin
                    WriteData <= {reg_rdata[23:16], reg_rdata[31:24]};  // status
                    ts_reset <= 0;
                 end
              3'd3:
                 begin
                    WriteData <= {reg_rdata[7:0], reg_rdata[15:8]};     // status
                    reg_raddr <= {12'd0, `REG_DIGIN};   // address of digital I/O register
                 end
              3'd4:
                 begin
                    WriteData <= {reg_rdata[23:16], reg_rdata[31:24]};  // digital I/O
                 end
              3'd5:
                 begin
                    WriteData <= {reg_rdata[7:0], reg_rdata[15:8]};     // digital I/O
                    reg_raddr <= {12'd0, `REG_TEMPSNS};  // address of temperature sensors
                 end
              3'd6:
                 begin
                    WriteData <= {reg_rdata[23:16], reg_rdata[31:24]};  // temperature sensors
                 end
              3'd7:
                 begin
                    WriteData <= {reg_rdata[7:0], reg_rdata[15:8]};     // temperature sensors
                    reg_raddr[7:4] <= 4'h1;        // start from channel 1
                    // NOTE: Following is hard-coded to first read from channel 0,
                    //       and then from 5,6,7. This is correct, but less flexible
                    //       than the implementation in Firewire.v, which uses dev_addr[].
                    reg_raddr[3:0] <= 4'd0;        // 1st device address
                    next_addr <= 3'd5;             // set next device address
                 end
              default: WriteData <= 16'h0;
            endcase
            state <= ST_WAIT_ACK;
            if (count[2:0] == 3'd7) begin
                nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL;
                count[2:0] <= 3'd0;
            end
            else begin
                nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_MAIN;
                count[2:0] <= count[2:0]+3'd1;
            end
         end

         ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL:
           begin
              cmdReq <= 1;
              state <= ST_WAIT_ACK;
              if (count[0] == 0) begin
                  count[0] <= 1;
                  WriteData <= {reg_rdata[23:16], reg_rdata[31:24]};
                  nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL;
              end
              else begin
                  count[0] <= 0;
                  WriteData <= {reg_rdata[7:0], reg_rdata[15:8]};
                  if (reg_raddr[7:4] == num_channels) begin
                      if (next_addr == 3'd7) begin
                          eth_read_en <= 0;  // we are done
                          nextState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
                      end
                      else begin
                          reg_raddr[7:4] <= 4'd1;
                          reg_raddr[2:0] <= next_addr;
                          next_addr <= next_addr + 3'd1;
                          nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL;
                      end
                  end
                  else begin
                      reg_raddr[7:4] <= reg_raddr[7:4] + 4'd1;
                      nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_CHANNEL;
                  end
              end
           end

         ST_SEND_DMA_PACKETDATA_BLOCK_PROM:
         begin
            cmdReq <= 1;
            state <= ST_WAIT_ACK;
            if (count[0] == 0) begin
                count[0] <= 1;
                WriteData <= {reg_rdata[23:16], reg_rdata[31:24]};
                nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_PROM;
            end
            else begin
                count[0] <= 0;
                WriteData <= {reg_rdata[7:0], reg_rdata[15:8]};
                reg_raddr[5:0] <= reg_raddr[5:0] + 6'd1;
                // reg_raddr increments quadlets (32-bits), whereas block_data_length
                // is in bytes (8-bits). Note that maximum PROM read is 256 bytes,
                // or 64 quadlets. The second term below takes care of the overflow
                // case in the first term.
                if (((reg_raddr[5:0] + 6'd1) == block_data_length[7:2]) ||
                    (reg_raddr[5:0] == 6'h3f)) begin
                    nextState <= ST_SEND_DMA_PACKETDATA_CHECKSUM;
                    eth_read_en <= 0; // we are done
                end
                else
                    nextState <= ST_SEND_DMA_PACKETDATA_BLOCK_PROM;
            end
         end

         ST_SEND_DMA_PACKETDATA_CHECKSUM:
         begin
            cmdReq <= 1;
            count[0] <= 1;
            WriteData <= 16'd0;    // Checksum currently not set
            state <= ST_WAIT_ACK;
            nextState <= (count[0] == 0) ? ST_SEND_DMA_PACKETDATA_CHECKSUM : ST_SEND_DMA_STOP_READ;
         end

         ST_SEND_DMA_STOP_READ:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            isDMA <= 0;
            RegAddr <= 8'h82;
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_STOP_WRITE;
         end

         ST_SEND_DMA_STOP_WRITE:
         begin
            // Disable DMA transfers
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= {ReadData[15:4],1'b0,ReadData[2:0]};
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_TXQ_ENQUEUE_START;
          end

         ST_SEND_TXQ_ENQUEUE_START:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            RegAddr <= 8'h80;
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_TXQ_ENQUEUE_END;
         end

         ST_SEND_TXQ_ENQUEUE_END:
         begin
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= {ReadData[15:1],1'b1};
            state <= ST_WAIT_ACK;
            // For now, wait for the frame to be transmitted. According to the datasheet,
            // "the software should wait for the bit to be cleared before setting up another
            // new TX frame," so this check could be moved elsewhere for efficiency.
            nextState <= ST_SEND_TXQ_ENQUEUE_WAIT_START;
         end

         ST_SEND_TXQ_ENQUEUE_WAIT_START:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            // RegAddr is already set to 8'h80
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_TXQ_ENQUEUE_WAIT_CHECK;
         end

         ST_SEND_TXQ_ENQUEUE_WAIT_CHECK:
         begin
            // Wait for bit 0 in Register 0x80 to be cleared
            if (ReadData[0] == 1'b0) begin
                state <= (FrameCount == 8'd0) ?  ST_IDLE : ST_RECEIVE_FRAME_STATUS;
            end
            else begin
               state <= ST_SEND_TXQ_ENQUEUE_WAIT_START;
               waitInfo <= WAIT_FLUSH;  // TEMP: use WAIT_FLUSH, but should be WAIT_TXQ_ENQUEUE
            end
         end

         endcase // case (state)
    end
end

endmodule
