`timescale 1ns / 1ps
`default_nettype none

module top_level_tb;

    localparam PRIVATE_REG_WIDTH=16;
    localparam PRIVATE_REG_COUNT=16;
    localparam INSTRUCTION_WIDTH=32;
    localparam INSTRUCTION_COUNT=61;    // UPDATE TO MATCH PROGRAM_FILE!
    localparam DATA_CACHE_WIDTH=16;
    localparam DATA_CACHE_DEPTH=4096;

    localparam FIXED_POINT=10;
    localparam WORD_WIDTH=16;
    localparam LINE_WIDTH=96;
    localparam FMA_COUNT=2;

    localparam ADDR_LENGTH=$clog2(36000 / 96);

    localparam CYCLES_TO_RUN = 750;//2*INSTRUCTION_COUNT + 8;

    // make logics for inputs and outputs!
    logic clk_in;
    logic rst_in;

    // logics for FMAs
    logic [3*WORD_WIDTH-1:0] fma_abc_1, fma_abc_2;
    logic fma_c_valid_in_1, fma_c_valid_in_2;
    logic [WORD_WIDTH-1:0] fma_out_1, fma_out_2;
    logic fma_valid_out_1, fma_valid_out_2;

    // logics for fma write buffer
    logic [WORD_WIDTH*FMA_COUNT-1:0] write_buffer_fma_out;
    logic [FMA_COUNT-1:0] write_buffer_fma_valid_out;
    logic [3*WORD_WIDTH*FMA_COUNT-1:0] write_buffer_line_out;
    logic write_buffer_line_valid;

    // logics for memory
    logic [0:INSTRUCTION_WIDTH-1] memory_instr_in;
    logic memory_instr_valid_in;
    logic memory_idle_out;
    logic [LINE_WIDTH-1:0] memory_abc_out;
    logic memory_use_new_c_out;
    logic memory_fma_output_can_be_valid_out;
    logic memory_abc_valid_out;

    // logics for controller
    logic [WORD_WIDTH-1:0] controller_reg_a, controller_reg_b, controller_reg_c;

    // Instantiate 2 FMA blocks!
    fma #(
        .WIDTH(WORD_WIDTH),
        .FIXED_POINT(FIXED_POINT)
    ) fma1 (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .abc(memory_abc_out[LINE_WIDTH - 1:LINE_WIDTH/2]),
        .valid_in(memory_abc_valid_out),
        .c_valid_in(memory_use_new_c_out),
        .output_can_be_valid_in(memory_fma_output_can_be_valid_out),
        .out(fma_out_1),
        .valid_out(fma_valid_out_1)
    );

    fma #(
        .WIDTH(WORD_WIDTH),
        .FIXED_POINT(FIXED_POINT)
    ) fma2 (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .abc(memory_abc_out[LINE_WIDTH/2 - 1:0]),
        .valid_in(memory_abc_valid_out),
        .c_valid_in(memory_use_new_c_out),
        .output_can_be_valid_in(memory_fma_output_can_be_valid_out),
        .out(fma_out_2),
        .valid_out(fma_valid_out_2)
    );

    // Instantiate write buffer!
    fma_write_buffer #(
        .FMA_COUNT(FMA_COUNT),
        .WORD_WIDTH(WORD_WIDTH),
        .LINE_WIDTH(LINE_WIDTH)
    ) write_buffer (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .fma_out(write_buffer_fma_out),
        .fma_valid_out(write_buffer_fma_valid_out),
        .line_out(write_buffer_line_out),
        .line_valid(write_buffer_line_valid)
    );

    // Instantiate memory module!
    memory #(
        .FMA_COUNT(FMA_COUNT),
        .WORD_WIDTH(WORD_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .ADDR_LENGTH(ADDR_LENGTH),
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH)
    ) main_memory (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .controller_reg_a(controller_reg_a),
        .controller_reg_b(controller_reg_b),
        .controller_reg_c(controller_reg_c),
        .write_buffer_read_in(write_buffer_line_out),
        .write_buffer_valid_in(write_buffer_line_valid),
        .instr_in(memory_instr_in),
        .instr_valid_in(memory_instr_valid_in),
        .abc_out(memory_abc_out),
        .abc_valid_out(memory_abc_valid_out),
        .use_new_c_out(memory_use_new_c_out),
        .fma_output_can_be_valid_out(memory_fma_output_can_be_valid_out)
    );

    // Instantiate controller!
    controller #(
        .PROGRAM_FILE(),
        .PRIVATE_REG_WIDTH(PRIVATE_REG_WIDTH),
        .PRIVATE_REG_COUNT(PRIVATE_REG_COUNT),
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH),
        .INSTRUCTION_COUNT(INSTRUCTION_COUNT),
        .DATA_CACHE_WIDTH(DATA_CACHE_WIDTH),
        .DATA_CACHE_DEPTH(DATA_CACHE_DEPTH)
    ) controller_module (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .instr_out(memory_instr_in),
        .reg_a_out(controller_reg_a),
        .reg_b_out(controller_reg_b),
        .reg_c_out(controller_reg_c),
        .instr_valid_for_memory_out(memory_instr_valid_in)
    );


    // Declare testbench variables here
    logic [INSTRUCTION_WIDTH-1:0] addr;

    always begin
        #5;  //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
        clk_in = !clk_in;

        // set fma write buffer to wire up from every individual FMA
        write_buffer_fma_out = {fma_out_1, fma_out_2};
        write_buffer_fma_valid_out = {fma_valid_out_1, fma_valid_out_2};
    end

    //initial block...this is our test simulation
    initial begin
        $dumpfile("top_level.vcd"); //file to store value change dump (vcd)
        $dumpvars(0, top_level_tb); //store everything at the current level and below
        $display("Starting Sim\n"); //print nice message
        clk_in = 0; //initialize clk (super important)
        rst_in = 0; //initialize rst (super important)
        #10  //wait a little bit of time at beginning
        rst_in = 1; //reset system
        #10; //hold high for a few clock cycles
        rst_in = 0;
        #10;

        for (int cycle = 0; cycle < CYCLES_TO_RUN; cycle = cycle + 1) begin
            if (cycle < 10 || CYCLES_TO_RUN - cycle < 10) begin
                $display("State %1d | Executing %4b", controller_module.state, controller_module.instr[0:3]);
            end else if (cycle == 10) begin
                $display("...\n...\n...");
            end
            #10;
        end

        $finish;

    end

endmodule // top_level_tb

`default_nettype wire
