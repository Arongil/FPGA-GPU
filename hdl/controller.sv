`timescale 1ns / 1ps
`default_nettype none

`ifdef SYNTHESIS
`define FPATH(X) `"X`"
`else /* ! SYNTHESIS */
`define FPATH(X) `"data/X`"
`endif  /* ! SYNTHESIS */

module controller #(
    parameter PROGRAM_FILE="program.mem",
    parameter PRIVATE_REG_WIDTH=16,  // number of bits per private register
    parameter PRIVATE_REG_COUNT=16,  // number of registers in the controller
    parameter INSTRUCTION_WIDTH=32,  // number of bits per instruction
    parameter INSTRUCTION_COUNT=512, // number of instructions in the program
    parameter DATA_CACHE_WIDTH=16,   // number of bits per fixed-point number
    parameter DATA_CACHE_DEPTH=4096  // number of addresses in the data cache
) (
    input wire clk_in,
    input wire rst_in,
    output logic [0:INSTRUCTION_WIDTH-1] instr_out, // instruction to send to memory
    output logic instr_valid_for_memory_out
);
    
    // CONTROLLER ------------------------------------------------------------
    //
    //     The controller orchestrates all other modules in order to execute
    //     the program. The program comes in the form of ISA instructions
    //     compiled in a BRAM; see isa.py to generate ISA instructions. The
    //     BRAM takes a read pointer called "instruction_index" that is the
    //     line of code currently being executed in the controller. By default,
    //     the instruction_index is incremented each line, but branch and jump
    //     instructions allow for conditional control flow. Additionally, the
    //     controller has a small private buffer of 16 registers with 16 bits
    //     each, designated for program-specific logic, such as loops.
    //
    //     ISA:
    //         - 4'b0000: 
    //         - 4'b0100: LOAD(a_addr, data)                    // put 16 bits into data_cache at a_addr
    //
    //     Number of unique ISA instructions: 11
    //
    // -----------------------------------------------------------------------


    // The controller is a state machine, with one state per command in the ISA.
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
        OP_LOADB   = 4'b1001,  // loadb(val, shuffle):
                               //    Load FMA buffer contents into the immediate addr in the data cache.
                               //    Shuffle is a SIMD description for how to rearrange the direct output before placing it in memory.
                               //       Shuffle is an immediate value of the form xxx, where x is in the set {0, 1, 2}.
                               //       The x's represent the -2, -1, 0 results of each FMA. Example:
                               //           shuffle = 002 means set memory address to "a a c" from the FMAs
                               //           shuffle = 120 means set memory address to "b c a" from the FMAs
                               //       Shuffle operates on the previous k results of each FMA independently.
                               //       The number k of past results is a parameter that we set to 3 for now.
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

    enum {
        IDLE=0,
        LOAD_INSTRUCTION=1,
        EXECUTE_INSTRUCTION=2
    } state;

    // Private registers
    logic [PRIVATE_REG_WIDTH-1:0] registers [0:PRIVATE_REG_COUNT-1];
    logic compare_reg;

    // Uncomment to track registers in GTKWave for debugging!
    logic [PRIVATE_REG_WIDTH-1:0] reg0, reg1, reg2, reg3, reg4, reg5, reg6, reg7; // 8 more not displayed
    assign reg0 = registers[0];
    assign reg1 = registers[1];
    assign reg2 = registers[2];
    assign reg3 = registers[3];
    assign reg4 = registers[4];
    assign reg5 = registers[5];
    assign reg6 = registers[6];
    assign reg7 = registers[7];

    // Instruction tracking
    localparam INSTRUCTION_DEPTH = $clog2(INSTRUCTION_COUNT);
    logic [0:INSTRUCTION_DEPTH-1] instruction_index;
    logic [0:INSTRUCTION_DEPTH-1] prefetching_index;
    logic [0:INSTRUCTION_WIDTH-1] current_instruction;
    logic [0:INSTRUCTION_WIDTH-1] prefetched_instruction;

    // Prefetch the next instruction, unless we are at the last instruction.
    assign prefetching_index = (instruction_index < INSTRUCTION_COUNT - 1) ? instruction_index + 1 : instruction_index;

    // Read-only instruction buffer RAM (compiled program source)
    xilinx_true_dual_port_read_first_2_clock_ram #(
        .RAM_WIDTH(INSTRUCTION_WIDTH),
        .RAM_DEPTH(INSTRUCTION_COUNT),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"),     // Select "HIGH_PERFORMANCE"
        .INIT_FILE(`FPATH(isa-matrix-mult.mem))  // Specify file to init RAM
    ) instruction_buffer (
        .clka(clk_in),                   // PORT 1
        .addra(instruction_index),       // Read address (current instruction)
        .douta(current_instruction),     // Output data (current instruction)
        .ena(state != IDLE),             // Enable RAM whenever the controller is not idle
        .regcea(1'b1),                   // Always enable output register for read-only RAM
        .wea(1'b0),                      // Never write from read-only RAM
        .dina(),                         // No input data
        .rsta(rst_in),                   // Reset wire

        .clkb(clk_in),                   // PORT 2
        .addrb(prefetching_index),       // Read address (prefetched instruction)
        .doutb(prefetched_instruction),  // Output data (prefetched instruction)
        .enb(state != IDLE),             // Enable RAM whenever the controller is not idle
        .regceb(1'b1),                   // Always enable output register for read-only RAM
        .web(1'b0),                      // Never write from read-only RAM
        .dinb(),                         // No input data
        .rstb(rst_in)                    // Reset wire
    );

    // Execute instructions
    logic instr_ready, just_used_prefetch;
    logic [0:INSTRUCTION_WIDTH-1] instr;
    assign instr = current_instruction; // redesign once we do prefetching
    assign instr_out = current_instruction;
    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            state <= LOAD_INSTRUCTION;
            instr_ready <= 0;
            instruction_index <= 0;
            just_used_prefetch <= 0;
            compare_reg <= 0;
            for (int i = 0; i < PRIVATE_REG_COUNT; i = i + 1) begin
                registers[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                end

                LOAD_INSTRUCTION: begin
                    // Two stage pipeline to allow for two cycle read on the BRAM.
                    // If the execution branches, it sets instr_ready to 0.
                    // TODO (LAKER): use prefetched instruction
                    instr_ready <= 1'b1;
                    if (instr_ready) begin
                        state <= EXECUTE_INSTRUCTION;
                        instruction_index <= instruction_index + 1'b1;
                        // TODO: if instr is not JUMP, prefetch next instruction
                        //       instr <= current_instruction;
                    end
                end

                EXECUTE_INSTRUCTION: begin
                    // Implement the ISA
                    case (instr[0:3])

                        // ------------------------------------------------------------------------
                        // | 4 bit op code | 4 bit reg | 16 bit immediate | 4 bit reg | 4 bit reg |
                        // ------------------------------------------------------------------------

                        OP_NOP: begin
                        end

                        OP_END: begin
                            state <= IDLE;
                            instruction_index <= 0;
                        end

                        OP_XOR: begin
                            registers[instr[4:7]] <= registers[instr[4:7]] ^ registers[instr[24:27]];
                        end

                        OP_ADDI: begin
                            registers[instr[4:7]] <= instr[8:23] + registers[instr[24:27]];
                        end

                        OP_BGE: begin
                            compare_reg <= registers[instr[4:7]] >= registers[instr[24:27]];
                        end

                        OP_JUMP: begin
                            if (compare_reg) begin
                                instr_ready <= 0; // force two-cycle read for new instruction_index
                                instruction_index <= instr[8:23];
                            end
                        end

                        default: begin
                            // Unrecognized instruction is NOP
                        end
                    endcase 

                    if (instr[0:3] != OP_END) begin
                        // If the instruction wasn't a jump, immediately execute the next instruction.
                        //if (instr[0:3] != OP_JUMP) begin
                        //    state <= EXECUTE_INSTRUCTION;
                        //    instr <= just_used_prefetch ? current_instruction : prefetched_instruction;
                        //    instruction_index <= instruction_index + 1;
                        //    // ^^^ won't work yet -- need to persist instr_index two cycles for BRAM
                        //end else begin
                        state <= LOAD_INSTRUCTION; // TEMP -- remove when using prefetching and instead directly go to next instruction
                        //end
                    end

                    // Tell other modules when their instructions are valid.
                    // 1. Memory (op code is NOP, SMA, LOADI, SENDL, LOADB, or WRITEB)
                    // 2. HDMI (to be implemented)
                    instr_valid_for_memory_out <= (
                        instr[0:3] == OP_NOP   || instr[0:3] == OP_SMA    ||
                        instr[0:3] == OP_LOADI || instr[0:3] == OP_SENDL  || 
                        instr[0:3] == OP_LOADB || instr[0:3] == OP_WRITEB
                    );
                end

                default: begin
                end
            endcase
        end
    end

endmodule

`default_nettype wire
