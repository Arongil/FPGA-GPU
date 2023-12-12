`timescale 1ns / 1ps
`default_nettype none

module top_level(
  input wire clk_100mhz, // 100 MHz clock
  input wire [15:0] sw, // all 16 input slide switches
  input wire [3:0] btn, // all four momentary button switches
  output logic [15:0] led, // 16 green output LEDs (located right above switches)
  output logic [2:0] rgb0, // rgb led
  output logic [2:0] rgb1, // rgb led
  output logic [2:0] hdmi_tx_p, // hdmi output signals (blue, green, red)
  output logic [2:0] hdmi_tx_n, // hdmi output signals (negatives)
  output logic hdmi_clk_p, hdmi_clk_n, // differential hdmi clock

  output logic [6:0] ss0_c,
  output logic [6:0] ss1_c,
  output logic [3:0] ss0_an,
  output logic [3:0] ss1_an,

  input wire [7:0] pmoda,
  input wire [2:0] pmodb,
  output logic pmodbclk,
  output logic pmodblock
);

    assign led = sw; // set green LEDs to flip on with switches
    assign rgb1 = 0; // turn off rgb LEDs (active high)
    assign rgb0 = 0; // turn off rgb LEDs (active high)

    // Set system reset to button 0
    logic sys_rst;
    assign sys_rst = btn[0];

    // START HDMI SETUP

    // Clocking variables
    logic clk_pixel, clk_5x;
    logic locked;

    // Clock manager: creates 74.25 MHz and 5 times 74.25 MHz for pixel and TMDS
    hdmi_clk_wiz_720p mhdmicw (
        .clk_pixel(clk_pixel),
        .clk_tmds(clk_5x),
        .reset(0),
        .locked(locked),
        .clk_ref(clk_100mhz)
    );

    // Signals to drive the video pipeline
    logic [10:0] hcount;
    logic [9:0] vcount;
    logic vert_sync;
    logic hor_sync;
    logic active_draw;
    logic new_frame;
    logic [5:0] frame_count;

    // Drive the video pipeline
    video_sig_gen mvg(
        .clk_pixel_in(clk_pixel),
        .rst_in(sys_rst),
        .hcount_out(hcount),
        .vcount_out(vcount),
        .vs_out(vert_sync),
        .hs_out(hor_sync),
        .ad_out(active_draw),
        .nf_out(new_frame),
        .fc_out(frame_count)
    );

    logic [7:0] img_red, img_green, img_blue;
    logic [7:0] red, green, blue;
    assign red = img_red;
    assign green = img_green;
    assign blue = img_blue;

    // TMDS signals
    logic [9:0] tmds_10b [0:2]; // output of each TMDS encoder
    logic tmds_signal [2:0];    // output of each TMDS serializer

    // Three TMDS encoders: red, green, blue.
    // Blue should have vert_sync, hor_sync for control signals
    // Red and green have nothing
    tmds_encoder tmds_red(
        .clk_in(clk_pixel),
        .rst_in(sys_rst),
        .data_in(red),
        .control_in(2'b0),
        .ve_in(active_draw),
        .tmds_out(tmds_10b[2])
    );

    tmds_encoder tmds_green(
        .clk_in(clk_pixel),
        .rst_in(sys_rst),
        .data_in(green),
        .control_in(2'b0),
        .ve_in(active_draw),
        .tmds_out(tmds_10b[1])
    );

    tmds_encoder tmds_blue(
        .clk_in(clk_pixel),
        .rst_in(sys_rst),
        .data_in(blue),
        .control_in({vert_sync,hor_sync}),
        .ve_in(active_draw),
        .tmds_out(tmds_10b[0])
    );

    // Three TMDS serializers (red, green, blue)
    tmds_serializer red_ser(
        .clk_pixel_in(clk_pixel),
        .clk_5x_in(clk_5x),
        .rst_in(sys_rst),
        .tmds_in(tmds_10b[2]),
        .tmds_out(tmds_signal[2])
    );

    tmds_serializer green_ser(
        .clk_pixel_in(clk_pixel),
        .clk_5x_in(clk_5x),
        .rst_in(sys_rst),
        .tmds_in(tmds_10b[1]),
        .tmds_out(tmds_signal[1])
    );

    tmds_serializer blue_ser(
        .clk_pixel_in(clk_pixel),
        .clk_5x_in(clk_5x),
        .rst_in(sys_rst),
        .tmds_in(tmds_10b[0]),
        .tmds_out(tmds_signal[0])
    );

    // Output buffers generating differential signal
    OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
    OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
    OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
    OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));

    assign ss0_c = 0; //ss_c; //control upper four digit's cathodes!
    assign ss1_c = 0; //ss_c; //same as above but for lower four digits!

    // END HDMI SETUP

    // START GPU SETUP

    localparam PRIVATE_REG_WIDTH=16;
    localparam PRIVATE_REG_COUNT=16;
    localparam INSTRUCTION_WIDTH=32;
    localparam INSTRUCTION_COUNT=61;    // UPDATE TO MATCH PROGRAM_FILE!
    localparam DATA_CACHE_WIDTH=16;
    localparam DATA_CACHE_DEPTH=4096;

    localparam FIXED_POINT=10;
    localparam WORD_WIDTH=16;
    localparam LINE_WIDTH=96;
    localparam FMA_COUNT=2;

    localparam ADDR_LENGTH=$clog2(36000 / 96);

    // logics for FMAs
    logic [3*WORD_WIDTH-1:0] fma_abc_1, fma_abc_2;
    logic fma_c_valid_in_1, fma_c_valid_in_2;
    logic [WORD_WIDTH-1:0] fma_out_1, fma_out_2;
    logic fma_valid_out_1, fma_valid_out_2;

    // logics for fma write buffer
    logic [WORD_WIDTH*FMA_COUNT-1:0] write_buffer_fma_out;
    logic [FMA_COUNT-1:0] write_buffer_fma_valid_out;
    logic [3*WORD_WIDTH*FMA_COUNT-1:0] write_buffer_line_out;
    logic write_buffer_line_valid;

    // logics for memory
    logic [0:INSTRUCTION_WIDTH-1] memory_instr_in;
    logic memory_instr_valid_in;
    logic memory_idle_out;
    logic [LINE_WIDTH-1:0] memory_abc_out;
    logic memory_use_new_c_out;
    logic memory_fma_output_can_be_valid_out;
    logic memory_abc_valid_out;

    // logics for controller
    logic [WORD_WIDTH-1:0] controller_reg_a, controller_reg_b, controller_reg_c;

    // Instantiate 2 FMA blocks!
    fma #(
        .WIDTH(WORD_WIDTH),
        .FIXED_POINT(FIXED_POINT)
    ) fma1 (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),
        .abc(memory_abc_out[LINE_WIDTH - 1:LINE_WIDTH/2]),
        .valid_in(memory_abc_valid_out),
        .c_valid_in(memory_use_new_c_out),
        .output_can_be_valid_in(memory_fma_output_can_be_valid_out),
        .out(fma_out_1),
        .valid_out(fma_valid_out_1)
    );

    fma #(
        .WIDTH(WORD_WIDTH),
        .FIXED_POINT(FIXED_POINT)
    ) fma2 (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),
        .abc(memory_abc_out[LINE_WIDTH/2 - 1:0]),
        .valid_in(memory_abc_valid_out),
        .c_valid_in(memory_use_new_c_out),
        .output_can_be_valid_in(memory_fma_output_can_be_valid_out),
        .out(fma_out_2),
        .valid_out(fma_valid_out_2)
    );

    // Instantiate write buffer!
    fma_write_buffer #(
        .FMA_COUNT(FMA_COUNT),
        .WORD_WIDTH(WORD_WIDTH),
        .LINE_WIDTH(LINE_WIDTH)
    ) write_buffer (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),
        .fma_out(write_buffer_fma_out),
        .fma_valid_out(write_buffer_fma_valid_out),
        .line_out(write_buffer_line_out),
        .line_valid(write_buffer_line_valid)
    );

    // Instantiate memory module!
    memory #(
        .FMA_COUNT(FMA_COUNT),
        .WORD_WIDTH(WORD_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .ADDR_LENGTH(ADDR_LENGTH),
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH)
    ) main_memory (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),
        .controller_reg_a(controller_reg_a),
        .controller_reg_b(controller_reg_b),
        .controller_reg_c(controller_reg_c),
        .write_buffer_read_in(write_buffer_line_out),
        .write_buffer_valid_in(write_buffer_line_valid),
        .instr_in(memory_instr_in),
        .instr_valid_in(memory_instr_valid_in),
        .abc_out(memory_abc_out),
        .abc_valid_out(memory_abc_valid_out),
        .use_new_c_out(memory_use_new_c_out),
        .fma_output_can_be_valid_out(memory_fma_output_can_be_valid_out)
    );

    // Instantiate controller!
    controller #(
        .PROGRAM_FILE(),
        .PRIVATE_REG_WIDTH(PRIVATE_REG_WIDTH),
        .PRIVATE_REG_COUNT(PRIVATE_REG_COUNT),
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH),
        .INSTRUCTION_COUNT(INSTRUCTION_COUNT),
        .DATA_CACHE_WIDTH(DATA_CACHE_WIDTH),
        .DATA_CACHE_DEPTH(DATA_CACHE_DEPTH)
    ) controller_module (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),
        .instr_out(memory_instr_in),
        .reg_a_out(controller_reg_a),
        .reg_b_out(controller_reg_b),
        .reg_c_out(controller_reg_c),
        .instr_valid_for_memory_out(memory_instr_valid_in)
    );

    always_comb begin
        // Set FMA write buffer to wire up from every individual FMA
        write_buffer_fma_out = {fma_out_1, fma_out_2};
        write_buffer_fma_valid_out = {fma_valid_out_1, fma_valid_out_2};
    end

    // END GPU SETUP

endmodule // top_level

`default_nettype wire
