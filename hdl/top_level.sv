// `timescale 1ns / 1ps
// `default_nettype none

// module top_level #(
//     // parameter PROGRAM_FILE="program.mem",
//     // parameter PRIVATE_REG_WIDTH=16,  // number of bits per private register
//     // parameter PRIVATE_REG_COUNT=16,  // number of registers in the controller
//     // parameter INSTRUCTION_WIDTH=32,  // number of bits per instruction
//     // parameter INSTRUCTION_COUNT=512, // number of instructions in the program
//     // parameter DATA_CACHE_WIDTH=16,   // number of bits per fixed-point number
//     // parameter DATA_CACHE_DEPTH=4096  // number of addresses in the data cache
//     parameter FMA_COUNT = 2,  // number of FMAs to prepare data for in a simultaneous read
//     parameter WORD_WIDTH = 16,  // number of bits per number aka width of a word
//     parameter LINE_WIDTH = 96,  // width of a line, FMA_COUNT * 3 * WORD_WIDTH = 2 * 3 * 16 = 96
//     parameter ADDR_LENGTH = $clog2(375),  // 96 bits in a line. 36kb/96 = 375
//     parameter INSTRUCTION_WIDTH = 32      // number of bits per instruction
// ) (
//     input wire clk_100mhz,
//     input wire 
//     input wire [15:0] sw, //all 16 input slide switches
//     input wire [3:0] btn, //all four momentary button switches
//     output logic [15:0] led, //16 green output LEDs (located right above switches)
//     output logic [2:0] rgb0, //rgb led
//     output logic [2:0] rgb1, //rgb led
//     output logic [2:0] hdmi_tx_p, //hdmi output signals (blue, green, red)
//     output logic [2:0] hdmi_tx_n, //hdmi output signals (negatives)
//     output logic hdmi_clk_p, hdmi_clk_n, //differential hdmi clock
//     output logic [6:0] ss0_c,
//     output logic [6:0] ss1_c,
//     output logic [3:0] ss0_an,
//     output logic [3:0] ss1_an,
//     input wire [7:0] pmoda,
//     input wire [2:0] pmodb,
//     output logic pmodbclk,
//     output logic pmodblock
//     );

//     xilinx_true_dual_port_read_first_2_clock_ram #(
//         .RAM_WIDTH(LINE_WIDTH),                       // Specify RAM data width
//         .RAM_DEPTH(WORD_WIDTH),                     // Specify RAM depth (number of entries)
//         .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
//         .INIT_FILE("")                        // Specify name/location of RAM initialization file if using one (leave blank if not)
//     ) memory_BRAM (
//         .addra(addr),   // Port A address bus, width determined from RAM_DEPTH
//         .addrb(),   // Port B address bus, width determined from RAM_DEPTH
//         .dina(bram_in),     // Port A RAM input data, width determined from RAM_WIDTH
//         .dinb(),     // Port B RAM input data, width determined from RAM_WIDTH
//         .clka(clk_in),     // Port A clock
//         .clkb(),     // Port B clock
//         .wea(bram_read),       // Port A write enable
//         .web(),       // Port B write enable
//         .ena(1),       // Port A RAM Enable, for additional power savings, disable port when not in use
//         .enb(),       // Port B RAM Enable, for additional power savings, disable port when not in use
//         .rsta(0),     // Port A output reset (does not affect memory contents)
//         .rstb(),     // Port B output reset (does not affect memory contents)
//         .regcea(bram_write), // Port A output register enable
//         .regceb(), // Port B output register enable
//         .douta(bram_out),   // Port A RAM output data, width determined from RAM_WIDTH
//         .doutb()    // Port B RAM output data, width determined from RAM_WIDTH
//     );