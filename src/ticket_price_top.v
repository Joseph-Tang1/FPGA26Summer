`timescale 1ns / 1ps

module ticket_price_top #(
    parameter integer DEBOUNCE_CYCLES    = 1_000_000,
    parameter integer SCAN_DIV           = 50_000,
    parameter integer BLINK_HALF_CYCLES  = 12_500_000,
    parameter integer EVENT_HOLD_CYCLES  = 50_000_000,
    parameter integer VEND_HOLD_CYCLES   = 150_000_000,
    parameter integer LED_ACTIVE_LOW     = 0,
    parameter         DISTANCE_ROM_FILE  = "distance_rom.mem"
) (
    input  wire       clk,
    input  wire       sw4_rst_n,
    input  wire       key1_n,
    input  wire       key2_n,
    input  wire       key3_n,
    input  wire       key4_n,
    input  wire       sw1,
    input  wire       sw2,
    input  wire       sw3,
    output wire [3:0] led,
    output wire [7:0] seg,
    output wire [7:0] sel
);

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
    localparam [3:0] CALC_WAIT            = 4'd10;
    localparam [3:0] TICKET_COUNT         = 4'd11;
    localparam [3:0] PAY                  = 4'd12;
    localparam [3:0] VEND                 = 4'd13;
    localparam [3:0] REFUND               = 4'd14;

    wire key1_pressed;
    wire key2_pressed;
    wire key3_pressed;
    wire key4_pressed;

    reg [3:0] state;
    reg [2:0] selected_line;
    reg [5:0] station_index;
    reg [6:0] origin_global;
    reg [6:0] destination_global;
    reg [2:0] origin_line_saved;
    reg [5:0] origin_station_saved;
    reg [4:0] unit_fare;
    reg [3:0] ticket_count;
    reg [9:0] total_due;
    reg [9:0] paid_amount;
    reg [9:0] change_amount;
    reg [9:0] refund_amount;
    reg [16:0] last_distance_m;
    reg [31:0] event_count;
    reg [31:0] line_blink_count;
    reg        line_blink_on;

    reg        blink_start;
    reg [3:0]  blink_mask;
    reg [3:0]  blink_flash_count;
    wire [3:0] blink_active_mask;
    wire       blink_busy;
    wire       blink_done;

    reg  distance_query;
    wire [16:0] lookup_distance_m;
    wire        distance_valid;
    wire [4:0]  calculated_fare;

    wire [6:0] mapped_global;
    wire       mapped_valid;
    wire [5:0] selected_line_count;

    reg ticket_pulse;
    reg refund_pulse;

    reg [5:0] coin_value;
    reg [9:0] inserted_sum;
    reg [9:0] station_code;

    wire [11:0] fare_bcd;
    wire [11:0] count_bcd;
    wire [11:0] total_bcd;
    wire [11:0] paid_bcd;
    wire [11:0] change_bcd;
    wire [11:0] refund_bcd;
    wire [11:0] station_bcd;
    reg  [31:0] display_digits;
    reg  [3:0] logical_led;

    // HX7A75C switches are electrically 1 when moved up and 0 when moved
    // down. Invert all four switches so the user-facing 0/1 convention is
    // reversed. The SW4 input keeps its legacy port name for XDC stability.
    wire internal_rst_n = sw4_rst_n;
    wire sw1_logic = ~sw1;
    wire sw2_logic = ~sw2;
    wire sw3_logic = ~sw3;

    key_filter #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_key1 (
        .clk(clk), .rst_n(internal_rst_n), .key_n(key1_n), .press_pulse(key1_pressed)
    );
    key_filter #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_key2 (
        .clk(clk), .rst_n(internal_rst_n), .key_n(key2_n), .press_pulse(key2_pressed)
    );
    key_filter #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_key3 (
        .clk(clk), .rst_n(internal_rst_n), .key_n(key3_n), .press_pulse(key3_pressed)
    );
    key_filter #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_key4 (
        .clk(clk), .rst_n(internal_rst_n), .key_n(key4_n), .press_pulse(key4_pressed)
    );

    blink_controller #(.HALF_PERIOD_CYCLES(BLINK_HALF_CYCLES)) u_blink (
        .clk(clk),
        .rst_n(internal_rst_n),
        .start(blink_start),
        .mask(blink_mask),
        .flash_count(blink_flash_count),
        .active_mask(blink_active_mask),
        .busy(blink_busy),
        .done(blink_done)
    );

    station_mapper u_station_mapper (
        .line_id(selected_line),
        .local_index(station_index),
        .global_id(mapped_global),
        .valid(mapped_valid),
        .station_count(selected_line_count)
    );

    distance_lookup #(.ROM_FILE(DISTANCE_ROM_FILE)) u_distance_lookup (
        .clk(clk),
        .query_valid(distance_query),
        .start_station(origin_global),
        .end_station(destination_global),
        .distance_m(lookup_distance_m),
        .result_valid(distance_valid)
    );

    fare_calculator u_fare_calculator (
        .distance_m(lookup_distance_m),
        .fare_yuan(calculated_fare)
    );

    binary_to_bcd u_fare_bcd (
        .binary({5'd0, unit_fare}),
        .bcd(fare_bcd)
    );
    binary_to_bcd u_count_bcd (
        .binary({6'd0, ticket_count}),
        .bcd(count_bcd)
    );
    binary_to_bcd u_total_bcd (
        .binary(total_due),
        .bcd(total_bcd)
    );
    binary_to_bcd u_paid_bcd (
        .binary(paid_amount),
        .bcd(paid_bcd)
    );
    binary_to_bcd u_change_bcd (
        .binary(change_amount),
        .bcd(change_bcd)
    );
    binary_to_bcd u_refund_bcd (
        .binary(refund_amount),
        .bcd(refund_bcd)
    );
    binary_to_bcd u_station_bcd (
        .binary(station_code),
        .bcd(station_bcd)
    );

    seven_seg_display #(.SCAN_DIV(SCAN_DIV)) u_display (
        .clk(clk),
        .rst_n(internal_rst_n),
        .digits(display_digits),
        .seg(seg),
        .sel(sel)
    );

    always @(*) begin
        case ({sw3_logic, sw2_logic, sw1_logic})
            3'b001: coin_value = 6'd1;
            3'b010: coin_value = 6'd5;
            3'b011: coin_value = 6'd10;
            3'b100: coin_value = 6'd20;
            default: coin_value = 6'd0;
        endcase
        inserted_sum = paid_amount + coin_value;
    end

    always @(*) begin
        case (selected_line)
            3'd1: station_code = 10'd100 + station_index;
            3'd2: station_code = 10'd200 + station_index;
            3'd3: station_code = 10'd300 + station_index;
            3'd4: station_code = 10'd400 + station_index;
            3'd5: station_code = 10'd500 + station_index;
            default: station_code = 10'd0;
        endcase
    end

    // Use a synchronous reset for registers that feed the block-RAM address.
    // This keeps asynchronous control signals out of the inferred BRAM path.
    always @(posedge clk) begin
        if (!internal_rst_n) begin
            state              <= MODE_SELECT;
            selected_line      <= 3'd0;
            station_index      <= 6'd1;
            origin_global      <= 7'd0;
            destination_global <= 7'd0;
            origin_line_saved  <= 3'd1;
            origin_station_saved <= 6'd1;
            unit_fare          <= 5'd2;
            ticket_count       <= 4'd1;
            total_due          <= 10'd0;
            paid_amount        <= 10'd0;
            change_amount      <= 10'd0;
            refund_amount      <= 10'd0;
            last_distance_m    <= 17'd0;
            event_count        <= 32'd0;
            line_blink_count   <= 32'd0;
            line_blink_on      <= 1'b1;
            blink_start        <= 1'b0;
            blink_mask         <= 4'b0000;
            blink_flash_count  <= 4'd2;
            distance_query     <= 1'b0;
            ticket_pulse       <= 1'b0;
            refund_pulse       <= 1'b0;
        end else begin
            blink_start    <= 1'b0;
            distance_query <= 1'b0;
            ticket_pulse   <= 1'b0;
            refund_pulse   <= 1'b0;

            // In either line-selection screen the selected digit flashes
            // continuously; the other four line digits remain constant.
            if ((state == ORIGIN_LINE) || (state == DEST_LINE)) begin
                if (line_blink_count >= BLINK_HALF_CYCLES - 1) begin
                    line_blink_count <= 32'd0;
                    line_blink_on <= ~line_blink_on;
                end else begin
                    line_blink_count <= line_blink_count + 1'b1;
                end
            end else begin
                line_blink_count <= 32'd0;
                line_blink_on <= 1'b1;
            end

            case (state)
                MODE_SELECT: begin
                    selected_line <= 3'd0;
                    station_index <= 6'd1;
                    paid_amount   <= 10'd0;
                    total_due     <= 10'd0;
                    change_amount <= 10'd0;
                    refund_amount <= 10'd0;
                    event_count   <= 32'd0;
                    ticket_count  <= 4'd1;
                    if (key1_pressed) begin
                        unit_fare <= 5'd2;
                        state <= MANUAL_FARE;
                    end else if (key2_pressed) begin
                        selected_line <= 3'd1;
                        state <= ORIGIN_LINE;
                    end
                end

                MANUAL_FARE: begin
                    if (key3_pressed) begin
                        if (unit_fare >= 5'd15)
                            unit_fare <= 5'd2;
                        else
                            unit_fare <= unit_fare + 1'b1;
                    end else if (key4_pressed) begin
                        if (unit_fare <= 5'd2)
                            unit_fare <= 5'd15;
                        else
                            unit_fare <= unit_fare - 1'b1;
                    end else if (key1_pressed) begin
                        ticket_count <= 4'd1;
                        state <= TICKET_COUNT;
                    end else if (key2_pressed) begin
                        state <= MODE_SELECT;
                    end
                end

                ORIGIN_LINE: begin
                    if (key1_pressed) begin
                        station_index <= 6'd1;
                        state <= ORIGIN_STATION;
                    end else if (key2_pressed) begin
                        state <= MODE_SELECT;
                    end else if (key3_pressed) begin
                        if (selected_line >= 3'd5)
                            selected_line <= 3'd1;
                        else
                            selected_line <= selected_line + 1'b1;
                    end else if (key4_pressed) begin
                        if (selected_line <= 3'd1)
                            selected_line <= 3'd5;
                        else
                            selected_line <= selected_line - 1'b1;
                    end
                end

                ORIGIN_LINE_BLINK: begin
                    if (blink_done) begin
                        station_index <= 6'd1;
                        state <= ORIGIN_STATION;
                    end
                end

                ORIGIN_STATION: begin
                    if (key3_pressed) begin
                        if (station_index >= selected_line_count)
                            station_index <= 6'd1;
                        else
                            station_index <= station_index + 1'b1;
                    end else if (key4_pressed) begin
                        if (station_index <= 6'd1)
                            station_index <= selected_line_count;
                        else
                            station_index <= station_index - 1'b1;
                    end else if (key1_pressed && mapped_valid) begin
                        origin_global <= mapped_global;
                        origin_line_saved <= selected_line;
                        origin_station_saved <= station_index;
                        blink_mask <= 4'b1111;
                        blink_flash_count <= 4'd2;
                        blink_start <= 1'b1;
                        state <= ORIGIN_STATION_BLINK;
                    end else if (key2_pressed) begin
                        state <= ORIGIN_LINE;
                    end
                end

                ORIGIN_STATION_BLINK: begin
                    if (blink_done) begin
                        selected_line <= 3'd1;
                        station_index <= 6'd1;
                        state <= DEST_LINE;
                    end
                end

                DEST_LINE: begin
                    if (key1_pressed) begin
                        station_index <= 6'd1;
                        state <= DEST_STATION;
                    end else if (key2_pressed) begin
                        selected_line <= origin_line_saved;
                        station_index <= origin_station_saved;
                        state <= ORIGIN_STATION;
                    end else if (key3_pressed) begin
                        if (selected_line >= 3'd5)
                            selected_line <= 3'd1;
                        else
                            selected_line <= selected_line + 1'b1;
                    end else if (key4_pressed) begin
                        if (selected_line <= 3'd1)
                            selected_line <= 3'd5;
                        else
                            selected_line <= selected_line - 1'b1;
                    end
                end

                DEST_LINE_BLINK: begin
                    if (blink_done) begin
                        station_index <= 6'd1;
                        state <= DEST_STATION;
                    end
                end

                DEST_STATION: begin
                    if (key3_pressed) begin
                        if (station_index >= selected_line_count)
                            station_index <= 6'd1;
                        else
                            station_index <= station_index + 1'b1;
                    end else if (key4_pressed) begin
                        if (station_index <= 6'd1)
                            station_index <= selected_line_count;
                        else
                            station_index <= station_index - 1'b1;
                    end else if (key1_pressed && mapped_valid) begin
                        destination_global <= mapped_global;
                        blink_mask <= 4'b1111;
                        blink_flash_count <= 4'd2;
                        blink_start <= 1'b1;
                        state <= DEST_STATION_BLINK;
                    end else if (key2_pressed) begin
                        state <= DEST_LINE;
                    end
                end

                DEST_STATION_BLINK: begin
                    if (blink_done) begin
                        distance_query <= 1'b1;
                        state <= CALC_WAIT;
                    end
                end

                CALC_WAIT: begin
                    if (distance_valid) begin
                        last_distance_m <= lookup_distance_m;
                        unit_fare <= calculated_fare;
                        ticket_count <= 4'd1;
                        state <= TICKET_COUNT;
                    end
                end

                TICKET_COUNT: begin
                    if (key3_pressed) begin
                        if (ticket_count >= 4'd9)
                            ticket_count <= 4'd1;
                        else
                            ticket_count <= ticket_count + 1'b1;
                    end else if (key4_pressed) begin
                        if (ticket_count <= 4'd1)
                            ticket_count <= 4'd9;
                        else
                            ticket_count <= ticket_count - 1'b1;
                    end else if (key1_pressed) begin
                        total_due <= unit_fare * ticket_count;
                        paid_amount <= 10'd0;
                        change_amount <= 10'd0;
                        state <= PAY;
                    end else if (key2_pressed) begin
                        state <= MODE_SELECT;
                    end
                end

                PAY: begin
                    if (key4_pressed) begin
                        refund_amount <= paid_amount;
                        refund_pulse <= 1'b1;
                        event_count <= 32'd0;
                        state <= REFUND;
                    end else if (key1_pressed && coin_value != 0) begin
                        paid_amount <= inserted_sum;
                        if (inserted_sum >= total_due) begin
                            change_amount <= inserted_sum - total_due;
                            ticket_pulse <= 1'b1;
                            blink_mask <= 4'b1111;
                            blink_flash_count <= ticket_count;
                            blink_start <= 1'b1;
                            event_count <= 32'd0;
                            state <= VEND;
                        end
                    end
                end

                VEND: begin
                    if ((event_count >= VEND_HOLD_CYCLES - 1) && !blink_busy) begin
                        event_count <= 32'd0;
                        state <= MODE_SELECT;
                    end else begin
                        event_count <= event_count + 1'b1;
                    end
                end

                REFUND: begin
                    if (event_count >= EVENT_HOLD_CYCLES - 1) begin
                        event_count <= 32'd0;
                        state <= MODE_SELECT;
                    end else begin
                        event_count <= event_count + 1'b1;
                    end
                end

                default: state <= MODE_SELECT;
            endcase
        end
    end

    always @(*) begin
        logical_led = 4'b0000;
        if (blink_busy && ((state == ORIGIN_STATION_BLINK) ||
                           (state == DEST_STATION_BLINK) ||
                           (state == VEND)))
            logical_led = blink_active_mask;
        else if (state == REFUND)
            logical_led = 4'b1001;
    end

    assign led = LED_ACTIVE_LOW ? ~logical_led : logical_led;

    always @(*) begin
        display_digits = 32'hffffffff;
        case (state)
            MODE_SELECT: begin
                display_digits[31:28] = 4'd1;
                display_digits[3:0] = 4'd2;
            end

            MANUAL_FARE: begin
                display_digits[31:28] = (fare_bcd[7:4] == 0) ? 4'hf : fare_bcd[7:4];
                display_digits[27:24] = fare_bcd[3:0];
            end

            ORIGIN_LINE, DEST_LINE: begin
                display_digits[31:12] = {4'd1, 4'd2, 4'd3, 4'd4, 4'd5};
                if (!line_blink_on) begin
                    case (selected_line)
                        3'd1: display_digits[31:28] = 4'hf;
                        3'd2: display_digits[27:24] = 4'hf;
                        3'd3: display_digits[23:20] = 4'hf;
                        3'd4: display_digits[19:16] = 4'hf;
                        3'd5: display_digits[15:12] = 4'hf;
                        default: display_digits[31:12] = {4'd1, 4'd2, 4'd3, 4'd4, 4'd5};
                    endcase
                end
            end

            ORIGIN_LINE_BLINK, DEST_LINE_BLINK: begin
                display_digits[31:16] = 16'hffff;
                case (selected_line)
                    3'd1: if (blink_active_mask[0]) display_digits[31:28] = 4'd1;
                    3'd2: if (blink_active_mask[1]) display_digits[27:24] = 4'd2;
                    3'd3: if (blink_active_mask[2]) display_digits[23:20] = 4'd3;
                    3'd4: if (blink_active_mask[3]) display_digits[19:16] = 4'd4;
                    default: display_digits[31:16] = 16'hffff;
                endcase
            end

            ORIGIN_STATION, ORIGIN_STATION_BLINK,
            DEST_STATION, DEST_STATION_BLINK: begin
                display_digits[31:28] = {1'b0, selected_line};
                display_digits[11:0] = station_bcd;
            end

            CALC_WAIT: begin
                display_digits[31:28] = 4'd0;
                display_digits[27:24] = 4'd0;
            end

            TICKET_COUNT: begin
                display_digits[31:28] = (fare_bcd[7:4] == 0) ? 4'hf : fare_bcd[7:4];
                display_digits[27:24] = fare_bcd[3:0];
                display_digits[3:0] = count_bcd[3:0];
            end

            PAY: begin
                display_digits[31:20] = total_bcd;
                display_digits[11:0] = paid_bcd;
            end

            VEND: begin
                display_digits[11:0] = change_bcd;
            end

            REFUND: begin
                display_digits[11:0] = refund_bcd;
            end

            default: display_digits = 32'hffffffff;
        endcase
    end

endmodule
