`timescale 1ns / 1ps

// Symmetric all-pairs shortest-distance ROM for 102 unique stations.
module distance_lookup #(
    parameter ROM_FILE = "distance_rom.mem"
) (
    input  wire        clk,
    input  wire        query_valid,
    input  wire [6:0]  start_station,
    input  wire [6:0]  end_station,
    output reg  [16:0] distance_m,
    output reg         result_valid
);

    reg [16:0] distance_rom [0:5150];
    wire [6:0] high_index;
    wire [6:0] low_index;
    wire [12:0] triangle_base;
    wire [12:0] rom_address;
    reg  [12:0] address_reg;
    reg         same_station_reg;
    reg         pending;

    assign high_index = (start_station >= end_station) ? start_station : end_station;
    assign low_index  = (start_station >= end_station) ? end_station : start_station;
    assign rom_address = triangle_base + low_index;

    triangle_base_rom u_triangle_base (
        .index(high_index),
        .base(triangle_base)
    );

    initial begin
        $readmemh(ROM_FILE, distance_rom);
    end

    // The extra address register intentionally has no asynchronous reset.
    // This isolates the BRAM address pins from the asynchronously reset main
    // state machine and avoids RAMB18/RAMB36 async-control DRC warnings.
    always @(posedge clk) begin
        result_valid <= pending;
        pending <= query_valid;
        if (query_valid) begin
            address_reg <= rom_address;
            same_station_reg <= (start_station == end_station);
        end
        if (pending) begin
            if (same_station_reg)
                distance_m <= 17'd0;
            else
                distance_m <= distance_rom[address_reg];
        end
    end

endmodule
