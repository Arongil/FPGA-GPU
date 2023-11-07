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
    output logic [3 * WIDTH - 1 : 0] abc_out [FMA_COUNT - 1 : 0],
    output logic c_valid_out [FMA_COUNT - 1 : 0],
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
    //       abc_in: array of length FMA_COUNT, each element being three numbers "a b c"
    //       abc_valid_in: array of length FMA_COUNT, each element being three booleans "a_valid b_valid c_valid"
    //
    //     Every cycle, the memory buffer saves whichever inputs are marked as valid.
    //     Once the "a" and "b" values of every FMA are marked as valid, the overall
    //     fma_valid_out flag goes high for one cycle. Every FMA connected to the
    //     memory buffer must read at this cycle.
    //
    //     By default, FMAs reuse their old "c" value. The reason is to allow simple chained dot products.
    //     If the controller chooses to overwrite the "c" value for FMA i, it must set the final bit of
    //     abc_valid_in[i] to 1. Then the memory buffer will set c_valid_out[i] to 1. When FMAs read,
    //     they do not write in the "c" value from fma_out unless c_valid_out[i] is 1.
    //     
    //     Outputs:
    //       abc_out: array of length FMA_COUNT, storing "a b c" for FMAs to read upon abc_valid_out high
    //       c_valid_out: array of length FMA_COUNT, storing whether each FMA should read the "c" value or use its old "c" value
    //       abc_valid_out: boolean that goes high when every FMA's input is ready to be read

    // Store fixed-point numbers to write into the a, b, and c wires of each FMA.
    logic [3 * WIDTH - 1 : 0] abc [FMA_COUNT - 1 : 0];
    // Store one-bit flags for whether c values should overwrite in the FMAs,
    // and for each FMA, whether its input has been prepared correctly from the BRAM.
    logic [FMA_COUNT - 1 : 0] c_valid, fma_prepared;

    enum {FILLING=0, WRITING=1} state;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            state <= FILLING;
            abc_valid_out <= 0;
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
                        abc_out <= abc;
                        c_valid_out <= c_valid;
                        abc_valid_out <= 1;
                    end
                end

                OUTPUTTING: begin
                    // Assume abc_valid_out has just gone high. Reset everything.
                    state <= FILLING;
                    abc_valid_out <= 0;
                    for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                        c_valid[i] <= 0;
                        fma_prepared[i] <= 0;
                        abc[i] <= 48'b0; 
                    end
                end

                default: begin
                    state <= FILLING;
                    abc_valid_out <= 0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
