`timescale 1ns / 1ps

// Produces exactly two visible flashes for the requested LED mask.
module blink_controller #(
    parameter integer HALF_PERIOD_CYCLES = 12_500_000
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [3:0] mask,
    output reg  [3:0] leds,
    output reg        busy,
    output reg        done
);

    reg [31:0] half_count;
    reg [1:0]  half_index;
    reg [3:0]  saved_mask;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            leds       <= 4'b0000;
            busy       <= 1'b0;
            done       <= 1'b0;
            half_count <= 32'd0;
            half_index <= 2'd0;
            saved_mask <= 4'b0000;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                saved_mask <= mask;
                leds       <= mask;
                busy       <= 1'b1;
                half_count <= 32'd0;
                half_index <= 2'd0;
            end else if (busy) begin
                if (half_count >= HALF_PERIOD_CYCLES - 1) begin
                    half_count <= 32'd0;
                    if (half_index == 2'd3) begin
                        leds <= 4'b0000;
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        half_index <= half_index + 1'b1;
                        if (leds == 4'b0000)
                            leds <= saved_mask;
                        else
                            leds <= 4'b0000;
                    end
                end else begin
                    half_count <= half_count + 1'b1;
                end
            end
        end
    end

endmodule
