`timescale 1ns / 1ps
`default_nettype none

// 

module memory #(
    parameter FMA_COUNT = 2,  // number of FMAs to prepare data for in a simultaneous read
    parameter WORD_WIDTH = 16,  // number of bits per number aka width of a word
    parameter LINE_WIDTH = 96,  // width of a line, FMA_COUNT * 3 * WORD_WIDTH = 2 * 3 * 16 = 96
    parameter ADDR_LENGTH = $clog2(375),  // 96 bits in a line. 36kb/96 = 375
    parameter INSTRUCTION_WIDTH = 32      // number of bits per instruction
) (
    // Use first 4-bit reg for loading immediate. 4'b0 means loading 0th word in the line, 4'b1 means 1st, ... , 4'b101 means 5th 
    // We have FMA_COUNT * 3 = 6 words per line right now
    // ADDR_LENGTH needs only 9 bits for now (since we are reading entire lines), which lives in the immediate section of the instr
    input wire clk_in,
    input wire rst_in,
    input wire [LINE_WIDTH - 1 : 0] buffer_read_in,
    // We assume that the buffer will keep the valid flag high until memory reads the content and go idle
    input wire [0 : INSTRUCTION_WIDTH - 1] instr_in,
    input wire instr_valid_in,
    output logic idle_out, // 1 when idle, 0 when busy
    output logic [LINE_WIDTH - 1 : 0] abc_out,  // for each FMA i, abc_in[i] is laid out as "a b c" 
    output logic abc_valid_out
);
    // OP_CODEs: read in from FMA_write_buffer 4'b1010
    // OP_CODEs: write to FMA_read_buffer 4'b1100

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
        OP_LOADB   = 4'b1000,  // loadb(val):
                               //    Load FMA buffer contents into the immediate addr in the data cache.
        OP_WRITEB  = 4'b1001   // writeb(val):
                               //    Write contents of immediate addr in the data cache to FMA blocks. 
    } isa;

    // accumulate FMA_COUNT * 3 = 6 words per line and read / write stuff into the BRAM in lines of 6 words each

    logic [ADDR_LENGTH - 1 : 0] addr;
    logic [LINE_WIDTH - 1 : 0] bram_temp_in;
    logic [LINE_WIDTH - 1 : 0] bram_in;
    logic [FMA_COUNT * 3 - 1 : 0] bram_valid_in;
    logic [LINE_WIDTH - 1 : 0] bram_out;
    logic load_imm_error;
    logic op_code_error;
    logic [1:0] cycle_ctr; // 2 cycles after the last instr_valid_in, BRAM will have processed stuff and we can go into idle state
    logic write_flag; // indicates a write operation from the BRAM to buffer
    logic bram_read;
    logic bram_write;
    logic reset_bram_read; // reset logics after putting one line into BRAM from system
    logic pull_abc_valid_out_low_flag; // will write a state machine later to make this less painful

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            idle_out <= 1;
            addr <= 0;
            bram_temp_in <= 0;
            bram_in <= 0;
            bram_valid_in <= 0;
            abc_out <= 0;
            abc_valid_out <= 0;
            load_imm_error <= 0;
            op_code_error <= 0;
            cycle_ctr <= 0;
            write_flag <= 0;
            bram_read <= 0;
            bram_write <= 0;
            reset_bram_read <= 0;
            pull_abc_valid_out_low_flag <= 0;
        end else begin
            if (instr_valid_in) begin
                case (instr_in[0:3])

                    // Set Memory Address (sets addr)
                    OP_SMA: begin 
                        addr <= instr_in[8:23];
                        idle_out <= 1;  // WHY NOT RETURN IDLE_OUT <= 1? Resolved
                        bram_read <= 0;
                        bram_write <= 0;
                    end

                    // Load immediate at address
                    OP_LOADI: begin
                        idle_out <= 0;

                        // instr_in[4:7] contain the bits for which word to set
                        if (instr_in[4:7] < 6) begin
                            bram_valid_in[instr_in[4:7]] <= 1;
                            bram_temp_in[LINE_WIDTH - (instr_in[4:7] + 1'b1) * WORD_WIDTH +: WORD_WIDTH] <= instr_in[8:23];
                            // bram_temp_in[LINE_WIDTH - instr_in[4:7] * WORD_WIDTH - 1 : LINE_WIDTH - (instr_in[4:7] + 1'b1) * WORD_WIDTH] <= instr_in[8:23];
                            // (x+y-1) = LINE_WIDTH - instr_in[4:7] * WORD_WIDTH - 1
                            // (x) = LINE_WIDTH - (instr_in[4:7] + 1'b1) * WORD_WIDTH
                            // (y-1) = LINE_WIDTH - instr_in[4:7] * WORD_WIDTH - 1 - LINE_WIDTH + (instr_in[4:7] + 1'b1) * WORD_WIDTH
                            // = - (instr_in[4:7] * WORD_WIDTH + 1) + (instr_in[4:7] + 1'b1) * WORD_WIDTH
                            // = - (instr_in[4:7] * WORD_WIDTH + 1) + (instr_in[4:7] * WORD_WIDTH) + WORD_WIDTH
                            // = WORD_WIDTH - 1
                            // y = WORD_WIDTH
                            // w[x  +: y] == w[(x+y-1) : x]
                        end else begin
                            load_imm_error <= 1;
                        end
                        bram_read <= 0;
                        bram_write <= 0;
                    end
                    4'b1110: begin
                        // NEW INSTRUCTION: aftering putting 6 words on the line, send a new instruction to flush line into BRAM
                        bram_in[LINE_WIDTH - 1 : 0] <= bram_temp_in[LINE_WIDTH - 1 : 0];
                        bram_read <= 1;
                        bram_write <= 0;
                        bram_valid_in <= 6'b0;
                        reset_bram_read <= 1;
                    end
                    4'b1010: begin
                        // We assume that the buffer will keep the valid flag high until memory reads the content and go idle
                        bram_in[LINE_WIDTH - 1 : 0] <= buffer_read_in[LINE_WIDTH - 1 : 0];
                        idle_out <= 0;
                        bram_read <= 1;
                        bram_write <= 0;
                        reset_bram_read <= 1;
                    end
                    4'b1100: begin
                        write_flag <= 1;
                        idle_out <= 0;
                        bram_read <= 0;
                        bram_write <= 1;
                    end
                    default: op_code_error <= 1;
                endcase
                abc_valid_out <= 0;
            end

            // Hanfei: factor out these if statements to be cleaner
            else if (write_flag) begin
                if (cycle_ctr == 2'b01) begin
                    abc_out <= bram_out;
                    abc_valid_out <= 1;
                    bram_temp_in <= 0;
                    bram_in <= 0;
                    bram_valid_in <= 0;
                    idle_out <= 1;
                    load_imm_error <= 0;
                    op_code_error <= 0;
                    cycle_ctr <= 0;
                    write_flag <= 0;
                    bram_read <= 0;
                    bram_write <= 0;
                    pull_abc_valid_out_low_flag <= 1;
                end else begin
                    cycle_ctr <= cycle_ctr + 1;
                    bram_read <= 0;
                    bram_write <= 0;
                end
            end 
            else if (reset_bram_read) begin
                bram_temp_in <= 0;
                bram_in <= 0;
                bram_valid_in <= 0;
                idle_out <= 1;
                load_imm_error <= 0;
                op_code_error <= 0;
                bram_read <= 0;
                reset_bram_read <= 0;
                abc_valid_out <= 0;
            end
            else if (pull_abc_valid_out_low_flag) begin
                abc_valid_out <= 0;
                pull_abc_valid_out_low_flag <= 0;
            end
        end
    end

    xilinx_true_dual_port_read_first_2_clock_ram #(
        .RAM_WIDTH(LINE_WIDTH),                       // Specify RAM data width
        .RAM_DEPTH(WORD_WIDTH),                     // Specify RAM depth (number of entries)
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
        .INIT_FILE("")                        // Specify name/location of RAM initialization file if using one (leave blank if not)
    ) memory_BRAM (
        .addra(addr),   // Port A address bus, width determined from RAM_DEPTH
        .addrb(),   // Port B address bus, width determined from RAM_DEPTH
        .dina(bram_in),     // Port A RAM input data, width determined from RAM_WIDTH
        .dinb(),     // Port B RAM input data, width determined from RAM_WIDTH
        .clka(clk_in),     // Port A clock
        .clkb(),     // Port B clock
        .wea(bram_read),       // Port A write enable
        .web(),       // Port B write enable
        .ena(1),       // Port A RAM Enable, for additional power savings, disable port when not in use
        .enb(),       // Port B RAM Enable, for additional power savings, disable port when not in use
        .rsta(0),     // Port A output reset (does not affect memory contents)
        .rstb(),     // Port B output reset (does not affect memory contents)
        .regcea(bram_write), // Port A output register enable
        .regceb(), // Port B output register enable
        .douta(bram_out),   // Port A RAM output data, width determined from RAM_WIDTH
        .doutb()    // Port B RAM output data, width determined from RAM_WIDTH
    );
endmodule

`default_nettype wire
