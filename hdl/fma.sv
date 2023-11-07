`timescale 1ns / 1ps
`default_nettype none

module fma #(
    parameter WIDTH=16,  // number of bits per fixed-point number
    parameter FIXED_POINT=10  // number of bits after the decimal
) (
    input wire clk_in,
    input wire rst_in,
    input wire [WIDTH-1:0] a,
    input wire [WIDTH-1:0] b,
    input wire [WIDTH-1:0] c,
    input wire a_valid_in,    // only write external a value if valid_in is high
    input wire b_valid_in,    // only write external b value if valid_in is high
    input wire c_valid_in,    // only write external c value if valid_in is high
    input wire compute,  // high when the FMA should compute on the next cycle
    output logic [WIDTH-1:0] out
);

    logic [WIDTH-1:0] a_internal, b_internal;
    logic [2*WIDTH-1:0] multiplication_full_precision;

    always_comb begin
        multiplication_full_precision = (
            (a_valid_in ? a : a_internal) * 
            (b_valid_in ? b : b_internal)
        );
    end

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            a_internal <= 0;
            b_internal <= 0;
            out <= 0;
        end else begin
            if (compute) begin
                // To multiply two fixed-point numbers, treat them as regular
                // integers and then shift to the right by the number of
                // decimal places. Let a and b be fixed-point. Let a' and b'
                // be a and b considered as plain integers. Then:
                //
                //   a * b = (a*2^f) * (b*2^f) * 2^(-2f)    [all integers now]
                //         = a' * b' * 2^(-2f)              [all integers now]
                //         = a' * b' * 2^(-f)      [considered as fixed-point]
                //
                //   where f is the number of bits after the decimal.
                //
                // out <= (a_internal * b_internal) >> FIXED_POINT + c
                //
                // The below is only more complicated to stay clock-aligned. 
                out <= (multiplication_full_precision >> FIXED_POINT) + (c_valid_in ? c : out);
            end

            a_internal <= a_valid_in ? a : a_internal;
            b_internal <= b_valid_in ? b : b_internal;
        end
    end

endmodule

`default_nettype wire
