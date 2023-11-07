`timescale 1ns / 1ps
`default_nettype none

module shared_memory #(
    parameter FMA_COUNT = 2,
    parameter WIDTH = 16,
    parameter ADDR_DEPTH = 13 // number of bits required to specify the data cache address 10 kb in the data cache
) (
    input wire clk_in,
    input wire rst_in,
    input wire [3 * WIDTH - 1 : 0] data_in [FMA_COUNT-1 : 0],
    input wire [2 : 0] data_in_valid [FMA_COUNT - 1 : 0],
    output logic [3 * WIDTH - 1 : 0] fma_out [FMA_COUNT-1 : 0],
    output logic [2 : 0] fma_out_valid [FMA_COUNT - 1 : 0] // a, b, c, all need valid_in 's
);

logic [3 * WIDTH - 1 : 0] data [FMA_COUNT-1 : 0];
logic [2 : 0] data_valid [FMA_COUNT - 1 : 0];
logic [1 : 0] filled; // 11 if all slots are filled

always_ff @(posedge clk_in) begin
    if (rst_in) begin
        for (int i = 0; i < FMA_COUNT; i = i + 1) begin
            fma_out_valid[i] <= 3'b0;
            data[i] <= 48'b0; // 
        end
        filled <= 2'b1;
    end
    else begin
        if (filled == 2'b11) begin
            for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                fma_out[i] <= data[i];
                fma_out_valid[i] <= 3'b111;
            end
            filled <= 2'b1;
        end
        else begin
            for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                data_valid[i] <= data_in_valid[i];
                case (data_in_valid[i])
                    3'b001: data[i] <= {data[i][47:16], data_in[i][15:0]};
                    3'b010: data[i] <= {data[i][47:32], data_in[i][31:16], data[i][15:0]};
                    3'b100: data[i] <= {data_in[i][47:32], data[i][31:0]};
                    3'b011: data[i] <= {data[i][47:32], data_in[i][31:0]};
                    3'b101: data[i] <= {data_in[i][47:32], data[i][31:16], data_in[i][15:0]};
                    3'b110: data[i] <= {data_in[i][47:16], data[i][15:0]};
                    3'b111: data[i] <= data_in[i];
                    default: data[i] <= data[i];
                endcase
            end
            filled[1] <= 1'b1;
            for (int i = 0; i < FMA_COUNT; i = i + 1) begin
                if (data_valid[i] != 3'b111) begin
                    filled[0] <= 1'b0;
                end
            end
        end
    end
end


endmodule

`default_nettype wire