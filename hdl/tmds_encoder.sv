`timescale 1ns / 1ps
`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module tmds_encoder(
  input wire clk_in,
  input wire rst_in,
  input wire [7:0] data_in,    // video data (red, green or blue)
  input wire [1:0] control_in, // for blue set to {vs, hs}, else will be 0
  input wire ve_in,  // video data enable, to choose between control or video signal
  output logic [9:0] tmds_out
);
 
    logic [8:0] q_m;

    tm_choice mtm(
      .data_in(data_in),
      .qm_out(q_m));

    logic [3:0] num_1s_qm_07;
    logic [3:0] num_0s_qm_07;
    always_comb begin
        num_1s_qm_07 = q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] + q_m[5] + q_m[6] + q_m[7];
        num_0s_qm_07 = 4'd8 - num_1s_qm_07;
    end

    logic [4:0] tally; // running count of excess 1's
    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            tally <= 5'b0;
            tmds_out <= 10'b0;
        end else if (ve_in == 1'b0) begin
            tally <= 5'b0;
            case (control_in)
                2'b00: tmds_out <= 10'b1101010100;
                2'b01: tmds_out <= 10'b0010101011;
                2'b10: tmds_out <= 10'b0101010100;
                2'b11: tmds_out <= 10'b1010101011;
                default: tmds_out <= 10'b0;
            endcase
        end else begin
            if (tally == 5'b0 || num_1s_qm_07 == num_0s_qm_07) begin
                tmds_out[9] <= ~q_m[8];
                tmds_out[8] <= q_m[8];
                tmds_out[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                if (q_m[8] == 1'b0) begin
                    tally <= tally + (num_0s_qm_07 - num_1s_qm_07);
                end else begin
                    tally <= tally + (num_1s_qm_07 - num_0s_qm_07);
                end
            end else begin
                //   top line checks tally > 0, bottom line checks tally < 0
                //                  (want zeros)                  (want ones)
                if ((tally < 5'd16 && num_1s_qm_07 > num_0s_qm_07) ||
                    (tally > 5'd15 && num_0s_qm_07 > num_1s_qm_07)) begin
                    tmds_out[9] <= 1'b1;
                    tmds_out[8] <= q_m[8];
                    tmds_out[7:0] <= ~q_m[7:0];
                    tally <= tally + (2'd2)*q_m[8] + (num_0s_qm_07 - num_1s_qm_07);
                end else begin
                    tmds_out[9] <= 1'b0;
                    tmds_out[8] <= q_m[8];
                    tmds_out[7:0] <= q_m[7:0];
                    tally <= tally - (2'd2)*(!q_m[8]) + (num_1s_qm_07 - num_0s_qm_07);
                end
            end
        end
    end
 
endmodule
 
`default_nettype wire
