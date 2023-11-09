`timescale 1ns / 1ps
`default_nettype none

module fma_memory_buffer_tb;

  localparam WIDTH = 4;
  localparam FMA_COUNT = 4;

  //make logics for inputs and outputs!
  logic clk_in;
  logic rst_in;
  logic [FMA_COUNT * 3*WIDTH-1 : 0] abc_in;
  logic [FMA_COUNT * 3 - 1 : 0] abc_valid_in;
  logic [FMA_COUNT * 3*WIDTH-1 : 0] abc_out;
  logic [FMA_COUNT - 1 : 0] c_valid_out;
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
    //   5. Give valid input to some FMAs, but not to others.
    //
    // Implicitly, we are testing whether the memory buffer can take in new
    // data after outputting its old data.
    
    // TEST CASE #1
    // First FMA gets a valid input (read everything except c), all other FMAs read nothing
    //                 cba cba cba cba
    abc_valid_in = 12'b000_000_000_011;
    // All FMAs are able to read in a = 1, b = 2, c = 4.
    abc_in = 48'b0001_0010_0100___0001_0010_0100___0001_0010_0100___0001_0010_0100;

    #10;

    // TEST CASE #2
    // Let's give valid input to each FMA one by one, until the buffer outputs
    abc_valid_in = 12'b000_000_011_000;
    abc_in = 48'b0000_0111_1000___0000_0111_1000___0000_0111_1000___0000_0111_1000;
    #10;
    abc_valid_in = 12'b000_011_000_000;
    abc_in = 48'b0000_0111_1000___0000_0111_1000___0000_0111_1000___0000_0111_1000;
    #10;
    abc_valid_in = 12'b011_000_000_000;
    abc_in = 48'b0000_0111_1000___0000_0111_1000___0000_0111_1000___0000_0111_1000;
    #10;

    // Give the memory buffer one cycle to output its stored data.
    #10;
    // Give the memory buffer one cycle to reset its internals.
    #10;

    // TEST CASE #3
    abc_valid_in = 12'b000_000_000_011;
    abc_in = 48'b0000_0111_1000___0000_0111_1000___0000_0111_1000___0000_0111_1000;
    #10;
    abc_valid_in = 12'b000_000_011_000;
    abc_in = 48'b0000_0111_1000___0000_0111_1000___0000_0111_1000___0000_0111_1000;
    #10;
    abc_valid_in = 12'b000_111_000_000; // set the c value to read in on this FMA!
    abc_in = 48'b0000_0111_1000___1001_0111_1000___0000_0111_1000___0000_0111_1000;
    #10;
    abc_valid_in = 12'b011_000_000_000;
    abc_in = 48'b0000_0111_1000___0000_0111_1000___0000_0111_1000___0000_0111_1000;
    #10;

    // Give the memory buffer one cycle to output its stored data.
    #10;
    // Give the memory buffer one cycle to reset its internals.
    #10;

    // TEST CASE #4
    abc_valid_in = 12'b000_000_000_111; // set the c value to read in on this FMA!
    abc_in = 48'b0000_0111_1000___0000_0111_1000___0000_0111_1000___0001_0111_1000;
    #10;
    abc_valid_in = 12'b000_000_111_000; // set the c value to read in on this FMA!
    abc_in = 48'b0000_0111_1000___0000_0111_1000___0001_0111_1000___0000_0111_1000;
    #10;
    abc_valid_in = 12'b000_111_000_000; // set the c value to read in on this FMA!
    abc_in = 48'b0000_0111_1000___0001_0111_1000___0000_0111_1000___0000_0111_1000;
    #10;
    abc_valid_in = 12'b111_000_000_000; // set the c value to read in on this FMA!
    abc_in = 48'b0001_0111_1000___0000_0111_1000___0000_0111_1000___0000_0111_1000;
    #10;

    // Give the memory buffer one cycle to output its stored data.
    #10;
    // Give the memory buffer one cycle to reset its internals.
    #10;

    // TEST CASE #5
    abc_valid_in = 12'b000_000_000_111;
    abc_in = 48'b0000_0111_1000___0000_0111_1000___0000_0111_1000___0001_0111_1000;
    #10;
    abc_valid_in = 12'b000_000_010_000; // give incomplete input to the second FMA
    abc_in = 48'b0000_0111_1000___0000_0111_1000___0001_0111_1000___0000_0111_1000;
    #10;
    abc_valid_in = 12'b000_111_000_000;
    abc_in = 48'b0000_0111_1000___0001_0111_1000___0000_0111_1000___0000_0111_1000;
    #10;
    abc_valid_in = 12'b111_000_000_000;
    abc_in = 48'b0001_0111_1000___0000_0111_1000___0000_0111_1000___0000_0111_1000;
    #10;

    // Give the memory buffer one cycle to output its stored data.
    #10;
    // Give the memory buffer one cycle to reset its internals.
    #10;

    $finish;

  end

endmodule // fma_memory_buffer_tb

`default_nettype wire
