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
    input wire [FMA_COUNT - 1 : 0] phrase_in_num,
    output logic [WORD_WIDTH * FMA_COUNT * 3 - 1 : 0] line_out,
    output logic line_valid
);

    // Documentation and testbenching to be added soon

    localparam ADDR_LENGTH =  $clog2(36000 / (WORD_WIDTH * FMA_COUNT * 3));  // number of bits in a memory address, 36kb/(16 * 2 * 3) = 375
    logic [WORD_WIDTH - 1 : 0] phrase_prepared_one;
    logic [WORD_WIDTH - 1 : 0] phrase_prepared_two;
    logic [WORD_WIDTH - 1 : 0] phrase_prepared_three;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            line_valid <= 0;
            phrase_prepared_one <= 0;
            phrase_prepared_two <= 0;
            phrase_prepared_three <= 0;
            for (int c = 0; c < 3; c = c + 1) begin
                for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                    for (int j = 0; j < WORD_WIDTH; j = j + 1) begin
                        line_out[c * FMA_COUNT * WORD_WIDTH + i * FMA_COUNT + j] <= 0;
                    end
                end
            end
        end else begin
            if (phrase_in_num == 2'b1) begin
                for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                    if (fma_valid_out[i]) begin
                        for (int j = 0; j < WORD_WIDTH; j = j + 1) begin
                            line_out[i * WORD_WIDTH + j] <= fma_out[i * WORD_WIDTH + j];
                        end
                        phrase_prepared_one[i] <= 1;
                    end
                end
            end else if (phrase_in_num == 2'b10) begin
                for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                    if (fma_valid_out[i]) begin
                        for (int j = 0; j < WORD_WIDTH; j = j + 1) begin
                            line_out[1 * FMA_COUNT * WORD_WIDTH + i * WORD_WIDTH + j] <= fma_out[i * WORD_WIDTH + j];
                        end
                        phrase_prepared_two[i] <= 1;
                    end
                end
            end else if (phrase_in_num == 2'b11) begin
                for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                    if (fma_valid_out[i]) begin
                        for (int j = 0; j < WORD_WIDTH; j = j + 1) begin
                            line_out[2 * FMA_COUNT * WORD_WIDTH + i * WORD_WIDTH + j] <= fma_out[i * WORD_WIDTH + j];
                        end
                        phrase_prepared_three[i] <= 1;
                    end
                end
            end

            if ((phrase_prepared_one == '1) && (phrase_prepared_two == '1) && (phrase_prepared_three == '1)) begin
                line_valid <= 1;
            end

        end
    end

endmodule
