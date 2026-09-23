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
    wire[15:0] err_count_bad_header;
    wire[15:0] err_count_bad_crc;

    integer packet_count = 0;
    integer repeat_index;
    integer prefix_length;
    integer byte_index;
    integer resume_index;
    integer fault_index;
    integer fault_end;
    integer fault_value;
    integer class_index;
    integer recovery_cases = 0;
    reg[7:0] crc_header_packet[0:10] = '{
        8'h64, 8'h53, 8'h49, 8'h42, 8'h1a, 8'h3e,
        8'h01, 8'hbc, 8'h0a, 8'hdb, 8'h64
    };
    reg[7:0] header_byte_classes[0:4] = '{8'h00, "d", "S", "I", "B"};

    always #1 clk = ~clk;

    dsib_si_parser dut (
        .clk(clk),
        .rx_data(rx_data),
        .rx_data_valid(rx_data_valid),
        .packet_valid(packet_valid),
        .suj_z_id(suj_z_id),
        .dsib_z_si_present(dsib_z_si_present),
        .suj_z_pot1(suj_z_pot1),
        .suj_z_pot2(suj_z_pot2),
        .err_count_bad_header(err_count_bad_header),
        .err_count_bad_crc(err_count_bad_crc)
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

    task automatic send_bad_packet_crc_hi_d;
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

    task automatic expect_error_counts;
        input [15:0] expected_header;
        input [15:0] expected_crc;
        begin
            tick_cycles(2);
            if ({err_count_bad_header, err_count_bad_crc} !== {expected_header, expected_crc}) begin
                $fatal(1, "error counters: expected header=%0d crc=%0d, got header=%0d crc=%0d",
                       expected_header, expected_crc, err_count_bad_header, err_count_bad_crc);
            end
        end
    endtask

    task automatic test_error_counters;
        reg[15:0] expected_header;
        reg[15:0] expected_crc;
        integer prefix;
        integer index;
        integer rollover_index;
        begin
            expected_header = err_count_bad_header;
            expected_crc = err_count_bad_crc;

            // Idle clocks and discarded bytes while already waiting for 'd'.
            rx_data = 8'hff;
            tick_cycles(100);
            send_byte("x");
            send_byte("S");
            send_byte("I");
            send_byte("B");
            expect_error_counts(expected_header, expected_crc);

            for (prefix = 1; prefix <= 3; prefix = prefix + 1) begin
                for (index = 0; index < prefix; index = index + 1) begin
                    send_byte(crc_header_packet[index]);
                end
                tick_cycles(100);
                expect_error_counts(expected_header, expected_crc);
                send_byte("x");
                expected_header = expected_header + 16'd1;
                expect_error_counts(expected_header, expected_crc);
            end

            // Overlapping 'd' restarts at HEADER_S, not HEADER_D.
            for (prefix = 1; prefix <= 3; prefix = prefix + 1) begin
                for (index = 0; index < prefix; index = index + 1) begin
                    send_byte(crc_header_packet[index]);
                end
                send_byte("d");
                expect_error_counts(expected_header, expected_crc);
                send_byte("x");
                expected_header = expected_header + 16'd1;
                expect_error_counts(expected_header, expected_crc);
            end

            // No CRC error until the final byte actually arrives, and only one
            // increment per failed check, regardless of subsequent idle clocks.
            for (index = 0; index < 10; index = index + 1) begin
                send_byte(crc_header_packet[index]);
            end
            tick_cycles(100);
            expect_error_counts(expected_header, expected_crc);
            send_byte(8'h65);
            expected_crc = expected_crc + 16'd1;
            expect_error_counts(expected_header, expected_crc);
            tick_cycles(100);
            expect_error_counts(expected_header, expected_crc);

            send_bad_packet_crc_hi_d(1'b0, 4'h5, 12'h111, 12'h222);
            expected_crc = expected_crc + 16'd1;
            expect_error_counts(expected_header, expected_crc);

            // Neither payload 'd' nor a valid CRC ending in 'd' is an error.
            send_packet(3'b000, 1'b1, 4'ha, 12'h064, 12'h064, 4'h0, 4'h0, 1'b0);
            expect_error_counts(expected_header, expected_crc);
            send_packet(3'b000, 1'b1, 4'ha, 12'h13e, 12'habc, 4'h0, 4'h0, 1'b0);
            expect_error_counts(expected_header, expected_crc);

            // Exercise the defensive fallback from an invalid state.
            @(negedge clk);
            dut.dsib_parse_state = 4'hf;
            send_byte("x");
            expected_header = expected_header + 16'd1;
            expect_error_counts(expected_header, expected_crc);

            // A full cycle checks rollover without forcing counter registers.
            for (rollover_index = 0; rollover_index < 65536; rollover_index = rollover_index + 1) begin
                send_byte("d");
                send_byte("x");
                expected_header = expected_header + 16'd1;
                send_bad_packet_crc_hi_d(1'b0, 4'h5, 12'h111, 12'h222);
                expected_crc = expected_crc + 16'd1;
                expect_error_counts(expected_header, expected_crc);
            end
            $display("dsib_si_parser error counter tests passed");
        end
    endtask

    task automatic expect_clean_packets;
        input string scenario;
        integer count_before;
        begin
            tick_cycles(2);
            count_before = packet_count;
            send_packet(3'b000, 1'b1, 4'ha, 12'h13e, 12'habc, 4'h0, 4'h0, 1'b0);
            tick_cycles(2);
            if (packet_count != count_before + 1) begin
                $fatal(1, "%s: did not accept the second complete packet", scenario);
            end
            expect_fields(4'ha, 1'b1, 12'h13e, 12'habc);

            // Change the fields to check that recovery continues updating data.
            send_packet(3'b000, 1'b0, 4'h6, 12'h333, 12'h444, 4'h0, 4'h0, 1'b0);
            tick_cycles(2);
            if (packet_count != count_before + 2) begin
                $fatal(1, "%s: lost synchronization after recovery", scenario);
            end
            expect_fields(4'h6, 1'b0, 12'h333, 12'h444);
            recovery_cases = recovery_cases + 1;
        end
    endtask

    task automatic expect_recovery;
        input string scenario;
        begin
            // An unfinished parse may consume the first good packet's header.
            send_packet(3'b000, 1'b1, 4'ha, 12'h13e, 12'habc, 4'h0, 4'h0, 1'b0);
            expect_clean_packets(scenario);
        end
    endtask

    initial begin
        tick_cycles(4);
        expect_error_counts(16'd0, 16'd0);

        send_packet(3'b000, 1'b1, 4'ha, 12'h123, 12'habc, 4'h0, 4'h0, 1'b0);
        expect_packet_count(1);
        expect_fields(4'ha, 1'b1, 12'h123, 12'habc);
        expect_error_counts(16'd0, 16'd0);

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

        // A failed CRC ending in 'd' must not prevent the next complete packet.
        send_bad_packet_crc_hi_d(1'b0, 4'h5, 12'h111, 12'h222);
        expect_packet_count(4);
        expect_fields(4'h4, 1'b1, 12'hfed, 12'hcba);
        send_packet(3'b000, 1'b0, 4'h6, 12'h333, 12'h444, 4'h0, 4'h0, 1'b0);
        expect_packet_count(5);
        expect_fields(4'h6, 1'b0, 12'h333, 12'h444);

        // A valid CRC high byte can equal 'd'. Repeating the same packet
        // must not leave the receiver permanently out of sync.
        if (packet_crc(8'h1a, 8'h3e, 8'h01, 8'hbc, 8'h0a) !== 16'h64db) begin
            $fatal(1, "CRC-header regression vector changed");
        end
        for (repeat_index = 0; repeat_index < 256; repeat_index = repeat_index + 1) begin
            send_packet(3'b000, 1'b1, 4'ha, 12'h13e, 12'habc, 4'h0, 4'h0, 1'b0);
        end
        expect_packet_count(261);
        expect_fields(4'ha, 1'b1, 12'h13e, 12'habc);

        // A new 'd' must restart any partially matched header.
        send_byte("d");
        send_packet(3'b000, 1'b0, 4'h2, 12'h456, 12'h789, 4'h0, 4'h0, 1'b0);
        expect_packet_count(262);
        send_byte("d");
        send_byte("S");
        send_packet(3'b000, 1'b0, 4'h2, 12'h456, 12'h789, 4'h0, 4'h0, 1'b0);
        expect_packet_count(263);
        send_byte("d");
        send_byte("S");
        send_byte("I");
        send_packet(3'b000, 1'b0, 4'h2, 12'h456, 12'h789, 4'h0, 4'h0, 1'b0);
        expect_packet_count(264);

        // A full header after a failed packet ending in 'd' is still accepted.
        send_bad_packet_crc_hi_d(1'b0, 4'h5, 12'h111, 12'h222);
        expect_packet_count(264);
        expect_fields(4'h2, 1'b0, 12'h456, 12'h789);
        send_packet(3'b000, 1'b1, 4'ha, 12'h13e, 12'habc, 4'h0, 4'h0, 1'b0);
        expect_packet_count(265);
        expect_fields(4'ha, 1'b1, 12'h13e, 12'habc);

        // Exercise every saved prefix and every byte phase on reconnection.
        for (prefix_length = 0; prefix_length < 11; prefix_length = prefix_length + 1) begin
            for (resume_index = 0; resume_index < 11; resume_index = resume_index + 1) begin
                for (byte_index = 0; byte_index < prefix_length; byte_index = byte_index + 1) begin
                    send_byte(crc_header_packet[byte_index]);
                end
                tick_cycles(100);
                for (byte_index = resume_index; byte_index < 11; byte_index = byte_index + 1) begin
                    send_byte(crc_header_packet[byte_index]);
                end
                if (resume_index == 0) begin
                    expect_clean_packets($sformatf("prefix=%0d resume=%0d", prefix_length, resume_index));
                end else begin
                    expect_recovery($sformatf("prefix=%0d resume=%0d", prefix_length, resume_index));
                end
            end
        end

        // Delete every nonempty contiguous byte range, including a whole frame.
        for (fault_index = 0; fault_index < 11; fault_index = fault_index + 1) begin
            for (fault_end = fault_index + 1; fault_end <= 11; fault_end = fault_end + 1) begin
                for (byte_index = 0; byte_index < 11; byte_index = byte_index + 1) begin
                    if (byte_index < fault_index || byte_index >= fault_end) begin
                        send_byte(crc_header_packet[byte_index]);
                    end
                end
                expect_recovery($sformatf("delete [%0d,%0d)", fault_index, fault_end));
            end
        end

        // Replace each byte with all 256 possible values, including header bytes.
        for (fault_index = 0; fault_index < 11; fault_index = fault_index + 1) begin
            for (fault_value = 0; fault_value < 256; fault_value = fault_value + 1) begin
                for (byte_index = 0; byte_index < 11; byte_index = byte_index + 1) begin
                    send_byte((byte_index == fault_index) ? fault_value[7:0] : crc_header_packet[byte_index]);
                end
                expect_recovery($sformatf("replace byte=%0d value=%02x", fault_index, fault_value));
            end
        end

        // Insert every byte value at every boundary, including before/after a frame.
        for (fault_index = 0; fault_index <= 11; fault_index = fault_index + 1) begin
            for (fault_value = 0; fault_value < 256; fault_value = fault_value + 1) begin
                for (byte_index = 0; byte_index <= 11; byte_index = byte_index + 1) begin
                    if (byte_index == fault_index) begin
                        send_byte(fault_value[7:0]);
                    end
                    if (byte_index < 11) begin
                        send_byte(crc_header_packet[byte_index]);
                    end
                end
                if (fault_index == 0) begin
                    expect_clean_packets($sformatf("insert byte=%0d value=%02x", fault_index, fault_value));
                end else begin
                    expect_recovery($sformatf("insert byte=%0d value=%02x", fault_index, fault_value));
                end
            end
        end

        // Framing only distinguishes d/S/I/B/other. Protocol flags and pot high
        // bytes are always "other". Enumerate all 5^4 low-pot/CRC classes from
        // all 11 reachable states. Arbitrary CRC values overapproximate valid
        // packets; CRC acceptance must not affect the framing recovery bound.
        for (prefix_length = 0; prefix_length < 11; prefix_length = prefix_length + 1) begin
            for (class_index = 0; class_index < 625; class_index = class_index + 1) begin
                for (byte_index = 0; byte_index < prefix_length; byte_index = byte_index + 1) begin
                    send_byte(crc_header_packet[byte_index]);
                end
                if (dut.dsib_parse_state !== prefix_length[3:0]) begin
                    $fatal(1, "did not reach parser state %0d", prefix_length);
                end
                send_header();
                send_byte(8'h00);
                send_byte(header_byte_classes[class_index % 5]);
                send_byte(8'h00);
                send_byte(header_byte_classes[(class_index / 5) % 5]);
                send_byte(8'h00);
                send_byte(header_byte_classes[(class_index / 25) % 5]);
                send_byte(header_byte_classes[(class_index / 125) % 5]);
                if (dut.dsib_parse_state !== dut.DSIB_PARSE_HEADER_D &&
                    dut.dsib_parse_state !== dut.DSIB_PARSE_HEADER_S &&
                    dut.dsib_parse_state !== dut.DSIB_PARSE_HEADER_I) begin
                    $fatal(1, "state=%0d classes=%0d: still consuming a body after one frame",
                           prefix_length, class_index);
                end
                expect_clean_packets($sformatf("state=%0d classes=%0d", prefix_length, class_index));
            end
        end

        $display("dsib_si_parser recovery cases passed: %0d", recovery_cases);
        test_error_counters();
        $display("dsib_si_parser Verilator test passed");
        $finish;
    end
endmodule
