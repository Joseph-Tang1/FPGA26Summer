`timescale 1ns / 1ps

// Converts a 10-bit unsigned value (0..1023) to three packed BCD digits.
module binary_to_bcd (
    input  wire [9:0] binary,
    output reg  [11:0] bcd
);
    integer index;
    reg [21:0] shift;

    always @(*) begin
        shift = 22'd0;
        shift[9:0] = binary;
        for (index = 0; index < 10; index = index + 1) begin
            if (shift[13:10] >= 5)
                shift[13:10] = shift[13:10] + 3;
            if (shift[17:14] >= 5)
                shift[17:14] = shift[17:14] + 3;
            if (shift[21:18] >= 5)
                shift[21:18] = shift[21:18] + 3;
            shift = shift << 1;
        end
        bcd = shift[21:10];
    end
endmodule
