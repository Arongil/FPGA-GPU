`timescale 1ns / 1ps
`default_nettype none

module fma_tb;

  localparam WIDTH = 16;
  localparam FIXED_POINT = 10;
  //make logics for inputs and outputs!
  logic clk_in;
  logic rst_in;
  logic [WIDTH-1:0] a, b, c;
  logic a_valid_in, b_valid_in, c_valid_in;
  logic compute;
  logic [WIDTH-1:0] out; 

  fma #(.WIDTH(WIDTH), .FIXED_POINT(FIXED_POINT)) uut  // uut = unit under test
          (.clk_in(clk_in),
           .rst_in(rst_in),
           .a(a),
           .b(b),
           .c(c),
           .a_valid_in(a_valid_in),
           .b_valid_in(b_valid_in),
           .c_valid_in(c_valid_in),
           .compute(compute),
           .out(out));

  always begin
    #5;  //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
    clk_in = !clk_in;
  end

  //initial block...this is our test simulation
  initial begin
    $dumpfile("fma.vcd"); //file to store value change dump (vcd)
    $dumpvars(0,fma_tb); //store everything at the current level and below
    $display("Starting Sim\n"); //print nice message
    clk_in = 0; //initialize clk (super important)
    rst_in = 0; //initialize rst (super important)
    #10  //wait a little bit of time at beginning
    rst_in = 1; //reset system
    #10; //hold high for a few clock cycles
    rst_in=0;
    #10;
    a=16'b000010_0000000000; // 2
    b=16'b000001_1000000000; // 1.5
    a_valid_in = 1;
    b_valid_in = 1;
    c_valid_in = 0;
    compute = 1;
    #10; // 1 cycle later
    a_valid_in = 0;
    b_valid_in = 0;
    compute = 0;
    $display("%16d * %16d = %16d", a, b, out);  // should be 3

    #10; // let's test another, more complicated multiplication
    a=16'b000101_0010000000; // 5.125
    b=16'b000110_0000000000; // 6
    a_valid_in = 1;
    b_valid_in = 1;
    c_valid_in = 0;
    compute = 1;
    #10; // 1 cycle later
    a_valid_in = 0;
    b_valid_in = 0;
    compute = 0;
    $display("%16d * %16d = %16d", a, b, out);  // should be 30.75 + 3 (the previous answer)

    #10; // now if we reset the c value we get just the multiplication from above
    a=16'b000101_0010000000; // 5.125
    b=16'b000110_0000000000; // 6
    c=16'b000000_0000000000; // 0
    a_valid_in = 1;
    b_valid_in = 1;
    c_valid_in = 1;
    compute = 1;
    #10; // 1 cycle later
    a_valid_in = 0;
    b_valid_in = 0;
    c_valid_in = 0;
    compute = 0;
    $display("%16d * %16d = %16d", a, b, out);  // should be 30.75 (the previous answer)

    $display("\nThe first two multiplications are a \"dot product\"\nwhere the answer is saved and added to the next result.\nThe third line resets the c value to 0.\n");

    $finish;

  end

endmodule // fma_tb

`default_nettype wire
