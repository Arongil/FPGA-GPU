`timescale 1ns / 1ps
`default_nettype none

module memory_tb;

  parameter FMA_COUNT = 2;  // number of FMAs to prepare data for in a simultaneous read
  parameter WORD_WIDTH = 16;  // number of bits per number aka width of a word
  parameter LINE_WIDTH = 96;  // width of a line, FMA_COUNT * 3 * WORD_WIDTH = 2 * 3 * 16 = 96
  parameter ADDR_LENGTH = $clog2(375);  // 96 bits in a line. 36kb/96 = 375
  parameter INSTRUCTION_WIDTH = 32;  // number of bits per instruction

  //make logics for inputs and outputs!
  logic clk_in;
  logic rst_in;
  logic [LINE_WIDTH - 1 : 0] buffer_read_in;
  logic [0 :  INSTRUCTION_WIDTH - 1] instr_in;
  logic instr_valid_in;
  logic [LINE_WIDTH - 1 : 0] abc_out;
  logic abc_valid_out;

  memory #(.FMA_COUNT(FMA_COUNT), 
           .WORD_WIDTH(WORD_WIDTH), 
           .LINE_WIDTH(LINE_WIDTH), 
           .ADDR_LENGTH(ADDR_LENGTH), 
           .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH)) uut  // uut = unit under test
          (.clk_in(clk_in),
           .rst_in(rst_in),
           .buffer_read_in(buffer_read_in),
           .instr_in(instr_in),
           .instr_valid_in(instr_valid_in),
           .abc_out(abc_out),
           .abc_valid_out(abc_valid_out));

  always begin
    #5;  //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
    clk_in = !clk_in;
  end

  //initial block...this is our test simulation
  initial begin
    $dumpfile("memory.vcd"); //file to store value change dump (vcd)
    $dumpvars(0, memory_tb); //store everything at the current level and below
    $display("Starting Sim\n"); //print nice message
    clk_in = 0; //initialize clk (super important)
    rst_in = 0; //initialize rst (super important)
    #5  //wait a little bit of time at beginning
    rst_in = 1; //reset system
    #10; //hold high for a few clock cycles
    rst_in = 0;
    #10;

    // We'll perform the following test cases:
    //   (pre_lim, can't check directly) Give an instruction that gives an address
    //   1. Give instructions that fill the line with that address
    //   2. Give an instruction that asks the memory to take the line at this address and fill the fma_read_buffer with it
    //   3. Give an instruction that asks the memory to take a line from the fma_write_buffer and fill in the line at the address with it
    //
    
    // OP codes: 
    // enum logic[3:0] {
    //     // ------------------------------------------------------------------------
    //     // | 4 bit op code | 4 bit reg | 16 bit immediate | 4 bit reg | 4 bit reg |
    //     // ------------------------------------------------------------------------
    //     OP_NOP     = 4'b0000,  // no op
    //     OP_END     = 4'b0001,  // end execution 
    //     OP_XOR     = 4'b0010,  // xor(a_reg, b_reg):
    //                            //    Places bitwise xor in a_reg
    //     OP_ADDI    = 4'b0011,  // addi(a_reg, b_reg, val):
    //                            //    Places sum of b_reg and val in a_reg
    //     OP_BGE     = 4'b0100,  // bge(a_reg, b_reg):
    //                            //    Sets compare_reg to 1 iff a_reg >= b_reg
    //     OP_JUMP    = 4'b0101,  // jump(jump_to):
    //                            //    Jumps to instruction at immediate index jump_to, if compare_reg is 1.
    //     OP_SMA     = 4'b0110,  // sma(val):
    //                            //    Set memory address to the immediate val in the data cache.
    //     OP_LOADI   = 4'b0111,  // loadi(reg_a, val):
    //                            //    Load immediate val into line at memory address, at word reg_a (not value at a_reg, but the direct bits).
    //     OP_LOADB   = 4'b1000,  // loadb(val):
    //                            //    Load FMA buffer contents into the immediate addr in the data cache.
    //     OP_WRITEB  = 4'b1001   // writeb(val):
    //                            //    Write contents of immediate addr in the data cache to FMA blocks. 
    // } isa;
    // Use first 4-bit reg for loading immediate. 4'b0 means loading 0th word in the line, 4'b1 means 1st, ... , 4'b101 means 5th 
    // We have FMA_COUNT * 3 = 6 words per line right now
    // ADDR_LENGTH needs only 9 bits for now (since we are reading entire lines), which lives in the immediate section of the instr

    /*
    NOTE: ADDRESS IS ONLY 9 BITS OUT OF THE 16 IMMEDIATE BITS
    */

    // Prelim -- give an address to the BRAM
    instr_in = 32'b0110___0000___0000_0001_0111_1000___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;

    #10;

    // TEST CASE #1
    // Give instructions that fill the line with that address
    instr_in = 32'b0111___0000___1000_1000_1000_1000___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;
    instr_in = 32'b0111___0001___1000_1000_1000_0111___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;
    instr_in = 32'b0111___0010___1000_1000_1000_0110___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;
    instr_in = 32'b0111___0011___1000_1000_1000_0101___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;
    instr_in = 32'b0111___0100___1000_1000_1000_0100___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;
    instr_in = 32'b0111___0101___1000_1000_1000_0011___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;
    //instr_in = 32'b1110___0110___1000_1000_1000_0011___0000___0000;
    //instr_valid_in = 1;
    //#10;
    instr_in = 32'b0;
    instr_valid_in = 0;

    // Give the BRAMs 2 cycles to take in the data
    #20;

    // TEST CASE #2
    // Give an instruction that asks the memory to take the line at this address and fill the fma_read_buffer with it
    instr_in = 32'b1100___0000___1000_1000_1000_1000___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #20; // 2 cycles to get stuff out of the bram, 1 cycle to put stuff into buffer

    // TEST CASE #3
    // Give an instruction that asks the memory to take a line from the fma_write_buffer and fill in the line at the address with it
    instr_in = 32'b1010___0000___1000_1000_1000_1000___0000___0000;
    buffer_read_in = 96'hA000_A000_A000_A000_A000_A000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;

    // Now take that line out and make sure it is what we put in
    #10;
    instr_in = 32'b1100___0000___1000_1000_1000_1000___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #20; // 2 cycles to get stuff out of the bram, 1 cycle to put stuff into buffer

