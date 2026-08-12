`timescale 1ns/1ps

module tb_dsib_si_uart;
    localparam int CLOCKS_PER_BAUD = 16;

    reg clk = 1'b0;
    reg rx_pin = 1'b1;
    wire tx_pin;

    wire[7:0] rx_data;
    wire rx_data_valid;
    wire rx_data_ready = 1'b1;

    reg[7:0] tx_data = 8'd0;
    reg tx_data_valid = 1'b0;
    wire tx_data_ready;

    always #1 clk = ~clk;

    dsib_si_uart #(
        .CLOCKS_PER_BAUD(CLOCKS_PER_BAUD)
    ) dut (
        .clk(clk),
        .rx_pin(rx_pin),
        .rx_data(rx_data),
        .rx_data_valid(rx_data_valid),
        .rx_data_ready(rx_data_ready),
        .tx_data(tx_data),
        .tx_data_valid(tx_data_valid),
        .tx_data_ready(tx_data_ready),
        .tx_pin(tx_pin)
    );

    task automatic tick_cycles;
        input int cycles;
        begin
            repeat (cycles) @(posedge clk);
        end
    endtask

    task automatic send_rx_byte;
        input [7:0] data;
        int bit_index;
        begin
            rx_pin = 1'b0;
            tick_cycles(CLOCKS_PER_BAUD);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                rx_pin = data[bit_index];
                tick_cycles(CLOCKS_PER_BAUD);
            end
            rx_pin = 1'b1;
            tick_cycles(CLOCKS_PER_BAUD);
        end
    endtask

    task automatic expect_rx_byte;
        input [7:0] expected;
        int wait_count;
        begin
            wait_count = 0;
            while (!rx_data_valid) begin
                @(posedge clk);
                wait_count = wait_count + 1;
                if (wait_count > CLOCKS_PER_BAUD * 16) begin
                    $fatal(1, "timed out waiting for RX byte %02x", expected);
                end
            end
            if (rx_data !== expected) begin
                $fatal(1, "RX byte mismatch: expected %02x, got %02x", expected, rx_data);
            end
            @(posedge clk);
        end
    endtask

    task automatic run_rx_case;
        input [7:0] data;
        begin
            fork
                send_rx_byte(data);
                expect_rx_byte(data);
            join
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

    task automatic expect_tx_byte;
        input [7:0] expected;
        reg[7:0] observed;
        int bit_index;
        int wait_count;
        begin
            wait_count = 0;
            while (tx_pin !== 1'b0) begin
                @(posedge clk);
                wait_count = wait_count + 1;
                if (wait_count > CLOCKS_PER_BAUD * 4) begin
                    $fatal(1, "timed out waiting for TX start bit");
                end
            end

            if (tx_data_ready !== 1'b0) begin
                $fatal(1, "TX reported ready during start bit");
            end

            tick_cycles(CLOCKS_PER_BAUD / 2);
            if (tx_pin !== 1'b0) begin
                $fatal(1, "TX start bit was not low at bit center");
            end

            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                tick_cycles(CLOCKS_PER_BAUD);
                observed[bit_index] = tx_pin;
            end

            tick_cycles(CLOCKS_PER_BAUD);
            if (tx_pin !== 1'b1) begin
                $fatal(1, "TX stop bit was not high");
            end
            if (observed !== expected) begin
                $fatal(1, "TX byte mismatch: expected %02x, got %02x", expected, observed);
            end

            while (!tx_data_ready) begin
                @(posedge clk);
            end
        end
    endtask

    initial begin
        tick_cycles(4);

        run_rx_case(8'h00);
        run_rx_case(8'h55);
        run_rx_case(8'ha5);
        run_rx_case(8'hff);

        fork
            begin
                send_rx_byte(8'h12);
                send_rx_byte(8'h34);
            end
            begin
                expect_rx_byte(8'h12);
                expect_rx_byte(8'h34);
            end
        join

        if (tx_pin !== 1'b1) begin
            $fatal(1, "TX did not idle high");
        end

        fork
            start_tx_byte(8'hc3);
            expect_tx_byte(8'hc3);
        join

        fork
            begin
                start_tx_byte(8'h5a);
                start_tx_byte(8'ha5);
            end
            begin
                expect_tx_byte(8'h5a);
                expect_tx_byte(8'ha5);
            end
        join

        $display("dsib_si_uart Verilator test passed");
        $finish;
    end
endmodule
