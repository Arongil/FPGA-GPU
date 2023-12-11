`timescale 1ns / 1ps
`default_nettype none

// 

module memory #(
    parameter FMA_COUNT = 2,  // number of FMAs to prepare data for in a simultaneous read
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
    // We assume that the buffer will keep the valid flag high until memory reads the content and go idle
    input wire [0 : INSTRUCTION_WIDTH - 1] instr_in,
    input wire instr_valid_in,
    // output logic idle_out, // 1 when idle, 0 when busy Update: don't think we need this anymore
    output logic [LINE_WIDTH - 1 : 0] abc_out,  // for each FMA i, abc_in[i] is laid out as "a b c" 
    output logic use_new_c_out,
    output logic fma_output_can_be_valid_out,
    output logic abc_valid_out
);
    // OP_CODEs: read in from FMA_write_buffer 4'b1001
    // OP_CODEs: write to FMAs 4'b1010

    enum logic[3:0] {
        // ------------------------------------------------------------------------
        // | 4 bit op code | 4 bit reg | 16 bit immediate | 4 bit reg | 4 bit reg |
        // ------------------------------------------------------------------------
        OP_NOP     = 4'b0000,  // no op
        OP_END     = 4'b0001,  // end execution 
        OP_XOR     = 4'b0010,  // xor(a_reg, b_reg):
                               //    Places bitwise xor in a_reg
        OP_ADDI    = 4'b0011,  // addi(a_reg, b_reg, val):
                               //    Places sum of b_reg and val in a_reg
        OP_BGE     = 4'b0100,  // bge(a_reg, b_reg):
                               //    Sets compare_reg to 1 iff a_reg >= b_reg
        OP_JUMP    = 4'b0101,  // jump(jump_to):
                               //    Jumps to instruction at immediate index jump_to, if compare_reg is 1.
        OP_SMA     = 4'b0110,  // sma(val):
                               //    Set memory address to the immediate val in the data cache.
        OP_LOADI   = 4'b0111,  // loadi(reg_a, val):
                               //    Load immediate val into line at memory address, at word reg_a (not value at a_reg, but the direct bits).
        OP_SENDL   = 4'b1000,  // sendl():
                               //    Send line at memory address into the BRAM.
        OP_LOADB   = 4'b1001,  // loadb(val):
                               //    Load FMA buffer contents into the immediate addr in the data cache.
        OP_LOAD    = 4'b1101,  // load(abc, reg_b, diff):
                               //    Load value at controller reg_b into line address (set by SMA), put into slot abc (0 -> a, 1 -> b, 2 -> c). 
                               //    where FMA_i's value is set to reg_val + i * diff. That way we can load Mandelbrot pixels in nicely.
        OP_WRITEB  = 4'b1010   // writeb(val, replace_c, fma_valid):
                               //    Write contents of immediate addr in the data cache to FMA blocks. 
                               //    The replace_c value is the bits of reg_a.
                               //    If replace_c is 4'b0000, FMAs will use previous c values.
                               //    If replace_c is 4'b0001, FMAs will use memory c values.
                               //    The fma_valid value is the bits of reg_b.
                               //    If fma_valid is 4'b0000, the FMAs will not output results.
                               //    If fma_valid is 4'b0001, the FMAs will output their results.
                               //    Typically fma_valid is 0 until the end of a chained dot product, when it is set to 1 once.
    } isa;

    // accumulate FMA_COUNT * 3 = 6 words per line and read / write stuff into the BRAM in lines of 6 words each

    logic [ADDR_LENGTH - 1 : 0] addr;
    logic [LINE_WIDTH - 1 : 0] bram_temp_in; // accumulating stuff to put into BRAM
    logic [LINE_WIDTH - 1 : 0] bram_in; // BRAM listens to this line
    logic [LINE_WIDTH - 1 : 0] write_buffer_read_in_buffer; // BRAM takes values from here
    logic bram_read; // flag for bram to read
    logic bram_write; // flag for bram to write
    logic [1:0] bram_write_ready; // counter variable that helps control abc_valid_out
    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            addr <= 0;
            bram_temp_in <= 0;
            bram_in <= 0;
            abc_valid_out <= 0;
            use_new_c_out <= 0;
            fma_output_can_be_valid_out <= 0;
            bram_read <= 0;
            bram_write <= 0;
            bram_write_ready <= 0;
            write_buffer_read_in_buffer <= 0;
        end else begin
            if (write_buffer_valid_in) begin
                write_buffer_read_in_buffer <= write_buffer_read_in;
            end

            if (bram_write) begin
                if (bram_write_ready == 0) begin
                    bram_write_ready <= 1;
                end else if (bram_write_ready <= 1) begin
                    bram_write_ready <= 2;
                end else begin
                    bram_write_ready <= 0;
                    bram_write <= 0;
                end
                abc_valid_out <= bram_write_ready == 2'b10;
            end else begin
                abc_valid_out <= 0;
            end

            if (instr_valid_in) begin
                bram_read <= (instr_in[0:3] == OP_SENDL || instr_in[0:3] == OP_LOADB);

                case (instr_in[0:3])
                    OP_NOP: begin
                        // noppy-stuff
                        // Note: has to stall for 1 cycle, aka NOP 1 cycle with "bram_write"
                    end
                    OP_SMA: begin
                        addr <= instr_in[8:23];
                    end
                    OP_LOADI: begin
                        bram_temp_in[LINE_WIDTH - (instr_in[4:7] + 1'b1) * WORD_WIDTH +: WORD_WIDTH] <= instr_in[8:23];
                    end
                    OP_SENDL: begin
                        bram_in[LINE_WIDTH - 1 : 0] <= bram_temp_in[LINE_WIDTH - 1 : 0];
                    end
                    OP_LOADB: begin
                        bram_in[LINE_WIDTH - 1 : 0] <= write_buffer_read_in;
                        addr <= instr_in[8:23];
                    end
                    OP_WRITEB: begin
                        use_new_c_out <= (instr_in[4:7] == 4'b0001);
                        fma_output_can_be_valid_out <= (instr_in[24:27] == 4'b0001);
                        addr <= instr_in[8:23];
                        bram_write <= 1'b1;
                    end
                    OP_LOAD: begin
                        // load(abc, reg_b, diff):
                        //    Load value at controller reg_b into line address (set by SMA), put into slot abc (0 -> a, 1 -> b, 2 -> c). 
                        //    where FMA_i's value is set to reg_val + i * diff. That way we can load Mandelbrot pixels in nicely.
                        //    abc is at reg 0, which is instr_in[4:7]
                        //    reg_b is at reg 1, which is instr_in[24:27]
                        //    diff is at imm, which is instr_in[8:23] 
                        //    bram_temp_in[(i * FMA_COUNT + 16 * (j + 1) - 1) : (i * FMA_COUNT + 16 * j)]
                        //    (instr_in[24:27] == 0) ? (controller_reg_a) : ((instr_in[24:27] == 1) ? (controller_reg_b) : (controller_reg_c));
                        //    (j == instr_in[4:7]) ? (controller_reg[instr_in[27:24]] + i * instr_in[8:23] ) : (abc_valid_out[i * FMA_COUNT + j])
                        for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                            for (int j = 0; j < 3; j = j + 1) begin
                                bram_temp_in[15 : 0] <= (j == instr_in[4:7]) ? ((instr_in[24:27] == 0) ? (controller_reg_a) : ((instr_in[24:27] == 1) ? (controller_reg_b) : (controller_reg_c)) + i * instr_in[8:23]) : (bram_temp_in[i * FMA_COUNT + j]);
                            end
                        end
                    end
                endcase
            end
        end
    end

    // xilinx_true_dual_port_read_first_2_clock_ram #(
    //     .RAM_WIDTH(LINE_WIDTH),                       // Specify RAM data width
    //     .RAM_DEPTH(36000 / LINE_WIDTH),                     // Specify RAM depth (number of entries)
    //     .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
    //     .INIT_FILE("")                        // Specify name/location of RAM initialization file if using one (leave blank if not)
    // ) memory_BRAM (
    //     .addra(addr),   // Port A address bus, width determined from RAM_DEPTH
    //     .dina(bram_in),     // Port A RAM input data, width determined from RAM_WIDTH
    //     .clka(clk_in),     // Port A clock
    //     .wea(bram_read),       // Port A write enable
    //     .ena(1'b1),       // Port A RAM Enable, for additional power savings, disable port when not in use
    //     .rsta(1'b0),     // Port A output reset (does not affect memory contents)
    //     .regcea(bram_write), // Port A output register enable
    //     .douta(abc_out),   // Port A RAM output data, width determined from RAM_WIDTH
    //     .addrb(),   // Port B address bus, width determined from RAM_DEPTH
    //     .dinb(),     // Port B RAM input data, width determined from RAM_WIDTH
    //     .clkb(),     // Port B clock
    //     .web(),       // Port B write enable
    //     .enb(),       // Port B RAM Enable, for additional power savings, disable port when not in use
    //     .rstb(),     // Port B output reset (does not affect memory contents)
    //     .regceb(), // Port B output register enable
    //     .doutb()    // Port B RAM output data, width determined from RAM_WIDTH
    // );
endmodule










/*
`timescale 1ns / 1ps
`default_nettype none

// 

module memory #(
    parameter FMA_COUNT = 2,  // number of FMAs to prepare data for in a simultaneous read
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
    input wire [LINE_WIDTH - 1 : 0] write_buffer_read_in,
    input wire write_buffer_valid_in,
    // We assume that the buffer will keep the valid flag high until memory reads the content and go idle
    input wire [0 : INSTRUCTION_WIDTH - 1] instr_in,
    input wire instr_valid_in,
    output logic idle_out, // 1 when idle, 0 when busy
    output logic [LINE_WIDTH - 1 : 0] abc_out,  // for each FMA i, abc_in[i] is laid out as "a b c" 
    output logic use_new_c_out,
    output logic fma_output_can_be_valid_out,
    output logic abc_valid_out
);
    // OP_CODEs: read in from FMA_write_buffer 4'b1001
    // OP_CODEs: write to FMAs 4'b1010

    enum logic[3:0] {
        // ------------------------------------------------------------------------
        // | 4 bit op code | 4 bit reg | 16 bit immediate | 4 bit reg | 4 bit reg |
        // ------------------------------------------------------------------------
        OP_NOP     = 4'b0000,  // no op
        OP_END     = 4'b0001,  // end execution 
        OP_XOR     = 4'b0010,  // xor(a_reg, b_reg):
                               //    Places bitwise xor in a_reg
        OP_ADDI    = 4'b0011,  // addi(a_reg, b_reg, val):
                               //    Places sum of b_reg and val in a_reg
        OP_BGE     = 4'b0100,  // bge(a_reg, b_reg):
                               //    Sets compare_reg to 1 iff a_reg >= b_reg
        OP_JUMP    = 4'b0101,  // jump(jump_to):
                               //    Jumps to instruction at immediate index jump_to, if compare_reg is 1.
        OP_SMA     = 4'b0110,  // sma(val):
                               //    Set memory address to the immediate val in the data cache.
        OP_LOADI   = 4'b0111,  // loadi(reg_a, val):
                               //    Load immediate val into line at memory address, at word reg_a (not value at a_reg, but the direct bits).
        OP_SENDL   = 4'b1000,  // sendl():
                               //    Send line at memory address into the BRAM.
        OP_LOADB   = 4'b1001,  // loadb(val):
                               //    Load FMA buffer contents into the immediate addr in the data cache.
        OP_WRITEB  = 4'b1010   // writeb(val, replace_c, fma_valid):
                               //    Write contents of immediate addr in the data cache to FMA blocks. 
                               //    The replace_c value is the bits of reg_a.
                               //    If replace_c is 4'b0000, FMAs will use previous c values.
                               //    If replace_c is 4'b0001, FMAs will use memory c values.
                               //    The fma_valid value is the bits of reg_b.
                               //    If fma_valid is 4'b0000, the FMAs will not output results.
                               //    If fma_valid is 4'b0001, the FMAs will output their results.
                               //    Typically fma_valid is 0 until the end of a chained dot product, when it is set to 1 once.
    } isa;

    // accumulate FMA_COUNT * 3 = 6 words per line and read / write stuff into the BRAM in lines of 6 words each

    logic [ADDR_LENGTH - 1 : 0] addr;
    logic [LINE_WIDTH - 1 : 0] bram_temp_in;
    logic [LINE_WIDTH - 1 : 0] bram_in;
    logic [FMA_COUNT * 3 - 1 : 0] bram_valid_in;
    logic [LINE_WIDTH - 1 : 0] write_buffer_read_in_buffer;
    logic load_imm_error;
    logic op_code_error;
    logic bram_read;
    logic bram_write;
    logic bram_write_ready_to_reset;
    logic reset_bram_read; // reset logics after putting one line into BRAM from system
    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            idle_out <= 1;
            addr <= 0;
            bram_temp_in <= 0;
            bram_in <= 0;
            bram_valid_in <= 0;
            abc_valid_out <= 0;
            use_new_c_out <= 0;
            fma_output_can_be_valid_out <= 0;
            op_code_error <= 0;
            bram_read <= 0;
            bram_write <= 0;
            bram_write_ready_to_reset <= 0;
            write_buffer_read_in_buffer <= 0;
            reset_bram_read <= 0;
        end else begin
            if (instr_valid_in) begin
                case (instr_in[0:3])

                    OP_NOP: begin
                        // Hanfei: factor out these if statements to be cleaner
                        idle_out <= 1;
                        if (reset_bram_read) begin
                            bram_temp_in <= 0;
                            bram_in <= 0;
                            bram_valid_in <= 0;
                            load_imm_error <= 0;
                            op_code_error <= 0;
                            bram_read <= 0;
                            reset_bram_read <= 0;
                        end
                        

                        // TODO HANFEI: make it possible to prefetch next
                        // writeb data without taking NOP cycle in between.
                        // Implementation: convert memory into finite state
                        // machine to reduce reliance on tons of fiddly flags.
                        
                        // Set abc_valid_out if we just asked BRAM to write to FMAs.
                        if (bram_write) begin
                            if (bram_write_ready_to_reset) begin
                                bram_write_ready_to_reset <= 0;
                                bram_write <= 0;
                                abc_valid_out <= 1;
                            end else begin
                                bram_write_ready_to_reset <= 1;
                            end
                        end else begin
                            abc_valid_out <= 0;
                        end
                    end

                    // Set Memory Address (sets addr)
                    OP_SMA: begin 
                        addr <= instr_in[8:23];
                        idle_out <= 1;
                        bram_read <= 0;
                        bram_write <= 0;
                        abc_valid_out <= 0;
                        if (reset_bram_read) begin
                            bram_temp_in <= 0;
                            bram_in <= 0;
                            bram_valid_in <= 0;
                            load_imm_error <= 0;
                            op_code_error <= 0;
                            bram_read <= 0;
                            reset_bram_read <= 0;
                        end
                    end

                    // Load immediate at address
                    OP_LOADI: begin
                        idle_out <= 0;

                        // instr_in[4:7] contain the bits for which word to set
                        if (instr_in[4:7] < 6) begin
                            // See bottom of this file for calculation for what "+:" means in the expression above.
                            bram_valid_in[instr_in[4:7]] <= 1;
                            bram_temp_in[LINE_WIDTH - (instr_in[4:7] + 1'b1) * WORD_WIDTH +: WORD_WIDTH] <= instr_in[8:23];
                        end else begin
                            load_imm_error <= 1;
                        end
                        bram_read <= 0;
                        bram_write <= 0;
                        abc_valid_out <= 0;
                    end
                    OP_SENDL: begin
                        // NEW INSTRUCTION: after putting 6 words on the line, send a new instruction to flush line into BRAM
                        bram_in[LINE_WIDTH - 1 : 0] <= bram_temp_in[LINE_WIDTH - 1 : 0];
                        bram_read <= 1;
                        bram_write <= 0;
                        bram_valid_in <= 6'b0;
                        reset_bram_read <= 1;
                        abc_valid_out <= 0;
                    end
                    OP_LOADB: begin
                        // We assume that the buffer will keep the valid flag high until memory reads the content and go idle
                        bram_in[LINE_WIDTH - 1 : 0] <= write_buffer_read_in_buffer;
                        addr <= instr_in[8:23];
                        idle_out <= 0;
                        bram_read <= 1;
                        bram_write <= 0;
                        reset_bram_read <= 1;
                        abc_valid_out <= 0;
                    end
                    OP_WRITEB: begin
                        use_new_c_out <= (instr_in[4:7] == 4'b0001);
                        fma_output_can_be_valid_out <= (instr_in[24:27] == 4'b0001);
                        addr <= instr_in[8:23];
                        idle_out <= 0;
                        bram_read <= 0;
                        bram_write <= 1;
                        abc_valid_out <= 0;
                    end
                    default: op_code_error <= 1;
                endcase
            end
            else begin
                abc_valid_out <= 0; // If no more instructions are coming in, make sure the fma blocks don't keep waiting for new data
            end

            if (write_buffer_valid_in) begin
                write_buffer_read_in_buffer <= write_buffer_read_in;
            end
        end
    end

    xilinx_true_dual_port_read_first_2_clock_ram #(
        .RAM_WIDTH(LINE_WIDTH),                       // Specify RAM data width
        .RAM_DEPTH(36000 / LINE_WIDTH),                     // Specify RAM depth (number of entries)
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
        .INIT_FILE("")                        // Specify name/location of RAM initialization file if using one (leave blank if not)
    ) memory_BRAM (
        .addra(addr),   // Port A address bus, width determined from RAM_DEPTH
        .dina(bram_in),     // Port A RAM input data, width determined from RAM_WIDTH
        .clka(clk_in),     // Port A clock
        .wea(bram_read),       // Port A write enable
        .ena(1'b1),       // Port A RAM Enable, for additional power savings, disable port when not in use
        .rsta(1'b0),     // Port A output reset (does not affect memory contents)
        .regcea(bram_write), // Port A output register enable
        .douta(abc_out),   // Port A RAM output data, width determined from RAM_WIDTH
        .addrb(),   // Port B address bus, width determined from RAM_DEPTH
        .dinb(),     // Port B RAM input data, width determined from RAM_WIDTH
        .clkb(),     // Port B clock
        .web(),       // Port B write enable
        .enb(),       // Port B RAM Enable, for additional power savings, disable port when not in use
        .rstb(),     // Port B output reset (does not affect memory contents)
        .regceb(), // Port B output register enable
        .doutb()    // Port B RAM output data, width determined from RAM_WIDTH
    );
endmodule

`default_nettype wire

// Calculation for what "+:" means in LOADI case above:
//
// bram_temp_in[LINE_WIDTH - instr_in[4:7] * WORD_WIDTH - 1 : LINE_WIDTH - (instr_in[4:7] + 1'b1) * WORD_WIDTH] <= instr_in[8:23];
// (x+y-1) = LINE_WIDTH - instr_in[4:7] * WORD_WIDTH - 1
// (x) = LINE_WIDTH - (instr_in[4:7] + 1'b1) * WORD_WIDTH
// (y-1) = LINE_WIDTH - instr_in[4:7] * WORD_WIDTH - 1 - LINE_WIDTH + (instr_in[4:7] + 1'b1) * WORD_WIDTH
// = - (instr_in[4:7] * WORD_WIDTH + 1) + (instr_in[4:7] + 1'b1) * WORD_WIDTH
// = - (instr_in[4:7] * WORD_WIDTH + 1) + (instr_in[4:7] * WORD_WIDTH) + WORD_WIDTH
// = WORD_WIDTH - 1
// y = WORD_WIDTH
//
// w[x  +: y] == w[(x+y-1) : x]
*/
