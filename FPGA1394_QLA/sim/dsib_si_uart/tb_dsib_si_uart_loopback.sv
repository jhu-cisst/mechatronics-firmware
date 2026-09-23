`timescale 1ns/1ps

module tb_dsib_si_uart_loopback;
    localparam int CLOCKS_PER_BAUD = 16;

    reg clk = 1'b0;
    wire uart_pin;

    wire[7:0] rx_data;
    wire rx_data_valid;
    wire rx_data_ready = 1'b1;

    reg[7:0] tx_data = 8'd0;
    reg tx_data_valid = 1'b0;
    wire tx_data_ready;

    wire packet_valid;
    wire[3:0] suj_z_id;
    wire dsib_z_si_present;
    wire[11:0] suj_z_pot1;
    wire[11:0] suj_z_pot2;

    integer packet_count = 0;

    always #1 clk = ~clk;

    dsib_si_uart #(
        .CLOCKS_PER_BAUD(CLOCKS_PER_BAUD)
    ) uart (
        .clk(clk),
        .rx_pin(uart_pin),
        .rx_data(rx_data),
        .rx_data_valid(rx_data_valid),
        .rx_data_ready(rx_data_ready),
        .tx_data(tx_data),
        .tx_data_valid(tx_data_valid),
        .tx_data_ready(tx_data_ready),
        .tx_pin(uart_pin)
    );

    dsib_si_parser parser (
        .clk(clk),
        .rx_data(rx_data),
        .rx_data_valid(rx_data_valid),
        .packet_valid(packet_valid),
        .suj_z_id(suj_z_id),
        .dsib_z_si_present(dsib_z_si_present),
        .suj_z_pot1(suj_z_pot1),
        .suj_z_pot2(suj_z_pot2)
    );

    always @(posedge clk) begin
        if (packet_valid) begin
            packet_count = packet_count + 1;
        end
    end

    task automatic tick_cycles;
        input integer cycles;
        begin
            repeat (cycles) @(posedge clk);
        end
    endtask

    task automatic start_tx_byte;
        input [7:0] data;
        begin
            while (!tx_data_ready) begin
                @(posedge clk);
            end
            tx_data = data;
            tx_data_valid = 1'b1;
            @(posedge clk);
            tx_data_valid = 1'b0;
        end
    endtask

    task automatic expect_rx_byte;
        input [7:0] expected;
        integer wait_count;
        begin
            wait_count = 0;
            while (!rx_data_valid) begin
                @(posedge clk);
                wait_count = wait_count + 1;
                if (wait_count > CLOCKS_PER_BAUD * 16) begin
                    $fatal(1, "timed out waiting for loopback byte %02x", expected);
                end
            end
            if (rx_data !== expected) begin
                $fatal(1, "loopback byte mismatch: expected %02x, got %02x", expected, rx_data);
            end
            @(posedge clk);
        end
    endtask

    task automatic loopback_byte;
        input [7:0] data;
        begin
            fork
                start_tx_byte(data);
                expect_rx_byte(data);
            join
        end
    endtask

    task automatic send_valid_packet;
        begin
            // dSIB, present=1, id=10, pot1=0x123, pot2=0xabc.
            // CRC 0xd203 covers the five payload bytes and is sent low byte first.
            loopback_byte("d");
            loopback_byte("S");
            loopback_byte("I");
            loopback_byte("B");
            loopback_byte(8'h1a);
            loopback_byte(8'h23);
            loopback_byte(8'h01);
            loopback_byte(8'hbc);
            loopback_byte(8'h0a);
            loopback_byte(8'h03);
            loopback_byte(8'hd2);
        end
    endtask

    initial begin
        tick_cycles(4);

        if (uart_pin !== 1'b1) begin
            $fatal(1, "loopback UART did not idle high");
        end

        send_valid_packet();
        tick_cycles(4);

        if (packet_count != 1) begin
            $fatal(1, "packet count mismatch: expected 1, got %0d", packet_count);
        end
        if (suj_z_id !== 4'ha) begin
            $fatal(1, "suj_z_id mismatch: expected a, got %01x", suj_z_id);
        end
        if (dsib_z_si_present !== 1'b1) begin
            $fatal(1, "dsib_z_si_present mismatch: expected 1, got %0d", dsib_z_si_present);
        end
        if (suj_z_pot1 !== 12'h123) begin
            $fatal(1, "suj_z_pot1 mismatch: expected 123, got %03x", suj_z_pot1);
        end
        if (suj_z_pot2 !== 12'habc) begin
            $fatal(1, "suj_z_pot2 mismatch: expected abc, got %03x", suj_z_pot2);
        end

        $display("dsib_si_uart loopback Verilator test passed");
        $finish;
    end
endmodule
