`timescale 1ns / 1ps

// Eight-digit, active-low, common-anode scanner. 4'hf means blank.
module seven_seg_display #(
    parameter integer SCAN_DIV = 50_000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] digits,
    output reg  [7:0]  seg,
    output reg  [7:0]  sel
);

    reg [31:0] scan_count;
    reg [2:0]  scan_index;
    reg [3:0]  current_digit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_count <= 32'd0;
            scan_index <= 3'd0;
        end else if (scan_count >= SCAN_DIV - 1) begin
            scan_count <= 32'd0;
            scan_index <= scan_index + 1'b1;
        end else begin
            scan_count <= scan_count + 1'b1;
        end
    end

    always @(*) begin
        case (scan_index)
            3'd0: begin sel = 8'b11111110; current_digit = digits[3:0];   end
            3'd1: begin sel = 8'b11111101; current_digit = digits[7:4];   end
            3'd2: begin sel = 8'b11111011; current_digit = digits[11:8];  end
            3'd3: begin sel = 8'b11110111; current_digit = digits[15:12]; end
            3'd4: begin sel = 8'b11101111; current_digit = digits[19:16]; end
            3'd5: begin sel = 8'b11011111; current_digit = digits[23:20]; end
            3'd6: begin sel = 8'b10111111; current_digit = digits[27:24]; end
            3'd7: begin sel = 8'b01111111; current_digit = digits[31:28]; end
            default: begin sel = 8'b11111111; current_digit = 4'hf; end
        endcase

        case (current_digit)
            4'd0: seg = 8'b11000000;
            4'd1: seg = 8'b11111001;
            4'd2: seg = 8'b10100100;
            4'd3: seg = 8'b10110000;
            4'd4: seg = 8'b10011001;
            4'd5: seg = 8'b10010010;
            4'd6: seg = 8'b10000010;
            4'd7: seg = 8'b11111000;
            4'd8: seg = 8'b10000000;
            4'd9: seg = 8'b10010000;
            default: seg = 8'b11111111;
        endcase
    end

endmodule
