`timescale 1ns / 1ps
`default_nettype none

module scale(
  input wire [1:0] scale_in,
  input wire [10:0] hcount_in,
  input wire [9:0] vcount_in,
  output logic [10:0] scaled_hcount_out,
  output logic [9:0] scaled_vcount_out,
  output logic valid_addr_out
);
    always_comb begin
      case(scale_in)
        2'b00: begin
          scaled_hcount_out = hcount_in;
          scaled_vcount_out = vcount_in;
        end

        2'b01: begin // Undefined behavior, passing through input values
          scaled_hcount_out = hcount_in;
          scaled_vcount_out = vcount_in;
        end

        2'b10: begin
          scaled_hcount_out = hcount_in >> 2;
          scaled_vcount_out = vcount_in >> 1;
        end

        2'b11: begin
          scaled_hcount_out = hcount_in >> 1;
          scaled_vcount_out = vcount_in >> 1;
        end

        default: begin
          scaled_hcount_out = hcount_in;
          scaled_vcount_out = vcount_in;
        end
      endcase
    end

    assign valid_addr_out = (scaled_hcount_out < 240) && (scaled_vcount_out < 320);

  //always just default to scale 1
  //(you need to update/modify this to spec)!
  //assign scaled_hcount_out = hcount_in >> ((scale_in & 2'b10) - (scale_in & 2'b01));
  //assign scaled_vcount_out = vcount_in >> ((scale_in & 2'b10) >> 1'b1);
  //assign valid_addr_out = scaled_hcount_out < 240 && scaled_vcount_out < 320;

endmodule


`default_nettype wire

