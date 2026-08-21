`timescale 1ns/1ps

module tb_dsib_si_parser;
    reg clk = 1'b0;
    reg[7:0] rx_data = 8'd0;
    reg rx_data_valid = 1'b0;

    wire packet_valid;
    wire[3:0] suj_z_id;
    wire dsib_z_si_present;
    wire[11:0] suj_z_pot1;
    wire[11:0] suj_z_pot2;

    integer packet_count = 0;

    always #1 clk = ~clk;

    dsib_si_parser dut (
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

    function automatic [15:0] crc16_update_byte;
        input [15:0] q;
        input [7:0] data;
        reg[15:0] c;
        begin
            c[0] = q[8] ^ q[12] ^ q[13] ^ q[14] ^ data[0] ^ data[4] ^ data[5] ^ data[6];
            c[1] = q[8] ^ q[9] ^ q[12] ^ q[15] ^ data[0] ^ data[1] ^ data[4] ^ data[7];
            c[2] = q[8] ^ q[9] ^ q[10] ^ q[12] ^ q[14] ^ data[0] ^ data[1] ^ data[2] ^ data[4] ^ data[6];
            c[3] = q[9] ^ q[10] ^ q[11] ^ q[13] ^ q[15] ^ data[1] ^ data[2] ^ data[3] ^ data[5] ^ data[7];
            c[4] = q[8] ^ q[10] ^ q[11] ^ q[13] ^ data[0] ^ data[2] ^ data[3] ^ data[5];
            c[5] = q[8] ^ q[9] ^ q[11] ^ q[13] ^ data[0] ^ data[1] ^ data[3] ^ data[5];
            c[6] = q[9] ^ q[10] ^ q[12] ^ q[14] ^ data[1] ^ data[2] ^ data[4] ^ data[6];
            c[7] = q[8] ^ q[10] ^ q[11] ^ q[12] ^ q[14] ^ q[15] ^ data[0] ^ data[2] ^ data[3] ^ data[4] ^ data[6] ^ data[7];
            c[8] = q[0] ^ q[8] ^ q[9] ^ q[11] ^ q[14] ^ q[15] ^ data[0] ^ data[1] ^ data[3] ^ data[6] ^ data[7];
            c[9] = q[1] ^ q[9] ^ q[10] ^ q[12] ^ q[15] ^ data[1] ^ data[2] ^ data[4] ^ data[7];
            c[10] = q[2] ^ q[8] ^ q[10] ^ q[11] ^ q[12] ^ q[14] ^ data[0] ^ data[2] ^ data[3] ^ data[4] ^ data[6];
            c[11] = q[3] ^ q[8] ^ q[9] ^ q[11] ^ q[14] ^ q[15] ^ data[0] ^ data[1] ^ data[3] ^ data[6] ^ data[7];
            c[12] = q[4] ^ q[8] ^ q[9] ^ q[10] ^ q[13] ^ q[14] ^ q[15] ^ data[0] ^ data[1] ^ data[2] ^ data[5] ^ data[6] ^ data[7];
            c[13] = q[5] ^ q[9] ^ q[10] ^ q[11] ^ q[14] ^ q[15] ^ data[1] ^ data[2] ^ data[3] ^ data[6] ^ data[7];
            c[14] = q[6] ^ q[10] ^ q[11] ^ q[12] ^ q[15] ^ data[2] ^ data[3] ^ data[4] ^ data[7];
            c[15] = q[7] ^ q[11] ^ q[12] ^ q[13] ^ data[3] ^ data[4] ^ data[5];
            crc16_update_byte = c;
        end
    endfunction

    function automatic [15:0] packet_crc;
        input [7:0] flags;
        input [7:0] pot1_lo;
        input [7:0] pot1_hi;
        input [7:0] pot2_lo;
        input [7:0] pot2_hi;
        reg[15:0] crc;
        begin
            crc = 16'hffff;
            crc = crc16_update_byte(crc, flags);
            crc = crc16_update_byte(crc, pot1_lo);
            crc = crc16_update_byte(crc, pot1_hi);
            crc = crc16_update_byte(crc, pot2_lo);
            crc = crc16_update_byte(crc, pot2_hi);
            packet_crc = crc;
        end
    endfunction

    task automatic tick_cycles;
        input integer cycles;
        begin
            repeat (cycles) @(posedge clk);
        end
    endtask

    task automatic send_byte;
        input [7:0] data;
        begin
            @(negedge clk);
            rx_data = data;
            rx_data_valid = 1'b1;
            @(negedge clk);
            rx_data_valid = 1'b0;
            rx_data = 8'd0;
        end
    endtask

    task automatic send_header;
        begin
            send_byte("d");
            send_byte("S");
            send_byte("I");
            send_byte("B");
        end
    endtask

    task automatic send_packet_fields;
        input [2:0] flags_pad;
        input dsib_z_present;
        input [3:0] id;
        input [11:0] pot1;
        input [11:0] pot2;
        input [3:0] pot1_pad;
        input [3:0] pot2_pad;
        input corrupt_crc;
        reg[7:0] flags;
        reg[7:0] pot1_lo;
        reg[7:0] pot1_hi;
        reg[7:0] pot2_lo;
        reg[7:0] pot2_hi;
        reg[15:0] crc;
        begin
            flags = {flags_pad, dsib_z_present, id};
            pot1_lo = pot1[7:0];
            pot1_hi = {pot1_pad, pot1[11:8]};
            pot2_lo = pot2[7:0];
            pot2_hi = {pot2_pad, pot2[11:8]};
            crc = packet_crc(flags, pot1_lo, pot1_hi, pot2_lo, pot2_hi);
            if (corrupt_crc) begin
                crc = crc ^ 16'h0001;
            end

            send_byte(flags);
            send_byte(pot1_lo);
            send_byte(pot1_hi);
            send_byte(pot2_lo);
            send_byte(pot2_hi);
            send_byte(crc[7:0]);
            send_byte(crc[15:8]);
        end
    endtask

    task automatic send_packet;
        input [2:0] flags_pad;
        input dsib_z_present;
        input [3:0] id;
        input [11:0] pot1;
        input [11:0] pot2;
        input [3:0] pot1_pad;
        input [3:0] pot2_pad;
        input corrupt_crc;
        begin
            send_header();
            send_packet_fields(flags_pad, dsib_z_present, id, pot1, pot2, pot1_pad, pot2_pad, corrupt_crc);
        end
    endtask

    task automatic send_bad_packet_crc_hi_as_header_d;
        input dsib_z_present;
        input [3:0] id;
        input [11:0] pot1;
        input [11:0] pot2;
        reg[7:0] flags;
        reg[7:0] pot1_lo;
        reg[7:0] pot1_hi;
        reg[7:0] pot2_lo;
        reg[7:0] pot2_hi;
        reg[15:0] crc;
        begin
            flags = {3'b000, dsib_z_present, id};
            pot1_lo = pot1[7:0];
            pot1_hi = {4'h0, pot1[11:8]};
            pot2_lo = pot2[7:0];
            pot2_hi = {4'h0, pot2[11:8]};
            crc = packet_crc(flags, pot1_lo, pot1_hi, pot2_lo, pot2_hi);

            send_header();
            send_byte(flags);
            send_byte(pot1_lo);
            send_byte(pot1_hi);
            send_byte(pot2_lo);
            send_byte(pot2_hi);
            send_byte(crc[7:0] ^ 8'h01);
            send_byte("d");
        end
    endtask

    task automatic expect_packet_count;
        input integer expected;
        begin
            tick_cycles(2);
            if (packet_count != expected) begin
                $fatal(1, "packet count mismatch: expected %0d, got %0d", expected, packet_count);
            end
        end
    endtask

    task automatic expect_fields;
        input [3:0] expected_id;
        input expected_z_present;
        input [11:0] expected_pot1;
        input [11:0] expected_pot2;
        begin
            if (suj_z_id !== expected_id) begin
                $fatal(1, "suj_z_id mismatch: expected %01x, got %01x", expected_id, suj_z_id);
            end
            if (dsib_z_si_present !== expected_z_present) begin
                $fatal(1, "dsib_z_si_present mismatch: expected %0d, got %0d", expected_z_present, dsib_z_si_present);
            end
            if (suj_z_pot1 !== expected_pot1) begin
                $fatal(1, "suj_z_pot1 mismatch: expected %03x, got %03x", expected_pot1, suj_z_pot1);
            end
            if (suj_z_pot2 !== expected_pot2) begin
                $fatal(1, "suj_z_pot2 mismatch: expected %03x, got %03x", expected_pot2, suj_z_pot2);
            end
        end
    endtask

    initial begin
        tick_cycles(4);

        send_packet(3'b000, 1'b1, 4'ha, 12'h123, 12'habc, 4'h0, 4'h0, 1'b0);
        expect_packet_count(1);
        expect_fields(4'ha, 1'b1, 12'h123, 12'habc);

        send_byte("x");
        send_byte("d");
        send_byte("x");
        send_byte("d");
        send_byte("S");
        send_byte("d");
        send_byte("S");
        send_byte("I");
        send_byte("x");
        send_packet(3'b000, 1'b0, 4'h2, 12'h456, 12'h789, 4'h0, 4'h0, 1'b0);
        expect_packet_count(2);
        expect_fields(4'h2, 1'b0, 12'h456, 12'h789);

        send_packet(3'b000, 1'b1, 4'hf, 12'h001, 12'h002, 4'h0, 4'h0, 1'b1);
        expect_packet_count(2);
        expect_fields(4'h2, 1'b0, 12'h456, 12'h789);

        send_packet(3'b000, 1'b1, 4'h3, 12'h00a, 12'h00b, 4'h0, 4'h0, 1'b0);
        expect_packet_count(3);
        expect_fields(4'h3, 1'b1, 12'h00a, 12'h00b);

        send_packet(3'b101, 1'b1, 4'h4, 12'hfed, 12'hcba, 4'ha, 4'h5, 1'b0);
        expect_packet_count(4);
        expect_fields(4'h4, 1'b1, 12'hfed, 12'hcba);

        send_bad_packet_crc_hi_as_header_d(1'b0, 4'h5, 12'h111, 12'h222);
        send_byte("S");
        send_byte("I");
        send_byte("B");
        send_packet_fields(3'b000, 1'b0, 4'h6, 12'h333, 12'h444, 4'h0, 4'h0, 1'b0);
        expect_packet_count(5);
        expect_fields(4'h6, 1'b0, 12'h333, 12'h444);

        $display("dsib_si_parser Verilator test passed");
        $finish;
    end
endmodule
