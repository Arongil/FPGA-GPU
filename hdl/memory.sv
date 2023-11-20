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
    output logic abc_valid_out,
);


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
        OP_JUMP    = 4'b0101   // jump(jump_to):
                               //    Jumps to instruction at immediate index jump_to, if compare_reg is 1.
        OP_SMA     = 4'b0110   // sma(val):
                               //    Set memory address to the immediate val in the data cache.
        OP_LOADI   = 4'b0111   // loadi(a_reg, val):
                               //    Load immediate val into line at memory address, at word a_reg (not value at a_reg, but the direct bits).
        OP_LOADB   = 4'b1000   // loadb(val):
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

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            idle_out <= 1;
            addr <= 0;
            bram_temp_in <= 0;
            bram_in <= 0;
            bram_valid_in <= 0;
            bram_out <= 0;
            abc_out <= 0;
            abc_valid_out <= 0;
            load_imm_error <= 0;
            op_code_error <= 0;
            cycle_ctr <= 0;
            write_flag <= 0;
            bram_read <= 0;
            bram_write <= 0;
        end else begin
            if (instr_valid_in) begin
                case (instr_in[0:3])

                    // Set Memory Address (sets addr)
                    OP_SMA: begin 
                        addr <= instr_in[8:23];
                        idle_out <= 0;  // WHY NOT RETURN IDLE_OUT <= 1?
                        bram_read <= 0;
                        bram_write <= 0;
                    end

                    // Load immediate at address
                    OP_LOADI: begin
                        idle_out <= 0;

                        // instr[4:7] contain the bits for which word to set
                        if (instr[4:7] < 6) begin
                            bram_valid_in[instr[4:7]] <= 1;
                            bram_temp_in[LINE_WIDTH - instr[4:7] * WORD_WIDTH - 1 : LINE_WIDTH - (instr[4:7] + 1'b1) * WORD_WIDTH] <= instr_in[8:23];
                        end else begin
                            load_imm_error <= 1;
                        end

                        // If the entire BRAM is valid, set it as ready to write.
                        if (bram_valid_in == '1) begin
                            bram_in[LINE_WIDTH - 1 : 0] <= bram_temp_in[LINE_WIDTH - 1 : 0];
                            bram_read <= 1;
                            bram_write <= 0;
                            bram_valid_in <= 6'b0;
                        end else begin
                            bram_read <= 0;
                            bram_write <= 0;
                        end
                    end
                    4'b1010: begin
                        // We assume that the buffer will keep the valid flag high until memory reads the content and go idle
                        bram_in[LINE_WIDTH - 1 : 0] <= buffer_read_in[LINE_WIDTH - 1 : 0];
                        idle_out <= 0;
                        bram_read <= 1;
                        bram_write <= 0;
                    end
                    4'b1100: begin
                        write_flag <= 1;
                        idle_out <= 0;
                        bram_read <= 0;
                        bram_write <= 0;
                    end
                default: op_code_error <= 1;
            endcase
        end

        // Hanfei: factor out these if statements to be cleaner
        if (write_flag) begin
            cycle_ctr <= cycle_ctr + 1;
            if (cycle_ctr == 2'b10) begin
                abc_out[LINE_WIDTH - 1 : 0] <= bram_out[LINE_WIDTH - 1 : 0];
                addr <= 0;
                bram_temp_in <= 0;
                bram_in <= 0;
                bram_valid_in <= 0;
                bram_out <= 0;
                idle_out <= 1;
                abc_out <= 0;
                abc_valid_out <= 0;
                load_imm_error <= 0;
                op_code_error <= 0;
                cycle_ctr <= 0;
                write_flag <= 0;
                bram_read <= 0;
                bram_write <= 1;
            end else begin
                bram_read <= 0;
                bram_write <= 0;
            end
        end else begin
            cycle_ctr <= cycle_ctr + 1;
            if (cycle_ctr == 2'b10) begin
                addr <= 0;
                bram_temp_in <= 0;
                bram_in <= 0;
                bram_valid_in <= 0;
                bram_out <= 0;
                idle_out <= 1;
                abc_out <= 0;
                abc_valid_out <= 0;
                load_imm_error <= 0;
                op_code_error <= 0;
                cycle_ctr <= 0;
                write_flag <= 0;
                bram_read <= 0;
                bram_write <= 0;
            end else begin
                bram_read <= 0;
                bram_write <= 0;
            end
        end
    end

    xilinx_single_port_ram_read_first #(
        .RAM_WIDTH(LINE_WIDTH),        // Specify RAM data width
        .RAM_DEPTH(WORD_WIDTH),        // Specify RAM depth
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
        .INIT_FILE())          // Specify name/location of RAM initialization file if using one (leave blank if not)
    ) data_cache_BRAM (
        .addra(addr),     // Address bus, width is ADDR_LENGTH
        .dina(bram_in),       // RAM input data, width is WIDTH
        .clka(clk_in),       // Clock
        .wea(bram_read),         // Write enable
        .ena(1),         // RAM Enable, for additional power savings, disable port when not in use
        .rsta(0),       // Output reset (does not affect memory contents)
        .regcea(bram_write),    // Output register enable
        .douta(bram_out)      // RAM output data, width is WIDTH
endmodule

`default_nettype wire
