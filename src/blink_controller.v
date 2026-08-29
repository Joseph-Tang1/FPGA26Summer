`timescale 1ns / 1ps

// Produces a requested number of fixed-period flashes on four generic channels.
module blink_controller #(
    parameter integer HALF_PERIOD_CYCLES = 12_500_000
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [3:0] mask,
    input  wire [3:0] flash_count,
    output reg  [3:0] active_mask,
    output reg        busy,
    output reg        done
);

    reg [31:0] half_count;
    reg [4:0]  half_remaining;
    reg [3:0]  saved_mask;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_mask <= 4'b0000;
            busy       <= 1'b0;
            done       <= 1'b0;
            half_count <= 32'd0;
            half_remaining <= 5'd0;
            saved_mask <= 4'b0000;
        end else begin
            done <= 1'b0;
            if (start && !busy && (flash_count != 0)) begin
                saved_mask <= mask;
                active_mask <= mask;
                busy       <= 1'b1;
                half_count <= 32'd0;
                half_remaining <= {flash_count, 1'b0};
            end else if (busy) begin
                if (half_count >= HALF_PERIOD_CYCLES - 1) begin
                    half_count <= 32'd0;
                    if (half_remaining <= 5'd1) begin
                        active_mask <= 4'b0000;
                        busy <= 1'b0;
                        done <= 1'b1;
                        half_remaining <= 5'd0;
                    end else begin
                        half_remaining <= half_remaining - 1'b1;
                        if (active_mask == 4'b0000)
                            active_mask <= saved_mask;
                        else
                            active_mask <= 4'b0000;
                    end
                end else begin
                    half_count <= half_count + 1'b1;
                end
            end
        end
    end

endmodule
