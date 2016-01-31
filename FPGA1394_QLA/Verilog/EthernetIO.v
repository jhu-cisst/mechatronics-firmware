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

module EthernetIO(
    // global clock and reset
    input wire sysclk,
    input wire reset,

    // board id (rotary switch)
    input wire[3:0] board_id,

    // KSZ8851 interrupt
    input wire ETH_IRQn,          // interrupt request

    // Debugging
    input wire receiveEnabled,
    output reg quadRead,
    output reg quadWrite,
    input wire sendReq,
    output reg sendAck,

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
    output reg ethIoError         // 1 -> Ethernet I/O error
);

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
    ST_INIT_REG_82 = 6'd12,
    ST_INIT_IRQ_CLEAR = 6'd13,
    ST_INIT_IRQ_ENABLE = 6'd14,
    ST_INIT_TRANSMIT_ENABLE_READ = 6'd15,
    ST_INIT_TRANSMIT_ENABLE_WRITE = 6'd16,
    ST_INIT_RECEIVE_ENABLE_READ = 6'd17,
    ST_INIT_RECEIVE_ENABLE_WRITE = 6'd18,
    ST_INIT_DONE = 6'd19,
    ST_RECEIVE_CLEAR_RXIS = 6'd20,
    ST_RECEIVE_FRAME_COUNT_START = 6'd21,
    ST_RECEIVE_FRAME_COUNT_END = 6'd22,
    ST_RECEIVE_FRAME_STATUS = 6'd23,
    ST_RECEIVE_FRAME_LENGTH = 6'd24,
    ST_RECEIVE_DMA_STATUS_READ = 6'd25,
    ST_RECEIVE_DMA_STATUS_WRITE = 6'd26,
    ST_RECEIVE_DMA_SKIP = 6'd27,
    ST_RECEIVE_DMA_FRAME_HEADER = 6'd28,
    ST_RECEIVE_FLUSH_START = 6'd29,
    ST_RECEIVE_FLUSH_EXECUTE = 6'd30,
    ST_RECEIVE_FLUSH_WAIT_START = 6'd31,
    ST_RECEIVE_FLUSH_WAIT_CHECK = 6'd32,
    ST_SEND_DMA_STATUS_READ = 6'd33,
    ST_SEND_DMA_STATUS_WRITE = 6'd34,
    ST_SEND_DMA_CONTROLWORD = 6'd35,
    ST_SEND_DMA_BYTECOUNT = 6'd36,
    ST_SEND_DMA_DESTADDR = 6'd37,
    ST_SEND_DMA_SRCADDR = 6'd38,
    ST_SEND_DMA_LENGTH = 6'd39,
    ST_SEND_DMA_PACKETDATA = 6'd40,
    ST_SEND_DMA_STOP_READ = 6'd41,
    ST_SEND_DMA_STOP_WRITE = 6'd42,
    ST_SEND_TXQ_ENQUEUE_START = 6'd43,
    ST_SEND_TXQ_ENQUEUE_END = 6'd44;

reg[7:0] FrameCount;   // Number of received frames
reg[3:0] count;        // General use counter
reg[3:0] readCount;    // Wait for read valid

