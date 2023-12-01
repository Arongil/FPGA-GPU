`timescale 1ns / 1ps
`default_nettype none

module fma_write_buffer #(
    parameter FMA_COUNT = 2,  // number of FMAs to prepare data for in a simultaneous read
    parameter WORD_WIDTH = 16,  // number of bits per number aka width of a word
    parameter LINE_WIDTH = 96  // width of a line, FMA_COUNT * 3 * WORD_WIDTH = 2 * 3 * 16
) (
    input wire clk_in,
    input wire rst_in,
    input wire [WORD_WIDTH * FMA_COUNT - 1 : 0] fma_out,
    input wire [FMA_COUNT - 1 : 0] fma_valid_out,
    output logic [3 * WORD_WIDTH * FMA_COUNT - 1 : 0] line_out,
    output logic line_valid
);

    // A "word" is a single number. A "phrase" is all FMA c outputs.

    localparam ADDR_LENGTH =  $clog2(36000 / (WORD_WIDTH * FMA_COUNT * 3));  // number of bits in a memory address, 36kb/(16 * 2 * 3) = 375
    logic [1:0] phrase_in;

    // All FMAs take one cycle to compute. Therefore,
    // when one FMA is ready to output we read from them
    // all -- increment_phrase goes high for one cycle.
    // The promise is that controller will set the "compute"
    // flag high for all FMAs on the same cycle, not out of sync.
    logic increment_phrase;
    assign increment_phrase = (fma_valid_out != 0);

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            line_valid <= 0;
            phrase_in <= 0;
            line_out <= 0;
        end else begin
            if (phrase_in != 2'b11) begin
                if (increment_phrase) begin
                    phrase_in <= phrase_in + 2'b01;
                    line_valid <= phrase_in == 2'b10;

                    // Set line_out and phrase_prepared across all three words.
                    for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                        // Assume every FMA is valid because at least one is.
                        for (int j = 0; j < WORD_WIDTH; j = j + 1) begin
                            line_out[phrase_in * FMA_COUNT * WORD_WIDTH + i * WORD_WIDTH + j] <= fma_out[i * WORD_WIDTH + j];
                        end
                    end
                end
            end else begin
                line_valid <= 0;

                // Reset phrase_in and line_out
                phrase_in <= 0;
                line_out <= 0;
            end

        end
    end

endmodule
