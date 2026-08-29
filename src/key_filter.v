`timescale 1ns / 1ps

// Active-low key filter. One press produces one clock-wide pulse.
module key_filter #(
    parameter integer DEBOUNCE_CYCLES = 1_000_000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire key_n,
    output reg  press_pulse
);

    localparam [1:0] RELEASED       = 2'd0;
    localparam [1:0] PRESS_VERIFY   = 2'd1;
    localparam [1:0] PRESSED        = 2'd2;
    localparam [1:0] RELEASE_VERIFY = 2'd3;

    reg [1:0]  state;
    reg [31:0] debounce_count;
    (* ASYNC_REG = "TRUE" *) reg [1:0] key_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            key_sync <= 2'b11;
        else
            key_sync <= {key_sync[0], key_n};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= RELEASED;
            debounce_count <= 32'd0;
            press_pulse    <= 1'b0;
        end else begin
            press_pulse <= 1'b0;
            case (state)
                RELEASED: begin
                    debounce_count <= 32'd0;
                    if (!key_sync[1])
                        state <= PRESS_VERIFY;
                end

                PRESS_VERIFY: begin
                    if (key_sync[1]) begin
                        state          <= RELEASED;
                        debounce_count <= 32'd0;
                    end else if (debounce_count >= DEBOUNCE_CYCLES - 1) begin
                        state          <= PRESSED;
                        debounce_count <= 32'd0;
                        press_pulse    <= 1'b1;
                    end else begin
                        debounce_count <= debounce_count + 1'b1;
                    end
                end

                PRESSED: begin
                    debounce_count <= 32'd0;
                    if (key_sync[1])
                        state <= RELEASE_VERIFY;
                end

                RELEASE_VERIFY: begin
                    if (!key_sync[1]) begin
                        state          <= PRESSED;
                        debounce_count <= 32'd0;
                    end else if (debounce_count >= DEBOUNCE_CYCLES - 1) begin
                        state          <= RELEASED;
                        debounce_count <= 32'd0;
                    end else begin
                        debounce_count <= debounce_count + 1'b1;
                    end
                end

                default: begin
                    state          <= RELEASED;
                    debounce_count <= 32'd0;
                end
            endcase
        end
    end

endmodule
