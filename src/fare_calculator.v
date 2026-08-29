`timescale 1ns / 1ps

// Fare brackets from the supplied distance-fare chart.
module fare_calculator (
    input  wire [16:0] distance_m,
    output reg  [4:0]  fare_yuan
);
    reg [16:0] extra_distance;

    always @(*) begin
        extra_distance = 17'd0;
        if (distance_m <= 17'd4000)
            fare_yuan = 5'd2;
        else if (distance_m <= 17'd9000)
            fare_yuan = 5'd3;
        else if (distance_m <= 17'd14000)
            fare_yuan = 5'd4;
        else if (distance_m <= 17'd21000)
            fare_yuan = 5'd5;
        else if (distance_m <= 17'd28000)
            fare_yuan = 5'd6;
        else if (distance_m <= 17'd37000)
            fare_yuan = 5'd7;
        else if (distance_m <= 17'd48000)
            fare_yuan = 5'd8;
        else if (distance_m <= 17'd61000)
            fare_yuan = 5'd9;
        else begin
            extra_distance = distance_m - 17'd61000;
            fare_yuan = 5'd9 + ((extra_distance + 17'd14999) / 17'd15000);
        end
    end
endmodule
