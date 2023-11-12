`timescale 1ns / 1ps
`default_nettype none

module controller_tb;

    localparam PRIVATE_REG_WIDTH=16;
    localparam PRIVATE_REG_COUNT=16;
    localparam INSTRUCTION_WIDTH=32;
    localparam INSTRUCTION_COUNT=8;    // UPDATE TO MATCH PROGRAM_FILE
    localparam DATA_CACHE_WIDTH=16;
    localparam DATA_CACHE_DEPTH=4096;

    // make logics for inputs and outputs!
    logic clk_in;
    logic rst_in;

    controller #(
        .PROGRAM_FILE("all-no-op.mem"),
        .PRIVATE_REG_WIDTH(PRIVATE_REG_WIDTH),
        .PRIVATE_REG_COUNT(PRIVATE_REG_COUNT),
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH),
        .INSTRUCTION_COUNT(INSTRUCTION_COUNT),
        .DATA_CACHE_WIDTH(DATA_CACHE_WIDTH),
        .DATA_CACHE_DEPTH(DATA_CACHE_DEPTH)
    ) uut ( // uut = unit under test
        .clk_in(clk_in),
        .rst_in(rst_in)
    );

    always begin
        #5;  //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
        clk_in = !clk_in;
    end

    //initial block...this is our test simulation
    initial begin
        $dumpfile("controller.vcd"); //file to store value change dump (vcd)
        $dumpvars(0, controller_tb); //store everything at the current level and below
        $display("Starting Sim\n"); //print nice message
        clk_in = 0; //initialize clk (super important)
        rst_in = 0; //initialize rst (super important)
        #10  //wait a little bit of time at beginning
        rst_in = 1; //reset system
        #10; //hold high for a few clock cycles
        rst_in = 0;
        #10;

        // We can't perform test cases directly because the controller reads
        // in from only one BRAM per instantiation. Instead, we can run this
        // test case with various compiled programs and verify that the
        // behavior is as intended. Programs to check:
        //     1. PROGRAM_FILE="all-no-ops.mem"
        //     2. PROGRAM_FILE="simple-for-loop.mem"
        //     3. PROGRAM_FILE="mutliply.mem"
        //     4. PROGRAM_FILE="2-by-2-matrix-mult.mem"
        //     5. PROGRAM_FILE="mandelbrot-single-pixel.mem"

        for (int cycle = 0; cycle < 64; cycle = cycle + 1) begin
            $display("State %1d | Executing %4b", uut.state, uut.instr[0:3]);
            #10;
        end

        $finish;

    end

endmodule // controller_tb

`default_nettype wire