//
//
//

    // Prelim -- give an address to the BRAM
    instr_in = 32'b0110___0000___0000_0101_0111_1000___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;

    #10;

    // TEST CASE #1
    // Give instructions that fill the line with that address
    instr_in = 32'b0111___0000___1100_1000_1000_1000___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;
    instr_in = 32'b0111___0001___1100_1000_1000_0111___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;
    instr_in = 32'b0111___0010___1100_1000_1000_0110___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;
    instr_in = 32'b0111___0011___1100_1000_1000_0101___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;
    instr_in = 32'b0111___0100___1100_1000_1000_0100___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;
    instr_in = 32'b0111___0101___1100_1000_1000_0011___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;
    instr_in = 32'b1110___0110___1100_1000_1000_0011___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;

    // Give the BRAMs 2 cycles to take in the data
    #20;

    // TEST CASE #2
    // Give an instruction that asks the memory to take the line at this address and fill the fma_read_buffer with it
    instr_in = 32'b1100___0000___1000_1000_1000_1000___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #20; // 2 cycles to get stuff out of the bram, 1 cycle to put stuff into buffer

    // TEST CASE #3
    // Give an instruction that asks the memory to take a line from the fma_write_buffer and fill in the line at the address with it
    instr_in = 32'b1010___0000___1000_1000_1000_1000___0000___0000;
    buffer_read_in = 96'hAA00_A000_A000_A000_A000_A000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #10;

    // Now take that line out and make sure it is what we put in
    #10;
    instr_in = 32'b1100___0000___1000_1000_1000_1000___0000___0000;
    instr_valid_in = 1;
    #10;
    instr_in = 32'b0;
    instr_valid_in = 0;
    #20; // 2 cycles to get stuff out of the bram, 1 cycle to put stuff into buffer

    #100;
    $finish;

  end

endmodule // fma_memory_buffer_tb

`default_nettype wire
