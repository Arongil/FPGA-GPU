module video_sig_gen
#(
  parameter ACTIVE_H_PIXELS = 1280,  // horizontal pixels in active region
  parameter H_FRONT_PORCH = 110,     // horizontal pixels in front porch
  parameter H_SYNC_WIDTH = 40,       // horizontal pixels in sync region
  parameter H_BACK_PORCH = 220,      // horizontal pixels in back porch
  parameter ACTIVE_LINES = 720,      // vertical pixels in active region
  parameter V_FRONT_PORCH = 5,       // vertical pixels in front porch
  parameter V_SYNC_WIDTH = 5,        // vertical pixels in sync region
  parameter V_BACK_PORCH = 20)       // vertical pixels in back porch
(
  input wire clk_pixel_in,  // 74.25 MHz
  input wire rst_in,
  output logic [$clog2(TOTAL_COLS)-1:0] hcount_out,  // horizontal pixel count
  output logic [$clog2(TOTAL_ROWS)-1:0] vcount_out,  // vertical pixel count
  output logic vs_out,  // high on vertical sync   (bottom of frame)
  output logic hs_out,  // high on horizontal sync (right of frame)
  output logic ad_out,  // high on active drawing region
  output logic nf_out,  // high on new frame for one clock cycle
  output logic [5:0] fc_out);  // current frame (0-59 inclusive)
 
  localparam TOTAL_COLS = ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH + H_BACK_PORCH;
  localparam TOTAL_ROWS = ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH + V_BACK_PORCH;
 
  logic rst_in_old;
  always_ff @(posedge clk_pixel_in) begin
      if (rst_in) begin
          hcount_out <= 0;
          vcount_out <= 0;
          vs_out <= 0;
          hs_out <= 0;
          ad_out <= 0;
          nf_out <= 0;
          fc_out <= 0;
          rst_in_old <= 1'b1;
      end else if (rst_in_old == 1'b1) begin
          rst_in_old <= 1'b0;
          ad_out <= 1'b1;
      end else begin
          hcount_out <= hcount_out < (TOTAL_COLS-1) ? hcount_out + 1 : 0;
          vcount_out <= hcount_out < (TOTAL_COLS-1) ? vcount_out : (vcount_out < (TOTAL_ROWS-1) ? vcount_out + 1 : 0);

          if (hcount_out == ACTIVE_H_PIXELS + H_FRONT_PORCH - 1) begin
              hs_out <= 1'b1;
          end else if (hcount_out == ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH - 1) begin
              hs_out <= 1'b0;
          end

          if (hcount_out == TOTAL_COLS-1 && vcount_out == ACTIVE_LINES + V_FRONT_PORCH - 1) begin
              vs_out <= 1'b1;
          end else if (hcount_out == TOTAL_COLS-1 && vcount_out == ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH - 1) begin
              vs_out <= 1'b0;
          end

          if (hcount_out == TOTAL_COLS-1 && (vcount_out == TOTAL_ROWS-1 || vcount_out < ACTIVE_LINES-1)) begin
              ad_out <= 1'b1;
          end else if (hcount_out == ACTIVE_H_PIXELS-1) begin
              ad_out <= 1'b0;
          end

          nf_out <= (hcount_out == ACTIVE_H_PIXELS-1 && vcount_out == ACTIVE_LINES);

          fc_out <= (hcount_out == ACTIVE_H_PIXELS-1 && vcount_out == ACTIVE_LINES) ? (fc_out + 6'd1) % 6'd60 : fc_out;
      end
  end
 
endmodule
