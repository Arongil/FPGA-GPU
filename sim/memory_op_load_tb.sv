`timescale 1ns / 1ps
`default_nettype none

module memory_op_load_tb;

/*    parameter FMA_COUNT = 2,  // number of FMAs to prepare data for in a simultaneous read
    parameter WORD_WIDTH = 16,  // number of bits per number aka width of a word
    parameter LINE_WIDTH = 96,  // width of a line, FMA_COUNT * 3 * WORD_WIDTH = 2 * 3 * 16 = 96
    parameter ADDR_LENGTH = $clog2(36000 / 96),  // 96 bits in a line. 36kb/96 = 375
    parameter INSTRUCTION_WIDTH = 32      // number of bits per instruction
) (
    // Use first 4-bit reg for loading immediate. 4'b0 means loading 0th word in the line, 4'b1 means 1st, ... , 4'b101 means 5th 
    // We have FMA_COUNT * 3 = 6 words per line right now
    // ADDR_LENGTH needs only 9 bits for now (since we are reading entire lines), which lives in the immediate section of the instr
    input wire clk_in,
    input wire rst_in,
    input wire [15:0] controller_reg_a,
    input wire [15:0] controller_reg_b,
    input wire [15:0] controller_reg_c,
    input wire [LINE_WIDTH - 1 : 0] write_buffer_read_in,
    input wire write_buffer_valid_in,
    input wire [0 : INSTRUCTION_WIDTH - 1] instr_in,
    input wire instr_valid_in,
    output logic [LINE_WIDTH - 1 : 0] abc_out,  // for each FMA i, abc_in[i] is laid out as "a b c" 
    output logic use_new_c_out,
    output logic fma_output_can_be_valid_out,
    output logic abc_valid_out
);
*/

  parameter FMA_COUNT = 2;  // number of FMAs to prepare data for in a simultaneous read
  parameter WORD_WIDTH = 16;  // number of bits per number aka width of a word
  parameter LINE_WIDTH = 96;  // width of a line, FMA_COUNT * 3 * WORD_WIDTH = 2 * 3 * 16 = 96
  parameter ADDR_LENGTH = $clog2(36000 / 96);  // 96 bits in a line. 36kb/96 = 375
  parameter INSTRUCTION_WIDTH = 32;  // number of bits per instruction

  //make logics for inputs and outputs!
  logic clk_in;
  logic rst_in;
  logic [15:0] controller_reg_a;
  logic [15:0] controller_reg_b;
  logic [15:0] controller_reg_c;
  logic [LINE_WIDTH - 1 : 0] write_buffer_read_in;
  logic write_buffer_valid_in;
  logic [INSTRUCTION_WIDTH - 1 : 0] instr_in;
  logic instr_valid_in;
  logic [LINE_WIDTH - 1 : 0] abc_out;
  logic use_new_c_out;
  logic fma_output_can_be_valid_out;
  logic abc_valid_out;

  logic [31:0] addr1;

  memory #(.FMA_COUNT(FMA_COUNT), 
           .WORD_WIDTH(WORD_WIDTH), 
           .LINE_WIDTH(LINE_WIDTH), 
           .ADDR_LENGTH(ADDR_LENGTH), 
           .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH)) uut  // uut = unit under test
          (.clk_in(clk_in),
           .rst_in(rst_in),
           .controller_reg_a(controller_reg_a),
           .controller_reg_b(controller_reg_b),
           .controller_reg_c(controller_reg_c),
           .write_buffer_read_in(write_buffer_read_in),
           .write_buffer_valid_in(write_buffer_valid_in),
           .instr_in(instr_in),
           .instr_valid_in(instr_valid_in),
           .abc_out(abc_out),
           .use_new_c_out(use_new_c_out),
           .fma_output_can_be_valid_out(fma_output_can_be_valid_out),
           .abc_valid_out(abc_valid_out));

  always begin
    #5;  //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
    clk_in = !clk_in;
  end

  //initial block...this is our test simulation
  initial begin
    $dumpfile("memory_op_load_tb.vcd"); //file to store value change dump (vcd)
    $dumpvars(0, memory_op_load_tb); //store everything at the current level and below
    $display("Starting Sim\n"); //print nice message
    clk_in = 0; //initialize clk (super important)
    rst_in = 0; //initialize rst (super important)
    #5  //wait a little bit of time at beginning
    rst_in = 1; //reset system
    #10; //hold high for a few clock cycles
    rst_in = 0;
    #10;

    controller_reg_a = 16'b1;
    controller_reg_b = 16'b10;
    controller_reg_c = 16'b11;

    instr_valid_in = 1;
    instr_in = 32'b0111___0000___0000_0000_0000_1000___0000___0000; // set BRAM address to line 8, not necessary? 
    #10;

    instr_in = 32'b1101___0000___0000_0000_0000_0001___0000___0000; // a, reg 1, diff = 1, 
    #10;
    // where FMA_i's value is set to reg_val + i * diff.
    // bram_temp_in should be 1 + 0 * 1, 0, 0, 1 + 1 * 1, 0, 0
    // 16'b1, 16'b0, 16'b0, 16'b10, 16'b0, 16'b0

    instr_valid_in = 0;
    #100;
    $finish;

  end

