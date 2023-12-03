`timescale 1ns / 1ps
`default_nettype none

module fma #(
    parameter WIDTH=16,  // number of bits per fixed-point number
    parameter FIXED_POINT=10  // number of bits after the decimal
) (
    input wire clk_in,
    input wire rst_in,
    input wire [3*WIDTH-1:0] abc, // abc is laid out as "a b c" in bits
    input wire valid_in,   // high when the FMA should read new values into a, b
    input wire c_valid_in, // high when the FMA should read new value into c
    input wire output_can_be_valid_in, // low when calculated values should stay internal only
    output logic [WIDTH-1:0] out,
    output logic valid_out
);

    logic [WIDTH-1:0] a_internal, b_internal;
    logic [2*WIDTH-1:0] multiplication_full_precision;

    logic [WIDTH-1:0] a, b;
    assign a = abc[3*WIDTH-1:2*WIDTH];
    assign b = abc[2*WIDTH-1:1*WIDTH];

     // set to 1'b1 for integer arithmetic, 1'b0 for fixed point arithmetic
    localparam INTEGER_ARITHMETIC = 1'b1;

    always_comb begin
        multiplication_full_precision = (
            (valid_in ? a : a_internal) *
            (valid_in ? b : b_internal)
        );
    end

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            a_internal <= 0;
            b_internal <= 0;
            out <= 0;
        end else begin
            if (valid_in) begin
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
                if (INTEGER_ARITHMETIC == 1'b1) begin
                    out <= multiplication_full_precision[WIDTH-1:0] + (c_valid_in ? abc[WIDTH-1:0] : out);
                end else begin
                    out <= (multiplication_full_precision >> FIXED_POINT) + (c_valid_in ? abc[WIDTH-1:0] : out);
                end
            end

            a_internal <= valid_in ? abc[3*WIDTH-1:2*WIDTH] : a_internal;
            b_internal <= valid_in ? abc[2*WIDTH-1:1*WIDTH] : b_internal;
            valid_out <= valid_in && output_can_be_valid_in;
        end
    end

endmodule

`default_nettype wire
