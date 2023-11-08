`timescale 1ns / 1ps
`default_nettype none

module fma_memory_buffer #(
    parameter FMA_COUNT = 2,  // number of FMAs to prepare data for in a simultaneous read
    parameter WIDTH = 16      // number of bits per number going into the FMA
) (
    input wire clk_in,
    input wire rst_in,
    input wire [FMA_COUNT * (3*WIDTH) - 1 : 0] abc_in,
    input wire [FMA_COUNT * 3 - 1 : 0] abc_valid_in,
    output logic [FMA_COUNT * (3*WIDTH) - 1 : 0] abc_out,
    output logic [FMA_COUNT - 1 : 0] c_valid_out,
    output logic abc_valid_out 
);

    //  FMA MEMORY BUFFER
    //
    //     The memory buffer provides an interface for simultaneous reads for the FMA blocks.
    //     The memory buffer receives data from the data cache, which the controller commands.
    //     Even though the data cache possibly only sends sequential information, the memory buffer 
    //     prepares a unified output for FMA units to read all at once.
    //     
    //     Inputs:
    //       abc_in: contiguous array of length FMA_COUNT, each element being three numbers "a b c"
    //       abc_valid_in: contiguous array of length FMA_COUNT, each element being three booleans "a_valid b_valid c_valid"
    //
    //     Example:
    //       For FMA_COUNT=2, WIDTH=3, abc_in would be, bit by bit,
    //         [c_fma2, b_fma2, a_fma2, c_fma1, b_fma1, a_fma1]
    //
    //     Every cycle, the memory buffer saves whichever inputs are marked as valid.
    //     Once the "a" and "b" values of every FMA have been marked as valid, the overall
    //     fma_valid_out flag goes high for one cycle. Every FMA connected to the
    //     memory buffer must read at this cycle.
    //
    //     By default, FMAs reuse their old "c" value. The reason is to allow simple chained dot products.
    //     If the controller chooses to overwrite the "c" value for FMA i, it must set the final bit of
    //     abc_valid_in[i] to 1. Then the memory buffer will set c_valid_out[i] to 1. When FMAs read,
    //     they do not write in the "c" value from abc_out unless c_valid_out[i] is 1.
    //     
    //     Outputs:
    //       abc_out: contiguous array of length FMA_COUNT, storing "a b c" for FMAs to read upon abc_valid_out high
    //       c_valid_out: contiguous array of length FMA_COUNT, storing whether each FMA should read the "c" value or use its old "c" value
    //       abc_valid_out: boolean that goes high when every FMA's input is ready to be read

    // Store fixed-point numbers to write into the a, b, and c wires of each FMA.
    logic [FMA_COUNT * (3*WIDTH) - 1 : 0] abc;
    // Store one-bit flags for whether c values should overwrite in the FMAs,
    // and for each FMA, whether its input has been prepared correctly from the BRAM.
    logic [FMA_COUNT - 1 : 0] c_valid, fma_prepared;

    enum {FILLING=0, WRITING=1} state;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            state <= FILLING;
            abc_valid_out <= 0;
            // Zero out all arrays, including the contiguous 1D arrays abc and abc_out
            for (int fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin
                c_valid[fma_id] <= 0;
                c_valid_out[fma_id] <= 0;
                fma_prepared[fma_id] <= 0;
                for (int bit_index = 0; bit_index < 3*WIDTH; bit_index = bit_index + 1) begin
                    abc[fma_id * 3*WIDTH + bit_index] <= 0;
                    abc_out[fma_id * 3*WIDTH + bit_index] <= 0;
                end
            end
        end else begin
            case (state)
                FILLING: begin
                    for (int fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin
                        // Set c_valid to the 3rd bit of the FMA's three valid_in bits
                        if (abc_valid_in[fma_id*3 + 2]) begin
                            c_valid[fma_id] <= 1'b1;
                        end
                        // Set fma_prepared if both a_valid and b_valid are high for an FMA
                        if (abc_valid_in[fma_id*3] && abc_valid_in[fma_id*3 + 1]) begin
                            fma_prepared[fma_id] <= 1'b1;
                        end
                        // Set the values of abc to the new input if valid signals are high
                        for (int i = 0; i < WIDTH; i = i + 1) begin
                            // loop through [0, 1, 2] to set a, b, c values based on abc_valid_in
                            for (int abc_index = 0; abc_index < 3; abc_index = abc_index + 1) begin
                                if (abc_valid_in[fma_id*3 + abc_index]) begin
                                    abc[fma_id * 3*WIDTH + abc_index*WIDTH + i] <= abc_in[fma_id * 3*WIDTH + abc_index*WIDTH + i];
                                end
                            end
                        end
                    end

                    // Check whether fma_prepared is all ones. The syntax '1 is
                    // called "filling" and will expand to the size of fma_prepared.
                    if (fma_prepared == '1) begin 
                        state <= WRITING;
                        abc_valid_out <= 1;
                        // Place abc values on abc_out and c_valid values on c_valid_out
                        for (int fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin
                            c_valid_out[fma_id] <= c_valid[fma_id];
                            for (int i = 0; i < 3*WIDTH; i = i + 1) begin
                                abc_out[fma_id * 3*WIDTH + i] <= abc[fma_id * 3*WIDTH + i];
                            end
                        end
                    end
                end

                WRITING: begin
                    // Assume abc_valid_out has just gone high. Reset everything.
                    state <= FILLING;
                    abc_valid_out <= 0;
                    for (int fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin
                        c_valid[fma_id] <= 0;
                        fma_prepared[fma_id] <= 0;
                        for (int i = 0; i < 3*WIDTH; i = i + 1) begin
                            abc[fma_id * 3*WIDTH + i] <= 0;
                        end
                    end
                end

                default: begin
                    state <= FILLING;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
