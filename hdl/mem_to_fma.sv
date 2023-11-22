// `timescale 1ns / 1ps
// `default_nettype none

// module mem_to_fma #(
//     parameter FMA_COUNT = 2,  // number of FMAs to prepare data for in a simultaneous read
//     parameter WORD_WIDTH = 16,  // number of bits per number aka width of a word
//     parameter WIDTH=16,  // number of bits per fixed-point number
//     parameter LINE_WIDTH = 96,  // width of a line, FMA_COUNT * 3 * WORD_WIDTH = 2 * 3 * 16 = 96
//     parameter ADDR_LENGTH = $clog2(375),  // 96 bits in a line. 36kb/96 = 375
//     parameter INSTRUCTION_WIDTH = 32      // number of bits per instruction
// ) (
//     input wire clk_100mhz,
//     input wire rst_in,
//     input wire [0 : INSTRUCTION_WIDTH - 1] instr_in,
//     input wire instr_valid_in,
//     output logic [WIDTH-1:0] out
// );


//     // input wire [LINE_WIDTH - 1 : 0] buffer_read_in,
//     // output logic idle_out, // 1 when idle, 0 when busy
//     // output logic [LINE_WIDTH - 1 : 0] abc_out,  // for each FMA i, abc_in[i] is laid out as "a b c" 
//     // output logic abc_valid_out,

//     // input wire clk_in,
//     // input wire rst_in,
//     // input wire [WIDTH-1:0] a,
//     // input wire [WIDTH-1:0] b,
//     // input wire [WIDTH-1:0] c,
//     // input wire a_valid_in,    // only write external a value if valid_in is high
//     // input wire b_valid_in,    // only write external b value if valid_in is high
//     // input wire c_valid_in,    // only write external c value if valid_in is high
//     // input wire compute,  // high when the FMA should compute on the next cycle