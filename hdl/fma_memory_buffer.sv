`timescale 1ns / 1ps
`default_nettype none

module fma_memory_buffer #(
    parameter FMA_COUNT = 2,  // number of FMAs to prepare data for in a simultaneous read
    parameter WIDTH = 16      // number of bits per number going into the FMA
) (
    input wire clk_in,
    input wire rst_in,
    input wire [3 * WIDTH - 1 : 0] abc_in [FMA_COUNT-1 : 0],  // for each FMA i, abc_in[i] is laid out as "a b c" 
    input wire [3 - 1 : 0] abc_valid_in [FMA_COUNT - 1 : 0],
    output logic [3 * WIDTH - 1 : 0] fma_out [FMA_COUNT - 1 : 0],
    output logic fma_c_valid [FMA_COUNT - 1 : 0],
    output logic fma_out_valid
);

    //  FMA MEMORY BUFFER
    //
    //     This module provides an interface for simultaneous reads for the FMA blocks.
    //     The memory controller module sets the inputs to the memory buffer,
    //     orchestrated by the controller. The memory controller is the interface to the
    //     data cache composed of BRAMs. This module receives possibly sequential information
    //     from the memory controller, preparing a unified output to all FMA units at once.
    //     
    //     Inputs:
    //       abc_in: array of length FMA_COUNT, each element being three numbers "a b c"
    //       abc_valid_in: array of length FMA_COUNT, each element being three booleans "a_valid b_valid c_valid"
    //
    //     Every cycle, the memory buffer saves whichever inputs are marked as valid.
    //     Once the "a" and "b" values of every FMA are marked as valid, the overall
    //     fma_valid_out flag goes high for one cycle. Every FMA connected to the
    //     memory buffer must read at this cycle.
    //     
    //     Outputs:
    //       fma_out: array of length FMA_COUNT, storing all numbers for FMAs to read upon fma_out_valid high
    //       fma_c_valid: array of length FMA_COUNT, storing whether each FMA should read the "c" value or use its old "c" value
    //       fma_out_valid: boolean that goes high when every FMA's input is ready to be read

    // Store fixed-point numbers to write into the a, b, and c wires of each FMA.
    logic [3 * WIDTH - 1 : 0] abc [FMA_COUNT - 1 : 0];
    // Store one-bit flags for whether c values should overwrite in the FMAs,
    // and for each FMA, whether its input has been prepared correctly from the BRAM.
    logic [FMA_COUNT - 1 : 0] c_valid, fma_prepared;
    logic valid_out;

    enum {FILLING=0, WRITING=1} state;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            state <= FILLING;
            valid_out <= 0;
            for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                c_valid[i] <= 0;
                fma_prepared[i] <= 0;
                abc[i] <= 48'b0; 
            end
        end else begin
            case (state)
                FILLING: begin
                    for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                        c_valid[i] <= (abc_valid_in[i] & 3'b001) == 3'b001;
                        fma_prepared[i] <= (abc_valid_in[i] & 3'b110) == 3'b110;
                        case (abc_valid_in[i])
                            3'b000: abc[i] <= abc[i];
                            3'b001: abc[i] <= {abc[i][47:16], abc_in[i][15:0]};
                            3'b010: abc[i] <= {abc[i][47:32], abc_in[i][31:16], abc[i][15:0]};
                            3'b100: abc[i] <= {abc_in[i][47:32], abc[i][31:0]};
                            3'b011: abc[i] <= {abc[i][47:32], abc_in[i][31:0]};
                            3'b101: abc[i] <= {abc_in[i][47:32], abc[i][31:16], abc_in[i][15:0]};
                            3'b110: abc[i] <= {abc_in[i][47:16], abc[i][15:0]};
                            3'b111: abc[i] <= abc_in[i];
                            default: abc[i] <= abc[i];
                        endcase
                    end
                    if (fma_prepared + 1 == 0) begin // Check whether fma_prepared is all 1's.
                        state <= OUTPUTTING;
                        valid_out <= 1;
                    end
                end

                OUTPUTTING: begin
                    // Assume valid_out has just gone high. Reset everything.
                    state <= FILLING;
                    valid_out <= 0;
                    for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                        c_valid[i] <= 0;
                        fma_prepared[i] <= 0;
                        abc[i] <= 48'b0; 
                    end
                end

                default: begin
                    state <= FILLING;
                    valid_out <= 0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
