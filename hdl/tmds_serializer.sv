`timescale 1ns / 1ps
`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module tmds_serializer (
    input wire clk_pixel_in,
    input wire clk_5x_in,
    input wire rst_in,
    input wire [9:0] tmds_in,
    output logic tmds_out
);
  logic [1:0] linker;

  // this is requried for OSERDESE2 to work
  logic pwup_rst = 1'b1;
  always @(posedge clk_pixel_in)begin
      pwup_rst <= 1'b0;
  end

  OSERDESE2 #(
      .DATA_RATE_OQ("DDR"),
      .DATA_RATE_TQ("SDR"),
      .DATA_WIDTH(10),
      .SERDES_MODE("MASTER"),
      .TRISTATE_WIDTH(1),
      .TBYTE_CTL("FALSE"),
      .TBYTE_SRC("FALSE")
  ) primary (
      .OQ(tmds_out),
      .OFB(),
      .TQ(),
      .TFB(),
      .SHIFTOUT1(),
      .SHIFTOUT2(),
      .TBYTEOUT(),
      .CLK(clk_5x_in),
      .CLKDIV(clk_pixel_in),
      .D1(tmds_in[0]),
      .D2(tmds_in[1]),
      .D3(tmds_in[2]),
      .D4(tmds_in[3]),
      .D5(tmds_in[4]),
      .D6(tmds_in[5]),
      .D7(tmds_in[6]),
      .D8(tmds_in[7]),
      .TCE(1'b0),
      .OCE(1'b1),
      .TBYTEIN(1'b0),
      .RST(rst_in || pwup_rst),
      .SHIFTIN1(linker[0]),
      .SHIFTIN2(linker[1]),
      .T1(1'b0),
      .T2(1'b0),
      .T3(1'b0),
      .T4(1'b0)
  );
  OSERDESE2 #(
      .DATA_RATE_OQ("DDR"),
      .DATA_RATE_TQ("SDR"),
      .DATA_WIDTH(10),
      .SERDES_MODE("SLAVE"),
      .TRISTATE_WIDTH(1),
      .TBYTE_CTL("FALSE"),
      .TBYTE_SRC("FALSE")
  ) secondary (
      .OQ(),
      .OFB(),
      .TQ(),
      .TFB(),
      .SHIFTOUT1(linker[0]),
      .SHIFTOUT2(linker[1]),
      .TBYTEOUT(),
      .CLK(clk_5x_in),
      .CLKDIV(clk_pixel_in),
      .D1(1'b0),
      .D2(1'b0),
      .D3(tmds_in[8]),
      .D4(tmds_in[9]),
      .D5(1'b0),
      .D6(1'b0),
      .D7(1'b0),
      .D8(1'b0),
      .TCE(1'b0),
      .OCE(1'b1),
      .TBYTEIN(1'b0),
      .RST(rst_in || pwup_rst),
      .SHIFTIN1(1'b0),
      .SHIFTIN2(1'b0),
      .T1(1'b0),
      .T2(1'b0),
      .T3(1'b0),
      .T4(1'b0)
  );
endmodule

`default_nettype wire
