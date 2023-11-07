`timescale 1ns / 1ps
`default_nettype none

module fma_memory_buffer_tb;

  localparam WIDTH = 4;
  localparam FMA_COUNT = 4;

  //make logics for inputs and outputs!
  logic clk_in;
  logic rst_in;
  logic [3*WIDTH-1:0] abc_in [FMA_COUNT-1:0];
  logic [3-1:0] abc_valid_in [FMA_COUNT-1:0];
  logic [3*WIDTH-1:0] abc_out [FMA_COUNT-1:0];
  logic c_valid_out [FMA_COUNT-1:0];
  logic abc_valid_out;

  fma_memory_buffer #(.WIDTH(WIDTH), .FMA_COUNT(FMA_COUNT)) uut  // uut = unit under test
          (.clk_in(clk_in),
           .rst_in(rst_in),
           .abc_in(abc_in),
           .abc_valid_in(abc_valid_in),
           .abc_out(abc_out),
           .c_valid_out(c_valid_out),
           .abc_valid_out(abc_valid_out));

  always begin
    #5;  //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
    clk_in = !clk_in;
  end

  //initial block...this is our test simulation
  initial begin
    $dumpfile("fma_shared_memory.vcd"); //file to store value change dump (vcd)
    $dumpvars(0, fma_memory_buffer_tb); //store everything at the current level and below
    $display("Starting Sim\n"); //print nice message
    clk_in = 0; //initialize clk (super important)
    rst_in = 0; //initialize rst (super important)
    #10  //wait a little bit of time at beginning
    rst_in = 1; //reset system
    #10; //hold high for a few clock cycles
    rst_in = 0;
    #10;

    // We'll perform the following test cases:
    //   1. Only give valid input to one FMA: make sure abc_valid_out stays low
    //   2. Give valid input to all FMAs, but no c values
    //   3. Give valid input to all FMAs, including c value for one FMA
    //   4. Give valid input to all FMAs, including c value for all FMAs
    //
    // Implicitly, we are testing whether the memory buffer can take in new
    // data after outputting its old data.
    
    // TEST CASE #1
    abc_valid_in[0] = 3'b110; // first  FMA gets a valid input (read everything except c)
    abc_valid_in[1] = 3'b000; // second FMA (read nothing)
    abc_valid_in[2] = 3'b000; // third  FMA (read nothing)
    abc_valid_in[3] = 3'b000; // fourth FMA (read nothing)
    abc_in[0] = 12'b0001_0010_0100; // 1 2 4 (should only read "a" and "b" values)
    abc_in[1] = 12'b0001_0010_0100; // 1 2 4 (make sure it doesn't read these in!)
    abc_in[2] = 12'b0001_0010_0100; // 1 2 4 (make sure it doesn't read these in!)
    abc_in[3] = 12'b0001_0010_0100; // 1 2 4 (make sure it doesn't read these in!)

    $display("%12d", abc_out[0]);

    #10;

    $finish;

  end

endmodule // fma_memory_buffer_tb

`default_nettype wire
