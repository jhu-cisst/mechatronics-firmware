`timescale 1ns/1ps

module tb_dsib_si_drac_registers;
    localparam integer CLOCKS_PER_BAUD = 427;

    reg clk = 1'b0;
    reg uart_rx = 1'b1;
    wire[1:32] io1;
    wire[1:38] io2;
    wire[3:0] io_extra;
    reg[15:0] reg_raddr = 16'hb031;
    wire[31:0] reg_rdata;
    wire reg_rwait;
    integer index;

    reg[7:0] packet_bytes[0:10];
    initial begin
        packet_bytes[0] = "d";
        packet_bytes[1] = "S";
        packet_bytes[2] = "I";
        packet_bytes[3] = "B";
        packet_bytes[4] = 8'h1a;
        packet_bytes[5] = 8'h3e;
        packet_bytes[6] = 8'h01;
        packet_bytes[7] = 8'hbc;
        packet_bytes[8] = 8'h0a;
        packet_bytes[9] = 8'hdb;
        packet_bytes[10] = 8'h64;
    end

    always #1 clk = ~clk;
    assign io_extra[2] = uart_rx;

    // Only UART, parser, address translation, and DRAC's read mux are
    // elaborated. Unrelated motor/LVDS peripherals are omitted by iverilog -i.
    DRAC dut (
        .sysclk(clk),
        .pwmclk(clk),
        .board_id(4'd0),
        .IO1(io1),
        .IO2(io2),
        .io_extra(io_extra),
        .host_reg_raddr(reg_raddr),
        .reg_waddr(16'd0),
        .reg_rdata(reg_rdata),
        .reg_wdata(32'd0),
        .reg_rwait(reg_rwait),
        .reg_wen(1'b0),
        .blk_wen(1'b0),
        .blk_wstart(1'b0),
        .req_blk_rt_rd(1'b0),
        .blk_rt_rd(1'b0),
        .wdog_period_led(1'b0),
        .wdog_period_status(3'd0),
        .wdog_timeout(1'b0)
    );

    // Only direct reads are tested. Disable unused RT translation tables to
    // avoid Icarus's rejection of their unsized genvar concatenations.
    defparam dut.ReadAddr.NUM_MOTORS = 0;
    defparam dut.ReadAddr.NUM_ENCODERS = 0;
    defparam dut.ReadAddr.NUM_EXTRA = 0;

    task automatic send_byte;
        input [7:0] data;
        integer bit_index;
        begin
            @(negedge clk);
            uart_rx = 1'b0;
            repeat (CLOCKS_PER_BAUD) @(negedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx = data[bit_index];
                repeat (CLOCKS_PER_BAUD) @(negedge clk);
            end
            uart_rx = 1'b1;
            repeat (CLOCKS_PER_BAUD) @(negedge clk);
        end
    endtask

    task automatic send_packet;
        input corrupt_crc;
        integer byte_index;
        begin
            for (byte_index = 0; byte_index < 11; byte_index = byte_index + 1) begin
                send_byte(packet_bytes[byte_index] ^
                          ((corrupt_crc && byte_index == 9) ? 8'h01 : 8'h00));
            end
        end
    endtask

    task automatic expect_register;
        input [15:0] address;
        input [31:0] expected;
        begin
            @(negedge clk);
            reg_raddr = address;
            @(negedge clk);
            if (reg_rwait !== 1'b0 || reg_rdata !== expected) begin
                $fatal(1, "address %04x: expected %08x without wait, got %08x wait=%b",
                       address, expected, reg_rdata, reg_rwait);
            end
        end
    endtask

    initial begin
        repeat (20) @(negedge clk);
        expect_register(16'hb031, 32'd0);

        send_byte("x");
        send_byte("S");
        send_byte("I");
        send_byte("B");
        expect_register(16'hb031, 32'd0);

        send_byte("d");
        send_byte("x");
        expect_register(16'hb031, 32'h00010000);
        send_byte("d");
        send_byte("S");
        send_byte("x");
        expect_register(16'hb031, 32'h00020000);
        send_byte("d");
        send_byte("S");
        send_byte("I");
        send_byte("x");
        expect_register(16'hb031, 32'h00030000);

        // Each unexpected 'd' increments bad_header but restarts the header.
        send_byte("d");
        send_byte("d");
        expect_register(16'hb031, 32'h00040000);
        send_byte("S");
        send_byte("d");
        expect_register(16'hb031, 32'h00050000);
        send_byte("S");
        send_byte("I");
        send_byte("d");
        expect_register(16'hb031, 32'h00060000);
        send_byte("S");
        send_byte("I");
        send_byte("B");
        for (index = 4; index < 11; index = index + 1) begin
            send_byte(packet_bytes[index]);
        end
        expect_register(16'hb031, 32'h00060000);

        send_packet(1'b1);
        expect_register(16'hb031, 32'h00060001);
        send_packet(1'b1);
        expect_register(16'hb031, 32'h00060002);
        send_packet(1'b0);
        expect_register(16'hb031, 32'h00060002);

        // Reads are non-destructive, and the neighboring decode is unchanged.
        expect_register(16'hb031, 32'h00060002);
        expect_register(16'hb030, 32'haabc213e);
        expect_register(16'hb032, 32'h0000cccc);
        expect_register(16'hc031, 32'd0);
        expect_register(16'hb031, 32'h00060002);

        $display("dsib_si DRAC register test passed");
        $finish;
    end
endmodule
