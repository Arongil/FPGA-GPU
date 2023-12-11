`timescale 1ns / 1ps
`default_nettype none

module memory #(
    parameter FMA_COUNT = 2,  // number of FMAs to prepare data for in a simultaneous read
    parameter WORD_WIDTH = 16,  // number of bits per number aka width of a word
    parameter FIXED_POINT = 10, // number of bits after the decimal
    parameter LINE_WIDTH = 96,  // width of a line, FMA_COUNT * 3 * WORD_WIDTH = 2 * 3 * 16 = 96
    parameter ADDR_LENGTH = $clog2(36000 / 96),  // 96 bits in a line. 36kb/96 = 375
    parameter INSTRUCTION_WIDTH = 32      // number of bits per instruction
) (
    // Use first 4-bit reg for loading immediate. 4'b0 means loading 0th word in the line, 4'b1 means 1st, ... , 4'b101 means 5th 
    // We have FMA_COUNT * 3 = 6 words per line right now
    // ADDR_LENGTH needs only 9 bits for now (since we are reading entire lines), which lives in the immediate section of the instr
    input wire clk_in,
    input wire rst_in,
    input wire [WORD_WIDTH-1:0] controller_reg_a,
    input wire [WORD_WIDTH-1:0] controller_reg_b,
    input wire [WORD_WIDTH-1:0] controller_reg_c,
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

    // 3 registers, 4 bits each
    logic [3*4-1:0] reg_vals;
    assign reg_vals = {instr_in[4:7], instr_in[24:27], instr_in[28:31]};

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
                bram_read <= (instr_in[0:3] == OP_SENDL);

                case (instr_in[0:3])
                    OP_NOP: begin
                    end
                    OP_SMA: begin
                        addr <= instr_in[8:23];
                    end
                    OP_LOADI: begin
                        // What "+:" means:
                        // w[x +: y] == w[(x+y-1) : x]
                        bram_temp_in[LINE_WIDTH - (instr_in[4:7]+1) * WORD_WIDTH +: WORD_WIDTH] <= instr_in[8:23];
                    end
                    OP_SENDL: begin
                        bram_in[LINE_WIDTH - 1 : 0] <= bram_temp_in[LINE_WIDTH - 1 : 0];
                    end
                    OP_LOADB: begin
                        // instr[4:7] is shuffle1, instr[24:27] is shuffle2, instr[28:31] is shuffle2
                        // write_buffer_read_in_buffer is shape "fma_2_c_3 fma_1_c_3 fma_2_c_2 fma_1_c_2 fma_2_c_1 fma_1_c_1"
                        //   The two steps to select out are (shuffle * FMA_COUNT*WORD_WIDTH) and (fma_id * WORD_WIDTH)
                        for (int fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin
                            for (int abc = 0; abc < 3; abc = abc + 1) begin
                                // reg_vals[12-(abc+1)*4 +: 4] is the same as shuffle1, shuffle2, shuffle3, selected according to abc
                                if (reg_vals[12-(abc+1)*4 +: 4] == 4'b0000) begin // 0 --> 0
                                    bram_temp_in[LINE_WIDTH - (fma_id*3 + abc + 1) * WORD_WIDTH +: WORD_WIDTH] <= 0;
                                end else if (reg_vals[12-(abc+1)*4 +: 4] <= 4'b0011) begin // 1, 2, 3 ---> set to corresponding
                                    bram_temp_in[LINE_WIDTH - (fma_id*3 + abc + 1) * WORD_WIDTH +: WORD_WIDTH] <= write_buffer_read_in_buffer[(reg_vals[12-(abc+1)*4 +: 4]-4'b0001)*FMA_COUNT*WORD_WIDTH + fma_id * WORD_WIDTH +: WORD_WIDTH];
                                end else if (reg_vals[12-(abc+1)*4 +: 4] <= 4'b0110) begin // 4, 5, 6 ---> set to 2*corresponding
                                    bram_temp_in[LINE_WIDTH - (fma_id*3 + abc + 1) * WORD_WIDTH +: WORD_WIDTH] <= 2*write_buffer_read_in_buffer[(reg_vals[12-(abc+1)*4 +: 4]-4'b0011-4'b0001)*FMA_COUNT*WORD_WIDTH + fma_id * WORD_WIDTH +: WORD_WIDTH];
                                end else if (reg_vals[12-(abc+1)*4 +: 4] >= 4'b1101) begin // -1, -2, -3 ---> set to -1*corresponding (two's complement in fixed point space)
                                    bram_temp_in[LINE_WIDTH - (fma_id*3 + abc + 1) * WORD_WIDTH +: WORD_WIDTH] <= (1<<FIXED_POINT) + ~write_buffer_read_in_buffer[(-reg_vals[12-(abc+1)*4 +: 4]-4'b0001)*FMA_COUNT*WORD_WIDTH + fma_id * WORD_WIDTH +: WORD_WIDTH];
                                end else begin
                                    // ERROR
                                end
                            end
                        end

                        // OLD: bram_in[LINE_WIDTH - 1 : 0] <= write_buffer_read_in;
                        // OLD: addr <= instr_in[8:23];
                    end
                    OP_LOAD: begin
                        // load(abc, reg_b, diff):
                        //    Load value at controller_reg_b, put into slot instr_in[4:7] = abc (0 -> a, 1 -> b, 2 -> c)
                        //    where FMA_i's value is set to reg_val + i * immediate_diff.
                        for (int fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin
                            bram_temp_in[LINE_WIDTH - (fma_id*3 + instr_in[4:7] + 1) * WORD_WIDTH +: WORD_WIDTH] <= controller_reg_b + fma_id * instr_in[8:23];
                        end
                    end
                    OP_WRITEB: begin
                        use_new_c_out <= (instr_in[4:7] == 4'b0001);
                        fma_output_can_be_valid_out <= (instr_in[24:27] == 4'b0001);
                        addr <= instr_in[8:23];
                        bram_write <= 1'b1;
                    end
                endcase
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