reg[15:0] destMac[0:2];  // Not currently used
reg[15:0] srcMac[0:2];
reg[15:0] Length;
              
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
       quadRead <= 0;
       quadWrite <= 0;
       sendAck <= 0;
       srcMac[0] <= 16'd0;
       srcMac[1] <= 16'd0;
       srcMac[2] <= 16'd0;
       Length <= 16'd0;
    end
    else begin

       case (state)

         ST_IDLE:
         begin
            isDMA <= 0;
            isWord <= 1;       // all transfers are word
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
            else if (~ETH_IRQn && receiveEnabled) begin
               cmdReq <= 1;
               isWrite <= 0;
               RegAddr <= 8'h92;
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_CLEAR_RXIS;
            end
            else if (sendReq) begin
               state <= ST_SEND_DMA_STATUS_READ;
               sendAck <= 1;
            end
         end

         ST_WAIT_ACK:
         begin
            if (cmdAck) begin
               cmdReq <= 0;
               state <= ST_WAIT_ACK_CLEAR;
               readCount <= 4'd0;
            end
         end

         ST_WAIT_ACK_CLEAR:
         begin
            if (~cmdAck) begin
               if (isWrite || readValid) state <= nextState;
               else begin
                  // Shouldn't take more than 12 cycles to read data.
                  if (readCount == 4'hf) begin
                     ethIoError <= 1;
                     // Moving to IDLE state may not be the best action,
                     // since there may be some cleanup needed, such as
                     // getting out of DMA mode.
                     state <= ST_IDLE;
                  end
                  readCount <= readCount + 4'd1;
               end
            end
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
         end // case: ST_RECEIVE_CLEAR_RXIS

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
            cmdReq <= 1;
            RegAddr <= 8'h7C;
            state <= ST_WAIT_ACK;
            nextState <= (ReadData[15:8] != 0) ? ST_RECEIVE_FRAME_STATUS : ST_IDLE;
         end

         ST_RECEIVE_FRAME_STATUS:
         begin
            FrameCount <= FrameCount-8'd1;
            if (ReadData[15]) begin // if valid
               cmdReq <= 1;
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
            count <= 4'd0;
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
              3'd6: Length <=  {ReadData[7:0],ReadData[15:8]};
            endcase
            if (count[2:0] == 3'd6) begin
               if (Length == 16'd16) begin
                  //state <= ST_RECEIVE_DMA_QUADLET_READ_REQ;
                  state <= ST_RECEIVE_FLUSH_START;
                  quadRead <= ~quadRead;
               end
               else if (Length == 16'd20) begin
                  // state <= ST_RECEIVE_DMA_QUADLET_WRITE;
                  state <= ST_RECEIVE_FLUSH_START;
                  quadWrite <= ~quadWrite;
               end
               else begin
                  state <= ST_RECEIVE_FLUSH_START;
               end
               count <= 4'd0;
            end
            else begin
               cmdReq <= 1;
               state <= ST_WAIT_ACK;
               nextState <= ST_RECEIVE_DMA_FRAME_HEADER;
               count[2:0] <= count[2:0]+3'd1;
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
         end

         ST_RECEIVE_FLUSH_EXECUTE:
         begin
            // Flush the rest of the packet (also clears DMA bit)
            cmdReq <= 1;
            isWrite <= 1;
            WriteData <= {ReadData[15:4],1'b0,ReadData[2:1],1'b1};
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_FLUSH_WAIT_START;
            //nextState <= (FrameCount == 0) ? ST_IDLE : ST_RECEIVE_FRAME_STATUS;
            //nextState <= (FrameCount == 0) ? ST_SEND_DMA_STATUS_READ : ST_RECEIVE_FRAME_STATUS;
         end

         ST_RECEIVE_FLUSH_WAIT_START:
         begin
            cmdReq <= 1;
            isWrite <= 0;
            // RegAddr is already set to 8'h82
            state <= ST_WAIT_ACK;
            nextState <= ST_RECEIVE_FLUSH_WAIT_CHECK;
         end

         ST_RECEIVE_FLUSH_WAIT_CHECK:
         begin
            // Wait for bit 0 in Register 0x82 to be cleared; if cleared, receive status
            // of next frame, or go to idle state if last frame.
            if (ReadData[0] == 1'b0)
               state <= (FrameCount == 8'd0) ? ST_IDLE : ST_RECEIVE_FRAME_STATUS;
            else
               state <= ST_RECEIVE_FLUSH_WAIT_START;
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
            WriteData <= 16'd34;  // Byte count = 34 (14+20), quadlet
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_DESTADDR;
            count <= 4'd0;
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
            WriteData <= 16'd20;  // 20 bytes for quadlet read/write
            state <= ST_WAIT_ACK;
            nextState <= ST_SEND_DMA_PACKETDATA;
            count <= 4'd0;
         end

         ST_SEND_DMA_PACKETDATA:
         begin
            cmdReq <= 1;
            case (count[3:0])

              //0:  WriteData <= 16'h0;     // dest-id
              4'd1:  WriteData <= 16'h6000; // tcode=6
              //2:  WriteData <= 16'h0;     // src-id
              //3:  WriteData <= 16'h0;     // rcode, reserved
              //4:  WriteData <= 16'h0;     // reserved
              //5:  WriteData <= 16'h0;     // reserved
              4'd6:  WriteData <= 16'h3412; // quadlet data (upper word)
              4'd7:  WriteData <= 16'h7856; // quadlet data (lower word)
              //8:  WriteData <= 16'h0;     // CRC
              //9:  WriteData <= 16'h0;     // CRC
              default: WriteData <= 16'h0;
            endcase
         
            state <= ST_WAIT_ACK;
            nextState <= (count[3:0] == 4'd9) ? ST_SEND_DMA_STOP_READ : ST_SEND_DMA_PACKETDATA;
            count[3:0] <= count[3:0]+4'd1;
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
            nextState <= ST_IDLE;
         end

         endcase // case (state)
    end
end

endmodule
