`timescale 1ns / 1ps

module tb_ticket_price_top;

    localparam [3:0] MODE_SELECT          = 4'd0;
    localparam [3:0] MANUAL_FARE          = 4'd1;
    localparam [3:0] ORIGIN_LINE          = 4'd2;
    localparam [3:0] ORIGIN_LINE_BLINK    = 4'd3;
    localparam [3:0] ORIGIN_STATION       = 4'd4;
    localparam [3:0] ORIGIN_STATION_BLINK = 4'd5;
    localparam [3:0] DEST_LINE            = 4'd6;
    localparam [3:0] DEST_LINE_BLINK      = 4'd7;
    localparam [3:0] DEST_STATION         = 4'd8;
    localparam [3:0] DEST_STATION_BLINK   = 4'd9;
    localparam [3:0] TICKET_COUNT         = 4'd11;
    localparam [3:0] PAY                  = 4'd12;
    localparam [3:0] VEND                 = 4'd13;
    localparam [3:0] REFUND               = 4'd14;

    reg clk;
    reg sw4_rst_n;
    reg key1_n;
    reg key2_n;
    reg key3_n;
    reg key4_n;
    reg sw1;
    reg sw2;
    reg sw3;
    wire [3:0] led;
    wire [3:0] logical_led_observed;
    wire [7:0] seg;
    wire [7:0] sel;

    reg [16:0] boundary_distance;
    wire [4:0] boundary_fare;
    reg [2:0] map_line;
    reg [5:0] map_index;
    wire [6:0] map_global;
    wire map_valid;
    wire [5:0] map_count;
    reg lookup_query;
    reg [6:0] lookup_start;
    reg [6:0] lookup_end;
    wire [16:0] lookup_distance;
    wire lookup_valid;
    reg blink_count_test_start;
    reg [3:0] blink_count_test_flashes;
    wire [3:0] blink_count_test_active;
    wire blink_count_test_busy;
    wire blink_count_test_done;
    reg [16:0] expected_distance_rom [0:5355];
    reg [6:0] saved_interchange_id;
    integer ticket_seen;
    integer refund_seen;
    integer line1_digit_flash_count;
    integer line2_digit_flash_count;
    integer line3_digit_flash_count;
    integer line4_digit_flash_count;
    integer all_flash_count;
    integer destination_all_flash_count;
    integer exhaustive_index;
    integer exhaustive_high;
    integer exhaustive_low;
    reg [3:0] previous_led;
    reg [3:0] previous_blink_mask;
    integer vend_hold_count;
    integer simulation_cycle;
    integer ticket_led_flash_count;
    integer last_ticket_flash_cycle;
    integer ticket_flash_interval_error;

    assign logical_led_observed = ~led;

    ticket_price_top #(
        .DEBOUNCE_CYCLES(2),
        .SCAN_DIV(2),
        .BLINK_HALF_CYCLES(2),
        .EVENT_HOLD_CYCLES(50),
        .VEND_HOLD_CYCLES(100),
        .LED_ACTIVE_LOW(1),
        .DISTANCE_ROM_FILE("distance_rom.mem")
    ) dut (
        .clk(clk),
        .sw4_rst_n(sw4_rst_n),
        .key1_n(key1_n),
        .key2_n(key2_n),
        .key3_n(key3_n),
        .key4_n(key4_n),
        .sw1(sw1),
        .sw2(sw2),
        .sw3(sw3),
        .led(led),
        .seg(seg),
        .sel(sel)
    );

    fare_calculator u_boundary_fare (
        .distance_m(boundary_distance),
        .fare_yuan(boundary_fare)
    );

    station_mapper u_mapper_check (
        .line_id(map_line),
        .local_index(map_index),
        .global_id(map_global),
        .valid(map_valid),
        .station_count(map_count)
    );

    distance_lookup #(.ROM_FILE("distance_rom.mem")) u_lookup_check (
        .clk(clk),
        .query_valid(lookup_query),
        .start_station(lookup_start),
        .end_station(lookup_end),
        .distance_m(lookup_distance),
        .result_valid(lookup_valid)
    );

    blink_controller #(.HALF_PERIOD_CYCLES(2)) u_blink_count_check (
        .clk(clk),
        .rst_n(sw4_rst_n),
        .start(blink_count_test_start),
        .mask(4'b1111),
        .flash_count(blink_count_test_flashes),
        .active_mask(blink_count_test_active),
        .busy(blink_count_test_busy),
        .done(blink_count_test_done)
    );

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    always @(posedge clk) begin
        simulation_cycle <= simulation_cycle + 1;
        previous_led <= logical_led_observed;
        previous_blink_mask <= dut.blink_active_mask;
        if (dut.ticket_pulse)
            ticket_seen <= ticket_seen + 1;
        if (dut.refund_pulse)
            refund_seen <= refund_seen + 1;
        if (dut.state != VEND)
            last_ticket_flash_cycle <= -1;
        if ((dut.state == ORIGIN_LINE_BLINK) && dut.blink_active_mask[0] && !previous_blink_mask[0])
            line1_digit_flash_count <= line1_digit_flash_count + 1;
        if ((dut.state == ORIGIN_LINE_BLINK) && dut.blink_active_mask[1] && !previous_blink_mask[1])
            line2_digit_flash_count <= line2_digit_flash_count + 1;
        if ((dut.state == ORIGIN_LINE_BLINK) && dut.blink_active_mask[2] && !previous_blink_mask[2])
            line3_digit_flash_count <= line3_digit_flash_count + 1;
        if ((dut.state == ORIGIN_LINE_BLINK) && dut.blink_active_mask[3] && !previous_blink_mask[3])
            line4_digit_flash_count <= line4_digit_flash_count + 1;
        if ((dut.state == ORIGIN_LINE_BLINK) || (dut.state == DEST_LINE_BLINK)) begin
            if (logical_led_observed !== 4'b0000) begin
                $display("TEST_FAIL: LEDs must stay off while a line number flashes");
                $finish;
            end
            case (dut.selected_line)
                3'd1: if (dut.display_digits[31:16] !== (dut.blink_active_mask[0] ? 16'h1fff : 16'hffff)) begin
                    $display("TEST_FAIL: line 1 digit did not follow blink phase"); $finish; end
                3'd2: if (dut.display_digits[31:16] !== (dut.blink_active_mask[1] ? 16'hf2ff : 16'hffff)) begin
                    $display("TEST_FAIL: line 2 digit did not follow blink phase"); $finish; end
                3'd3: if (dut.display_digits[31:16] !== (dut.blink_active_mask[2] ? 16'hff3f : 16'hffff)) begin
                    $display("TEST_FAIL: line 3 digit did not follow blink phase"); $finish; end
                3'd4: if (dut.display_digits[31:16] !== (dut.blink_active_mask[3] ? 16'hfff4 : 16'hffff)) begin
                    $display("TEST_FAIL: line 4 digit did not follow blink phase"); $finish; end
            endcase
        end
        if ((dut.state == ORIGIN_STATION_BLINK) && (logical_led_observed == 4'b1111) &&
            (previous_led != 4'b1111))
            all_flash_count <= all_flash_count + 1;
        if ((dut.state == DEST_STATION_BLINK) && (logical_led_observed == 4'b1111) &&
            (previous_led != 4'b1111))
            destination_all_flash_count <= destination_all_flash_count + 1;
        if ((dut.state == VEND) && (logical_led_observed == 4'b1111) &&
            (previous_led != 4'b1111)) begin
            ticket_led_flash_count <= ticket_led_flash_count + 1;
            if ((last_ticket_flash_cycle >= 0) &&
                ((simulation_cycle - last_ticket_flash_cycle) != 4))
                ticket_flash_interval_error <= 1;
            last_ticket_flash_cycle <= simulation_cycle;
        end
    end

    task press_key1;
        begin
            key1_n = 1'b0;
            repeat (7) @(posedge clk);
            key1_n = 1'b1;
            repeat (7) @(posedge clk);
        end
    endtask

    task press_key2;
        begin
            key2_n = 1'b0;
            repeat (7) @(posedge clk);
            key2_n = 1'b1;
            repeat (7) @(posedge clk);
        end
    endtask

    task press_key3;
        begin
            key3_n = 1'b0;
            repeat (7) @(posedge clk);
            key3_n = 1'b1;
            repeat (7) @(posedge clk);
        end
    endtask

    task press_key4;
        begin
            key4_n = 1'b0;
            repeat (7) @(posedge clk);
            key4_n = 1'b1;
            repeat (7) @(posedge clk);
        end
    endtask

    task wait_state;
        input [3:0] expected;
        integer cycles;
        begin
            cycles = 0;
            while ((dut.state !== expected) && (cycles < 300)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (dut.state !== expected) begin
                $display("TEST_FAIL: timeout waiting for state %0d, current=%0d", expected, dut.state);
                $finish;
            end
        end
    endtask

    task check_fare;
        input [16:0] distance;
        input [4:0] expected;
        begin
            boundary_distance = distance;
            #1;
            if (boundary_fare !== expected) begin
                $display("TEST_FAIL: distance %0d expected fare %0d, got %0d",
                         distance, expected, boundary_fare);
                $finish;
            end
        end
    endtask

    task check_line_count;
        input [2:0] line_number;
        input [5:0] expected_count;
        begin
            map_line = line_number;
            map_index = 6'd1;
            #1;
            if (!map_valid || (map_count !== expected_count)) begin
                $display("TEST_FAIL: line %0d expected %0d stations, got %0d",
                         line_number, expected_count, map_count);
                $finish;
            end
        end
    endtask

    task save_station_id;
        input [2:0] line_number;
        input [5:0] local_station;
        begin
            map_line = line_number;
            map_index = local_station;
            #1;
            if (!map_valid) begin
                $display("TEST_FAIL: invalid mapping %0d-%0d", line_number, local_station);
                $finish;
            end
            saved_interchange_id = map_global;
        end
    endtask

    task check_same_station_id;
        input [2:0] line_number;
        input [5:0] local_station;
        begin
            map_line = line_number;
            map_index = local_station;
            #1;
            if (!map_valid || (map_global !== saved_interchange_id)) begin
                $display("TEST_FAIL: interchange mapping %0d-%0d", line_number, local_station);
                $finish;
            end
        end
    endtask

    task check_lookup_pair;
        input [6:0] start_station;
        input [6:0] end_station;
        integer high_index;
        integer low_index;
        integer rom_address;
        reg [16:0] expected_distance;
        begin
            if (start_station >= end_station) begin
                high_index = start_station;
                low_index = end_station;
            end else begin
                high_index = end_station;
                low_index = start_station;
            end
            if (start_station == end_station)
                expected_distance = 17'd0;
            else begin
                rom_address = high_index * (high_index - 1) / 2 + low_index;
                expected_distance = expected_distance_rom[rom_address];
            end

            lookup_start = start_station;
            lookup_end = end_station;
            lookup_query = 1'b1;
            @(posedge clk);
            #1 lookup_query = 1'b0;
            @(posedge clk);
            #1;
            if (!lookup_valid || (lookup_distance !== expected_distance)) begin
                $display("TEST_FAIL: lookup pair (%0d,%0d), expected %0d, got %0d, valid=%b",
                         start_station, end_station, expected_distance,
                         lookup_distance, lookup_valid);
                $finish;
            end
        end
    endtask

    task check_requested_flash_count;
        input [3:0] requested;
        integer seen;
        integer cycles;
        time last_rise_time;
        reg previous_active;
        begin
            blink_count_test_flashes = requested;
            blink_count_test_start = 1'b1;
            @(posedge clk);
            #1 blink_count_test_start = 1'b0;
            seen = (blink_count_test_active == 4'b1111) ? 1 : 0;
            cycles = 0;
            // The first active level is sampled after its edge. Start interval
            // timing from the next fully observed rising edge.
            last_rise_time = 0;
            previous_active = (blink_count_test_active == 4'b1111);
            while (blink_count_test_busy && (cycles < 100)) begin
                @(posedge clk);
                #1 cycles = cycles + 1;
                if ((blink_count_test_active == 4'b1111) && !previous_active) begin
                    seen = seen + 1;
                    if ((last_rise_time != 0) && (($time - last_rise_time) != 80)) begin
                        $display("TEST_FAIL: requested flash interval changed for count %0d, delta=%0t",
                                 requested, $time - last_rise_time);
                        $finish;
                    end
                    last_rise_time = $time;
                end
                previous_active = (blink_count_test_active == 4'b1111);
            end
            if ((seen != requested) || blink_count_test_busy) begin
                $display("TEST_FAIL: requested %0d flashes, observed %0d", requested, seen);
                $finish;
            end
            @(posedge clk);
        end
    endtask

    initial begin
        sw4_rst_n = 1'b0;
        key1_n = 1'b1;
        key2_n = 1'b1;
        key3_n = 1'b1;
        key4_n = 1'b1;
        sw1 = 1'b0;
        sw2 = 1'b0;
        sw3 = 1'b0;
        boundary_distance = 17'd0;
        map_line = 3'd0;
        map_index = 6'd0;
        lookup_query = 1'b0;
        lookup_start = 7'd0;
        lookup_end = 7'd0;
        blink_count_test_start = 1'b0;
        blink_count_test_flashes = 4'd1;
        $readmemh("distance_rom.mem", expected_distance_rom);
        saved_interchange_id = 7'd0;
        ticket_seen = 0;
        refund_seen = 0;
        line1_digit_flash_count = 0;
        line2_digit_flash_count = 0;
        line3_digit_flash_count = 0;
        line4_digit_flash_count = 0;
        all_flash_count = 0;
        destination_all_flash_count = 0;
        previous_led = 4'b0000;
        previous_blink_mask = 4'b0000;
        vend_hold_count = 0;
        simulation_cycle = 0;
        ticket_led_flash_count = 0;
        last_ticket_flash_cycle = -1;
        ticket_flash_interval_error = 0;

        // The independent Python checker proves the ROM values. This loop
        // proves the FPGA triangular-address and read timing for all 5460
        // unordered station pairs, including the 104 same-station cases.
        repeat (3) @(posedge clk);
        for (exhaustive_index = 0; exhaustive_index < 104; exhaustive_index = exhaustive_index + 1)
            check_lookup_pair(exhaustive_index[6:0], exhaustive_index[6:0]);
        for (exhaustive_high = 1; exhaustive_high < 104; exhaustive_high = exhaustive_high + 1)
            for (exhaustive_low = 0; exhaustive_low < exhaustive_high; exhaustive_low = exhaustive_low + 1)
                check_lookup_pair(exhaustive_high[6:0], exhaustive_low[6:0]);

        check_fare(17'd4000, 5'd2);
        check_fare(17'd4001, 5'd3);
        check_fare(17'd9000, 5'd3);
        check_fare(17'd9001, 5'd4);
        check_fare(17'd14000, 5'd4);
        check_fare(17'd14001, 5'd5);
        check_fare(17'd21000, 5'd5);
        check_fare(17'd21001, 5'd6);
        check_fare(17'd28000, 5'd6);
        check_fare(17'd28001, 5'd7);
        check_fare(17'd37000, 5'd7);
        check_fare(17'd37001, 5'd8);
        check_fare(17'd48000, 5'd8);
        check_fare(17'd48001, 5'd9);
        check_fare(17'd61000, 5'd9);
        check_fare(17'd61001, 5'd10);
        check_fare(17'd76000, 5'd10);
        check_fare(17'd76001, 5'd11);

        // All four line selectors and all seven interchange aliases are mapped.
        check_line_count(3'd1, 6'd32);
        check_line_count(3'd2, 6'd30);
        check_line_count(3'd3, 6'd31);
        check_line_count(3'd4, 6'd18);
        save_station_id(3'd1, 6'd8);   check_same_station_id(3'd3, 6'd10); // 南京站
        save_station_id(3'd1, 6'd13);  check_same_station_id(3'd2, 6'd15); // 新街口
        save_station_id(3'd1, 6'd21);  check_same_station_id(3'd3, 6'd22); // 南京南站
        save_station_id(3'd2, 6'd16);  check_same_station_id(3'd3, 6'd14); // 大行宫
        save_station_id(3'd2, 6'd24);  check_same_station_id(3'd4, 6'd12); // 金马路
        save_station_id(3'd1, 6'd11);  check_same_station_id(3'd4, 6'd4);  // 鼓楼
        save_station_id(3'd3, 6'd12);  check_same_station_id(3'd4, 6'd5);  // 鸡鸣寺

        repeat (5) @(posedge clk);
        sw4_rst_n = 1'b1;
        repeat (6) @(posedge clk);
        wait_state(MODE_SELECT);

        // The generic controller must honor every supported ticket count with
        // the same rising-edge interval.
        for (exhaustive_index = 1; exhaustive_index <= 9; exhaustive_index = exhaustive_index + 1)
            check_requested_flash_count(exhaustive_index[3:0]);

        // Mode 1: select a known fare of 4 yuan and two tickets.
        press_key1;
        wait_state(MANUAL_FARE);
        press_key4;
        if (dut.unit_fare !== 5'd15) begin
            $display("TEST_FAIL: manual fare backward wrap");
            $finish;
        end
        press_key3;
        if (dut.unit_fare !== 5'd2) begin
            $display("TEST_FAIL: manual fare forward wrap");
            $finish;
        end
        press_key3;
        press_key3;
        if (dut.unit_fare !== 5'd4) begin
            $display("TEST_FAIL: manual fare selection");
            $finish;
        end
        press_key1;
        wait_state(TICKET_COUNT);
        press_key4;
        if (dut.ticket_count !== 4'd9) begin
            $display("TEST_FAIL: ticket-count backward wrap");
            $finish;
        end
        press_key3;
        if (dut.ticket_count !== 4'd1) begin
            $display("TEST_FAIL: ticket-count forward wrap");
            $finish;
        end
        press_key3;
        press_key1;
        wait_state(PAY);
        if ((dut.ticket_count !== 4'd2) || (dut.total_due !== 10'd8) ||
            (dut.display_digits !== 32'h008ff000)) begin
            $display("TEST_FAIL: ticket count, total due or initial paid display");
            $finish;
        end

        // Invalid code is ignored. Insert 1 + 5 + 10 yuan; vend once and return 8 yuan.
        {sw3, sw2, sw1} = 3'b000;
        press_key1;
        if ((dut.state !== PAY) || (dut.paid_amount !== 10'd0)) begin
            $display("TEST_FAIL: invalid payment code was not ignored");
            $finish;
        end
        {sw3, sw2, sw1} = 3'b001;
        press_key1;
        if ((dut.state !== PAY) || (dut.paid_amount !== 10'd1) ||
            (dut.display_digits !== 32'h008ff001)) begin
            $display("TEST_FAIL: one-yuan payment/paid display");
            $finish;
        end
        {sw3, sw2, sw1} = 3'b010;
        press_key1;
        if ((dut.state !== PAY) || (dut.paid_amount !== 10'd6) ||
            (dut.display_digits !== 32'h008ff006)) begin
            $display("TEST_FAIL: five-yuan payment/paid display");
            $finish;
        end
        {sw3, sw2, sw1} = 3'b011;
        press_key1;
        wait_state(VEND);
        if ((dut.change_amount !== 10'd8) || (ticket_seen !== 1) ||
            (dut.display_digits !== 32'hfffff008)) begin
            $display("TEST_FAIL: automatic vend/change, change=%0d tickets=%0d",
                     dut.change_amount, ticket_seen);
            $finish;
        end
        while ((dut.state == VEND) && (vend_hold_count < 200)) begin
            @(posedge clk);
            vend_hold_count = vend_hold_count + 1;
        end
        if ((dut.state !== MODE_SELECT) || (vend_hold_count < 70)) begin
            $display("TEST_FAIL: change-only display did not remain long enough");
            $finish;
        end
        if ((ticket_led_flash_count !== 2) || ticket_flash_interval_error) begin
            $display("TEST_FAIL: two-ticket LED flash count/interval, count=%0d interval_error=%0d",
                     ticket_led_flash_count, ticket_flash_interval_error);
            $finish;
        end
        if (ticket_seen !== 1) begin
            $display("TEST_FAIL: vend pulse was generated more than once");
            $finish;
        end

        // Cancellation in PAY returns the complete inserted amount once.
        press_key1;
        press_key4;
        press_key1;
        press_key3;
        press_key1;
        wait_state(PAY);
        if ((dut.unit_fare !== 5'd15) || (dut.ticket_count !== 4'd2) ||
            (dut.total_due !== 10'd30)) begin
            $display("TEST_FAIL: cancellation scenario setup");
            $finish;
        end
        {sw3, sw2, sw1} = 3'b100;
        press_key1;
        press_key4;
        wait_state(REFUND);
        if ((dut.refund_amount !== 10'd20) || (refund_seen !== 1) ||
            (ticket_seen !== 1) || (logical_led_observed !== 4'b1001) ||
            (dut.display_digits[11:0] !== 12'h020)) begin
            $display("TEST_FAIL: one-shot cancellation refund");
            $finish;
        end
        wait_state(MODE_SELECT);
        if (refund_seen !== 1) begin
            $display("TEST_FAIL: refund pulse was generated more than once");
            $finish;
        end

        // Every line-selection key must flash its matching seven-segment digit,
        // while all four LEDs remain off.
        press_key2;
        wait_state(ORIGIN_LINE);
        if (dut.display_digits[31:16] !== 16'h1234) begin
            $display("TEST_FAIL: line-selection display does not show 1234");
            $finish;
        end
        press_key1;
        wait_state(ORIGIN_STATION);
        if ((dut.selected_line !== 3'd1) || (line1_digit_flash_count !== 2)) begin
            $display("TEST_FAIL: KEY1/line1 digit selection");
            $finish;
        end
        press_key2;
        wait_state(ORIGIN_LINE);
        press_key2;
        wait_state(ORIGIN_STATION);
        if ((dut.selected_line !== 3'd2) || (line2_digit_flash_count !== 2)) begin
            $display("TEST_FAIL: KEY2/line2 digit selection");
            $finish;
        end
        press_key2;
        wait_state(ORIGIN_LINE);
        press_key3;
        wait_state(ORIGIN_STATION);
        if ((dut.selected_line !== 3'd3) || (line3_digit_flash_count !== 2)) begin
            $display("TEST_FAIL: KEY3/line3 digit selection");
            $finish;
        end
        press_key2;
        wait_state(ORIGIN_LINE);
        press_key4;
        wait_state(ORIGIN_STATION);
        if ((dut.selected_line !== 3'd4) || (line4_digit_flash_count !== 2)) begin
            $display("TEST_FAIL: KEY4/line4 digit selection");
            $finish;
        end
        press_key2;
        wait_state(ORIGIN_LINE);

        // Mode 2: line 1 station 101 to station 105 is 4.784 km, hence 3 yuan.
        {sw3, sw2, sw1} = 3'b000;
        press_key1;
        wait_state(ORIGIN_STATION);
        if (line1_digit_flash_count !== 4) begin
            $display("TEST_FAIL: selected line digit flashed %0d times", line1_digit_flash_count);
            $finish;
        end
        press_key1;
        wait_state(DEST_LINE);
        if (all_flash_count !== 2) begin
            $display("TEST_FAIL: all LEDs flashed %0d times", all_flash_count);
            $finish;
        end
        press_key1;
        wait_state(DEST_STATION);
        press_key3;
        press_key3;
        press_key3;
        press_key3;
        if (dut.station_index !== 6'd5) begin
            $display("TEST_FAIL: station forward selection");
            $finish;
        end
        press_key1;
        wait_state(TICKET_COUNT);
        if ((dut.last_distance_m !== 17'd4784) || (dut.unit_fare !== 5'd3)) begin
            $display("TEST_FAIL: distance fare lookup, distance=%0d fare=%0d",
                     dut.last_distance_m, dut.unit_fare);
            $finish;
        end
        press_key1;
        wait_state(PAY);
        {sw3, sw2, sw1} = 3'b010;
        press_key1;
        wait_state(VEND);
        if ((dut.change_amount !== 10'd2) || (ticket_seen !== 2)) begin
            $display("TEST_FAIL: automatic-mode purchase");
            $finish;
        end
        wait_state(MODE_SELECT);
        if ((ticket_led_flash_count !== 3) || ticket_flash_interval_error) begin
            $display("TEST_FAIL: one-ticket LED flash count/interval after second vend");
            $finish;
        end

        // Full cross-line query: 113 (Xinjiekou) to 401 (Longjiang).
        // The shortest path transfers at Gulou: 2009 m + 3677 m = 5686 m.
        press_key2;
        wait_state(ORIGIN_LINE);
        press_key1;
        wait_state(ORIGIN_STATION);
        press_key4;
        if (dut.station_index !== 6'd32) begin
            $display("TEST_FAIL: station backward wrap");
            $finish;
        end
        press_key3;
        if (dut.station_index !== 6'd1) begin
            $display("TEST_FAIL: station forward wrap");
            $finish;
        end
        repeat (12) press_key3;
        if ((dut.station_index !== 6'd13) ||
            (dut.display_digits[31:28] !== 4'd1) ||
            (dut.display_digits[11:0] !== 12'h113)) begin
            $display("TEST_FAIL: origin station code 113");
            $finish;
        end
        press_key1;
        wait_state(DEST_LINE);
        press_key4;
        wait_state(DEST_STATION);
        if ((dut.selected_line !== 3'd4) ||
            (dut.display_digits[11:0] !== 12'h401)) begin
            $display("TEST_FAIL: destination station code 401");
            $finish;
        end
        press_key1;
        wait_state(TICKET_COUNT);
        if ((dut.last_distance_m !== 17'd5686) || (dut.unit_fare !== 5'd3) ||
            (dut.display_digits[31:28] !== 4'hf) ||
            (dut.display_digits[27:24] !== 4'd3) ||
            (destination_all_flash_count !== 4)) begin
            $display("TEST_FAIL: cross-line shortest distance/fare/display, distance=%0d fare=%0d flashes=%0d",
                     dut.last_distance_m, dut.unit_fare, destination_all_flash_count);
            $finish;
        end
        press_key2;
        wait_state(MODE_SELECT);

        $display("TEST_PASS: all 5460 station lookups, active-low LEDs, isolated line-digit double flashes, 31-station extended line 3, navigation, fares, total/paid display, change-only hold, ticket-count LED flashes with fixed interval, and cancellation refund are correct.");
        $finish;
    end

endmodule