endmodule // fma_memory_buffer_tb

`default_nettype wire

/*
Discarded/redundent tests

    // Prelim -- give an address to the BRAM
    instr_in = addr2;
    instr_valid_in = 1;
    #10;

    // TEST CASE #1
    // Give instructions that fill the line with that address
    instr_in = 32'b0111___0000___1100_1000_1000_1000___0000___0000;
    #10;
    instr_in = 32'b0111___0001___1100_1000_1000_0111___0000___0000;
    #10;
    instr_in = 32'b0111___0010___1100_1000_1000_0110___0000___0000;
    #10;
    instr_in = 32'b0111___0011___1100_1000_1000_0101___0000___0000;
    #10;
    instr_in = 32'b0111___0100___1100_1000_1000_0100___0000___0000;
    #10;
    instr_in = 32'b0111___0101___1100_1000_1000_0011___0000___0000;
    #10;
    instr_in = 32'b1110___0110___1100_1000_1000_0011___0000___0000;
    instr_valid_in = 1;
    #10;
    
    // Give the BRAMs 2 cycles to take in the data
    instr_in = 32'b0000___1000___0000_0000_0000_0000___0000___0000;
    #10;
    // instr_in = 32'b0000___1000___0000_0000_0000_0000___0000___0000;
    // #10;

    // TEST CASE #2
    // Give an instruction that asks the memory to take the line at this address and fill the fma_read_buffer with it
    instr_in = 32'b1100___0000___1000_1000_1000_1000___0000___0000;
    instr_valid_in = 1;
    #10;
    // 2 cycles to get stuff out of the bram, 1 cycle to put stuff into buffer
    instr_in = 32'b0000___1000___0000_0000_0000_0000___0000___0000;
    #10;
    // instr_in = 32'b0000___1000___0000_0000_0000_0000___0000___0000;
    // #10;

    // TEST CASE #3
    // Give an instruction that asks the memory to take a line from the fma_write_buffer and fill in the line at the address with it
    instr_in = 32'b1010___0000___1000_1000_1000_1000___0000___0000;
    buffer_read_in = 96'hAA00_A000_A000_A000_A000_A000;
    instr_valid_in = 1;
    #10;

    // Now take that line out and make sure it is what we put in
    instr_in = 32'b0000___1000___0000_0000_0000_0000___0000___0000;
    #10;
    // instr_in = 32'b0000___1000___0000_0000_0000_0000___0000___0000;
    // #10; // 2 NOPs
    instr_in = 32'b1100___0000___1000_1000_1000_1000___0000___0000;
    instr_valid_in = 1;
    #10;
    // 2 cycles to get stuff out of the bram, 1 cycle to put stuff into buffer
    instr_in = 32'b0000___1000___0000_0000_0000_0000___0000___0000;
    #10;
    // instr_in = 32'b0000___1000___0000_0000_0000_0000___0000___0000;
    // #10;

  //
  //
  //
  //
*/
