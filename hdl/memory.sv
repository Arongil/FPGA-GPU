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
    // OP codes: 4'b1000 is line addr, 4'b1001 is load immediate, 4'b1010 is load from buffer, 4'b1100 is write to buffer
    // Use first 4-bit reg for loading immediate. 4'b0 means loading 0th word in the line, 4'b1 means 1st, ... , 4'b101 means 5th 
    // We have FMA_COUNT * 3 = 6 words per line right now
    // ADDR_LENGTH needs only 9 bits for now (since we are reading entire lines), which lives in the immediate section of the instr
    input wire clk_in,
    input wire rst_in,
    input wire [LINE_WIDTH - 1 : 0] buffer_read_in,
    // We assume that the buffer will keep the valid flag high until memory reads the content and go idle
    input wire [INSTRUCTION_WIDTH - 1 : 0] instr_in,
    input wire instr_valid_in,
    output logic idle_out, // 1 when idle, 0 when busy
    output logic [LINE_WIDTH - 1 : 0] abc_out,  // for each FMA i, abc_in[i] is laid out as "a b c" 
    output logic abc_valid_out,
);

    // accumulate FMA_COUNT * 3 = 6 words per line and read / write stuff into the BRAM in lines of 6 words each

    logic [ADDR_LENGTH - 1 : 0] addr;
    logic [LINE_WIDTH - 1 : 0] bram_temp_in;
    logic [LINE_WIDTH - 1 : 0] bram_in;
    logic [FMA_COUNT * 3] bram_valid_in;
    logic [LINE_WIDTH - 1 : 0] bram_out;
    logic load_imm_error;
    logic op_code_error;
    logic [1:0] cycle_ctr; // 2 cycles after the last instr_valid_in, BRAM will have processed stuff and we can go into idle state
    logic write_flag; // indicates a write operation from the BRAM to buffer
    logic bram_read;
    logic bram_write;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
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
        end
        else if (instr_valid_in) begin
            case (instr_in[31:28])
                4'b1000: begin
                    addr <= instr_in[23:8];
                    idle_out <= 0;
                    bram_read <= 0;
                    bram_write <= 0;
                end
                4'b1001: begin
                    case (instr_in[27:24]) 
                        4'b0: begin
                            bram_temp_in[LINE_WIDTH - 1 : LINE_WIDTH - 1 * WORD_WIDTH] <= instr_in[23:8];
                            bram_valid_in[5] <= 1;
                        end
                        4'b1: begin
                            bram_temp_in[LINE_WIDTH - 1 - 1 * WORD_WIDTH : LINE_WIDTH - 2 * WORD_WIDTH] <= instr_in[23:8];
                            bram_valid_in[4] <= 1;
                        end
                        4'b10: begin
                            bram_temp_in[LINE_WIDTH - 1 - 2 * WORD_WIDTH : LINE_WIDTH - 3 * WORD_WIDTH] <= instr_in[23:8];
                            bram_valid_in[3] <= 1;
                        end
                        4'b11: begin
                            bram_temp_in[LINE_WIDTH - 1 - 3 * WORD_WIDTH : LINE_WIDTH - 4 * WORD_WIDTH] <= instr_in[23:8];
                            bram_valid_in[2] <= 1;
                        end
                        4'b100: begin
                            bram_temp_in[LINE_WIDTH - 1 - 4 * WORD_WIDTH : LINE_WIDTH - 5 * WORD_WIDTH] <= instr_in[23:8];
                            bram_valid_in[1] <= 1;
                        end
                        4'b101: begin
                            bram_temp_in[LINE_WIDTH - 1 - 5 * WORD_WIDTH : 0] <= instr_in[23:8];
                            bram_valid_in[0] <= 1;
                        end
                        default: load_imm_error <= 1;
                    endcase
                    if (bram_valid_in == '1) begin
                        bram_in[LINE_WIDTH - 1 : 0] <= bram_temp_in[LINE_WIDTH - 1 : 0];
                        bram_read <= 1;
                        bram_write <= 0;
                        bram_valid_in <= 6'b0;
                    end
                    else begin
                        bram_read <= 0;
                        bram_write <= 0;
                    end
                    idle_out <= 0;
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
        else if (write_flag) begin
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
            end
            else begin
                bram_read <= 0;
                bram_write <= 0;
            end
        end
        else begin
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
            end
            else begin
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