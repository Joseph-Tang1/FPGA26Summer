`timescale 1ns / 1ps

module tb_ticket_price_top;

    localparam [3:0] MODE_SELECT          = 4'd0;
    localparam [3:0] MANUAL_FARE          = 4'd1;
    localparam [3:0] ORIGIN_LINE          = 4'd2;
    localparam [3:0] ORIGIN_LINE_BLINK    = 4'd3;
    localparam [3:0] ORIGIN_STATION       = 4'd4;
    localparam [3:0] ORIGIN_STATION_BLINK = 4'd5;
    localparam [3:0] DEST_LINE            = 4'd6;
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
    wire [7:0] seg;
    wire [7:0] sel;

    reg [16:0] boundary_distance;
    wire [4:0] boundary_fare;
    reg [2:0] map_line;
    reg [5:0] map_index;
    wire [6:0] map_global;
    wire map_valid;
    wire [5:0] map_count;
    reg [6:0] saved_interchange_id;
    integer ticket_seen;
    integer refund_seen;
    integer line1_flash_count;
    integer line2_flash_count;
    integer line3_flash_count;
    integer line4_flash_count;
    integer all_flash_count;
    integer destination_all_flash_count;
    reg [3:0] previous_led;

    ticket_price_top #(
        .DEBOUNCE_CYCLES(2),
        .SCAN_DIV(2),
        .BLINK_HALF_CYCLES(2),
        .EVENT_HOLD_CYCLES(50),
        .LED_ACTIVE_LOW(0),
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

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    always @(posedge clk) begin
        previous_led <= led;
        if (dut.ticket_pulse)
            ticket_seen <= ticket_seen + 1;
        if (dut.refund_pulse)
            refund_seen <= refund_seen + 1;
        if ((dut.state == ORIGIN_LINE_BLINK) && led[0] && !previous_led[0])
            line1_flash_count <= line1_flash_count + 1;
        if ((dut.state == ORIGIN_LINE_BLINK) && led[1] && !previous_led[1])
            line2_flash_count <= line2_flash_count + 1;
        if ((dut.state == ORIGIN_LINE_BLINK) && led[2] && !previous_led[2])
            line3_flash_count <= line3_flash_count + 1;
        if ((dut.state == ORIGIN_LINE_BLINK) && led[3] && !previous_led[3])
            line4_flash_count <= line4_flash_count + 1;
        if ((dut.state == ORIGIN_STATION_BLINK) && (led == 4'b1111) &&
            (previous_led != 4'b1111))
            all_flash_count <= all_flash_count + 1;
        if ((dut.state == DEST_STATION_BLINK) && (led == 4'b1111) &&
            (previous_led != 4'b1111))
            destination_all_flash_count <= destination_all_flash_count + 1;
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
        saved_interchange_id = 7'd0;
        ticket_seen = 0;
        refund_seen = 0;
        line1_flash_count = 0;
        line2_flash_count = 0;
        line3_flash_count = 0;
        line4_flash_count = 0;
        all_flash_count = 0;
        destination_all_flash_count = 0;
        previous_led = 4'b0000;

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
        check_line_count(3'd3, 6'd29);
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
        if ((dut.ticket_count !== 4'd2) || (dut.total_due !== 10'd8)) begin
            $display("TEST_FAIL: ticket count or total due");
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
        if ((dut.state !== PAY) || (dut.paid_amount !== 10'd1)) begin
            $display("TEST_FAIL: one-yuan payment");
            $finish;
        end
        {sw3, sw2, sw1} = 3'b010;
        press_key1;
        if ((dut.state !== PAY) || (dut.paid_amount !== 10'd6)) begin
            $display("TEST_FAIL: five-yuan payment");
            $finish;
        end
        {sw3, sw2, sw1} = 3'b011;
        press_key1;
        wait_state(VEND);
        if ((dut.change_amount !== 10'd8) || (ticket_seen !== 1) ||
            (led !== 4'b1111) || (dut.display_digits[11:0] !== 12'h008)) begin
            $display("TEST_FAIL: automatic vend/change, change=%0d tickets=%0d",
                     dut.change_amount, ticket_seen);
            $finish;
        end
        wait_state(MODE_SELECT);
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
            (ticket_seen !== 1) || (led !== 4'b1001) ||
            (dut.display_digits[11:0] !== 12'h020)) begin
            $display("TEST_FAIL: one-shot cancellation refund");
            $finish;
        end
        wait_state(MODE_SELECT);
        if (refund_seen !== 1) begin
            $display("TEST_FAIL: refund pulse was generated more than once");
            $finish;
        end

        // Every line-selection key must select its matching line and LED.
        press_key2;
        wait_state(ORIGIN_LINE);
        if (dut.display_digits[31:16] !== 16'h1234) begin
            $display("TEST_FAIL: line-selection display does not show 1234");
            $finish;
        end
        press_key1;
        wait_state(ORIGIN_STATION);
        if ((dut.selected_line !== 3'd1) || (line1_flash_count !== 2)) begin
            $display("TEST_FAIL: KEY1/line1/LED1 selection");
            $finish;
        end
        press_key2;
        wait_state(ORIGIN_LINE);
        press_key2;
        wait_state(ORIGIN_STATION);
        if ((dut.selected_line !== 3'd2) || (line2_flash_count !== 2)) begin
            $display("TEST_FAIL: KEY2/line2/LED2 selection");
            $finish;
        end
        press_key2;
        wait_state(ORIGIN_LINE);
        press_key3;
        wait_state(ORIGIN_STATION);
        if ((dut.selected_line !== 3'd3) || (line3_flash_count !== 2)) begin
            $display("TEST_FAIL: KEY3/line3/LED3 selection");
            $finish;
        end
        press_key2;
        wait_state(ORIGIN_LINE);
        press_key4;
        wait_state(ORIGIN_STATION);
        if ((dut.selected_line !== 3'd4) || (line4_flash_count !== 2)) begin
            $display("TEST_FAIL: KEY4/line4/LED4 selection");
            $finish;
        end
        press_key2;
        wait_state(ORIGIN_LINE);

        // Mode 2: line 1 station 101 to station 105 is 4.784 km, hence 3 yuan.
        {sw3, sw2, sw1} = 3'b000;
        press_key1;
        wait_state(ORIGIN_STATION);
        if (line1_flash_count !== 4) begin
            $display("TEST_FAIL: selected line LED flashed %0d times", line1_flash_count);
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

        $display("TEST_PASS: four-line keys/LEDs, station navigation, interchanges, same-line and cross-line shortest distance, fare/display boundaries, all payment denominations, ticket count, one-shot vend/change and cancellation refund are correct.");
        $finish;
    end

endmodule
