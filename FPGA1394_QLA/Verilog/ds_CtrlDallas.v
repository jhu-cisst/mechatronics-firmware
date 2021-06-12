/*******************************************************************************    
 *
 * Copyright(C) 2017 Johns Hopkins University
 *
 * Module:  CtrlDallas
 *
 * Purpose: This module controls communication to and from the Dallas chip
 *          through the DS2480B 1-wire line driver. It generates parallel 
 *          data that it sends to uart_top module to be converted to RS232
 *          protocol packets, which the DS2480B chip converts to 1-wire 
 *          signals. 
 *
 * Revision history
 *     07/26/17    Jie Ying Wu         Initial revision
 */
 
 `timescale 1ns / 1ps
 
 module ds_CtrlDallas(
    input  wire        clk,       // 50 MHz system clock
    input  wire        dlsrxd,    // to UART from Dallas 1-wire interface chip

    output reg  [31:0] inst_id,
    output wire        dlstxd

);   // from UART to Dallas 1-wire interface chip
    
    // Right shift 
    // Send a command byte to calibrate
    // send F0 command to read
    // then send 2-byte address to read from
    // baud rate should be 9600 bps (is default)
 
    // Variables
    reg   [7:0] tdata;
    reg         load_tdata;
    reg   [1:0] byte_ctr;
    wire        tx_busy;
    wire  [7:0] rdata;
    wire        load_rdata;
    reg   [2:0] state;
    reg  [31:0] temp_id;
    reg         latch;
    reg         start; 
    reg         written;
    reg         received;       //Since comm clock so much slower, reg to keep track if new data received

    wire        reset;    
    reg         master_reset;
    reg         clk_5m;    // customized 5 MHz clock
    reg   [3:0] count;

    parameter INIT       = 3'd0,
              RESET_CMD  = 3'd1,
              DATA_MODE  = 3'd2,
              SKIP_ROM   = 3'd3,
              READ_CMD   = 3'd4,
              ADDRESS    = 3'd5,
              READ       = 3'd6,
              CMD_MODE   = 3'd7,
              RESET_CODE = 8'hC1,
              UID_ADDR   = 16'h0288,
              SER_ID     = 16'h00A0;
				  
				  //Name offset is 16'h0160
    
    initial begin
        latch        <= 1'b0;
        state        <= INIT;
        master_reset <= 1'b1;
        load_tdata   <= 1'b0;
        byte_ctr     <= 2'b0;
        temp_id      <= 32'h12345678;
        written      <= 1'b0;
    end

    assign  reset = 1'd0;   // always disable reset
    initial clk_5m <= 1'b0;  // init 5M clock

    // generate 5MHz clock
    always @ (posedge clk) begin
           if (count == 4) begin
              count <= 0;
              clk_5m <= ~clk_5m;
           end
           else
              count <= count+1;
    end
    
    // Convert parallel data to RS232 format serial stream
    ds_CtrlUart uart_comm(
        // Input
        .clk(clk_5m),
        .reset(reset),
        .pwr_cycle(master_reset),
        .ser_in(dlsrxd),
        .tx_data(tdata),
        // Output
        .new_tx_data(load_tdata),
        .ser_out(dlstxd),
        .tx_busy(tx_busy),
        .rx_data(rdata),
        .new_rx_data(load_rdata)
    );
   
    // Continuously send read command and address for the instrument ID location
    always @(posedge clk_5m) begin
        if (tx_busy) begin      // Wait for confirmation that tdata has been queued to transmit
            received <= 1'b1;
        end
        case (state)
            INIT: begin      // Initialize DS2480B - master reset then reset signal to calibrate baud rate
                if (~written) begin
                    written    <= 1'b1;
                    load_tdata <= 1'b1;
                    received   <= 1'b0;
                    if (master_reset) begin
                        tdata      <= 8'h0;       // Master reset signal of NULL at 4800 bps
                    end else begin
                        tdata      <= RESET_CODE; // Reset command to sync baud rate
                    end
                end else if (received & ~tx_busy) begin                    
                    written    <= 1'b0;
                    load_tdata <= 1'b0;
                    if (master_reset) begin      
                        master_reset <= 1'b0;
                    end else begin
                        state      <= RESET_CMD;  // No response from this reset signal
                    end
                end 
            end
            RESET_CMD: begin // Send reset command to set up for read sequence
                if (~written) begin
                    tdata      <= RESET_CODE;
                    load_tdata <= 1'b1;
                    written    <= 1'b1;
                    received   <= 1'b0;
                end else if (~load_tdata & load_rdata) begin
                    state      <= DATA_MODE;
                    written    <= 1'b0;
                end else if (received & ~tx_busy) begin
                    load_tdata <= 1'b0;
                end 
            end
            DATA_MODE: begin // Go to data mode from command mode
                if (~written) begin
                    tdata      <= 8'hE1;      //Instruction to go to data mode
                    load_tdata <= 1'b1;
                    written    <= 1'b1;
                    received   <= 1'b0;
                end else if (received & ~tx_busy) begin
                    state      <= SKIP_ROM;
                    load_tdata <= 1'b0;
                    written    <= 1'b0;
                end 
            end
            SKIP_ROM: begin // Skip ROM section - necessary to read memory
                if (~written) begin
                    tdata      <= 8'hCC;      // Command to skip ROM
                    load_tdata <= 1'b1;
                    written    <= 1'b1;
                    received   <= 1'b0;
                end else if (~load_tdata & load_rdata) begin
                    state      <= READ_CMD;
                    written    <= 1'b0;
                end else if (received & ~tx_busy) begin
                    load_tdata <= 1'b0;
                end
            end
            READ_CMD: begin   // Send 8-bit read command to the Dallas chip
                if (~written) begin
                    tdata      <= 8'hF0;     // Read memory command
                    load_tdata <= 1'b1;
                    written    <= 1'b1;
                    received   <= 1'b0;
                end else if (~load_tdata & load_rdata) begin
                    state      <= ADDRESS;
                    written    <= 1'b0;
                end else if (received & ~tx_busy) begin
                    load_tdata <= 1'b0;
                end
            end
            ADDRESS: begin     // Send 16-bit address, LSB then MSB
                if (~written) begin
                    load_tdata <= 1'b1;
                    written    <= 1'b1;
                    received   <= 1'b0;
                    if (byte_ctr == 2'b00) begin
                        tdata    <= UID_ADDR[7:0];   // LSB of address for instrument ID
                        byte_ctr <= 2'b01;
                    end else if (byte_ctr == 2'b01) begin
                        tdata    <= UID_ADDR[15:8];  // MSB of address for instrument ID
                        byte_ctr <= 2'b10;
                    end
                end else if (~load_tdata & load_rdata) begin
                    written    <= 1'b0;
                    if (byte_ctr == 2'b10) begin
                        state      <= READ;
                        byte_ctr   <= 2'b0;
                    end
                end else if (received & ~tx_busy) begin
                    load_tdata <= 1'b0;
                end
            end
            READ: begin        // Load 4 bytes of instrument ID - can continuously read up t 8 bytes   
                if (~written) begin
                    tdata      <= 8'hFF;
                    load_tdata <= 1'b1;
                    written    <= 1'b1;
                    received   <= 1'b0;
                end else if (~load_tdata & load_rdata) begin
                    written    <= 1'b0;
                    byte_ctr   <= byte_ctr + 2'b01;
                    temp_id[31:0] <= {rdata[7:0], temp_id[31:8]};
                    if (byte_ctr == 2'd3) begin
                        state    <= CMD_MODE;
                        byte_ctr <= 2'b0;
                    end
                end else if (received & ~tx_busy) begin
                    load_tdata <= 1'b0;
                end
            end
            CMD_MODE: begin    // Go to command mode from data mode and reset 
                if (~written) begin
                    written    <= 1'b1;
                    load_tdata <= 1'b1;
                    received   <= 1'b0;
                    if (byte_ctr == 0) begin
                        latch      <= 1'b1;
                        tdata      <= 8'hE3; // Go to command mode from data mode 
                        latch      <= 1'b1;
                    end else begin
                        tdata      <= RESET_CODE;
                        latch      <= 1'b0;
                    end
                end else if (~load_tdata & load_rdata) begin
                    state    <= INIT;   // Reset to exit reading
                    master_reset <= 1'b1;
                    latch    <= 1'b0;
                    byte_ctr <= 2'b0;
                end else if (received & ~tx_busy) begin
                    if (byte_ctr == 2'b00) begin
                        byte_ctr <= 2'b01;
                        written  <= 1'b0;
                    end
                    load_tdata <= 1'b0;
                end
            end
        endcase
    end
    
    // Latch instrument ID at the end of a read cycle
    always @(posedge latch) begin
        inst_id[31:0] <= temp_id[31:0];
    end
endmodule