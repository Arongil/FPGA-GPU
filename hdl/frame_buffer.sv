`timescale 1ns / 1ps
`default_nettype none

// Adapted from Labs 5 and 6, the dual frame buffer holds two BRAMs:
// one that receives data from the GPU, another that presents data to HDMI.
module frame_buffer #(
    parameter FMA_COUNT=2,
    parameter ITERS_BITS=4, // how many bits we store for iterations until divergence in Mandelbrot calculations
    parameter WIDTH=320,
    parameter HEIGHT=320
) (
    input wire sys_clk_in,
    input wire hdmi_clk_in,
    input wire rst_in,
    input wire mandelbrot_iters_valid_in,
    input wire [FMA_COUNT*ITERS_BITS-1:0] mandelbrot_iters_in,
    input wire [$clog2(WIDTH*HEIGHT)-1:0]  addr_write_in,
    input wire [$clog2(1280)-1:0]  x_draw_in,
    input wire [$clog2(720)-1:0] y_draw_in,
    input wire swap_in, // high for one cycle if we should swap whether GPU writes to BRAM A or B
    output logic [7:0] red_out,
    output logic [7:0] green_out,
    output logic [7:0] blue_out,
    output logic GPU_writing_to_BRAM_A_out // TEMP TEMP TEMP
);

    // There are two BRAMS, A and B. At first, the GPU writes to BRAM A
    // while HDMI reads from BRAM B. Then, they switch. Repeat.
    // Technically there is one shared BRAM, so we translate
    // by WIDTH*HEIGHT to refer to the second BRAM.
    logic GPU_writing_to_BRAM_A; // high if GPU is writing to BRAM A
    assign GPU_writing_to_BRAM_A_out = GPU_writing_to_BRAM_A;
    always_ff @(posedge sys_clk_in) begin
        if (rst_in) begin
            GPU_writing_to_BRAM_A <= 1;
        end else if (swap_in) begin
            GPU_writing_to_BRAM_A <= swap_in ? !GPU_writing_to_BRAM_A : GPU_writing_to_BRAM_A;
        end
    end

    // Set clock to system clock if GPU is writing, else HDMI clock.
    logic clock_a, clock_b;
    assign clock_a = GPU_writing_to_BRAM_A ? sys_clk_in : hdmi_clk_in;
    assign clock_b = !GPU_writing_to_BRAM_A ? sys_clk_in : hdmi_clk_in;

    // Enable write if GPU is writing to that BRAM.
    logic write_enable_a, write_enable_b;
    assign write_enable_a = GPU_writing_to_BRAM_A;
    assign write_enable_b = !GPU_writing_to_BRAM_A;

    // Set read enable to opposite of write enable.
    logic read_enable_a, read_enable_b;
    assign read_enable_a = !write_enable_a;
    assign read_enable_b = !write_enable_b;

    // Set output data to come from the BRAM to which the GPU is not writing.
    logic [ITERS_BITS-1:0] out_a;
    logic [ITERS_BITS-1:0] out_b;
    logic [ITERS_BITS-1:0] iters_out;
    assign iters_out = !GPU_writing_to_BRAM_A ? out_a : out_b;

    // Set the output color as a gradient according to the iteration count (0-15).
    logic [16*8-1:0] red_gradient = {8'd66, 8'd25, 8'd9, 8'd4, 8'd0, 8'd12, 8'd24, 8'd57, 8'd134, 8'd211, 8'd241, 8'd248, 8'd255, 8'd204, 8'd153, 8'd0};
    logic [16*8-1:0] green_gradient = {8'd30, 8'd7, 8'd1, 8'd4, 8'd7, 8'd44, 8'd82, 8'd125, 8'd181, 8'd236, 8'd233, 8'd201, 8'd170, 8'd128, 8'd87, 8'd0};
    logic [16*8-1:0] blue_gradient = {8'd15, 8'd26, 8'd47, 8'd73, 8'd100, 8'd138, 8'd177, 8'd209, 8'd229, 8'd248, 8'd191, 8'd95, 8'd0, 8'd0, 8'd0, 8'd0};

    always_comb begin
        if (x_draw_in < WIDTH && y_draw_in < HEIGHT) begin
            // Color in-bounds pixels on a gradient according to how long it took to diverge in the Mandelbrot set. If it never diverged, color it black!
            red_out = red_gradient[16*8 - 8*(iters_out+1) +: 8];
            green_out = green_gradient[16*8 - 8*(iters_out+1) +: 8];
            blue_out = blue_gradient[16*8 - 8*(iters_out+1) +: 8];
        end else begin
            // Color out-of-bounds pixels black.
            red_out = 8'b0;
            green_out = 8'b0;
            blue_out = 8'b0;
        end
    end

    // Write data from GPU into memory. Because the GPU sends data in batches of FMA_COUNT,
    // we enter a finite state machine to write the values one-by-one until we are done.
    logic writing_iters_flag;
    logic [$clog2(FMA_COUNT)-1:0] iters_index;
    logic [FMA_COUNT*ITERS_BITS-1:0] mandelbrot_iters_buffer;
    logic [ITERS_BITS-1:0] iters_to_write;

    // Define the FSM that writes each iters value sequentially.
    always_ff @(posedge sys_clk_in) begin
        if (rst_in) begin
            writing_iters_flag <= 0;
            iters_index <= 0;
            mandelbrot_iters_buffer <= 0;
            iters_to_write <= 0;
        end else begin
            // Store the Mandelbrot iters when it comes!
            if (mandelbrot_iters_valid_in) begin
                mandelbrot_iters_buffer <= mandelbrot_iters_in;
                writing_iters_flag <= 1;
            end

            // Once we receive Mandelbrot iters, write its values one by one.
            if (writing_iters_flag) begin
                // Increment iters_index. The final time, it will reset to 0.
                iters_index <= iters_index + 1;
                // If we are on the last iters, reset the writing flag.
                writing_iters_flag <= iters_index != FMA_COUNT - 1;
                // Tell the BRAM which iters to write in.
                iters_to_write <= mandelbrot_iters_buffer[ITERS_BITS*FMA_COUNT - (iters_index+1)*ITERS_BITS +: ITERS_BITS];
            end
        end
    end

    // Increment the address that the GPU writes to after each iters that we write.
    logic [$clog2(2*WIDTH*HEIGHT)-1:0] addr_write_GPU, addr_read_HDMI;
    assign addr_write_GPU = addr_write_in + iters_index;
    assign addr_read_HDMI = x_draw_in * HEIGHT + y_draw_in; // col-major
    
    logic [$clog2(2*WIDTH*HEIGHT)-1:0] addr_a, addr_b;
    assign addr_a = GPU_writing_to_BRAM_A ? addr_write_GPU : addr_read_HDMI;
    assign addr_b = !GPU_writing_to_BRAM_A ? addr_write_GPU : addr_read_HDMI;

    // We use a dual port BRAM to represent the dual frame buffer.
    // Input A and Input B point to the first or second half of the BRAM,
    // and when frame_select changes, the halves that they point to switch.
    xilinx_true_dual_port_read_first_2_clock_ram #(
        .RAM_WIDTH(ITERS_BITS),                        // Specify RAM data width
        .RAM_DEPTH(2*WIDTH*HEIGHT),       // Specify RAM depth (number of entries)
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
        .INIT_FILE("")                        // Specify name/location of RAM initialization file if using one (leave blank if not)
    ) memory_BRAM (
        .addra(addr_a),         // Port A address bus, width determined from RAM_DEPTH
        .dina(iters_to_write),  // Port A RAM input data, width determined from RAM_WIDTH
        .clka(clock_a),         // Port A clock
        .wea(write_enable_a),   // Port A write enable
        .regcea(read_enable_a), // Port A output register enable
        .douta(out_a),          // Port A RAM output data, width determined from RAM_WIDTH
        .ena(1'b1),             // Port A RAM Enable, for additional power savings, disable port when not in use
        .rsta(1'b0),            // Port A output reset (does not affect memory contents)

        .addrb(addr_b + WIDTH*HEIGHT),   // Port B address bus, width determined from RAM_DEPTH [shift by WIDTH*HEIGHT to separate the two halves of the BRAM]
        .dinb(iters_to_write),  // Port B RAM input data, width determined from RAM_WIDTH
        .clkb(clock_b),         // Port B clock
        .web(write_enable_b),   // Port B write enable
        .regceb(read_enable_b), // Port B output register enable
        .doutb(out_b),          // Port B RAM output data, width determined from RAM_WIDTH
        .enb(1'b1),             // Port B RAM Enable, for additional power savings, disable port when not in use
        .rstb(1'b0)             // Port B output reset (does not affect memory contents)
    );
    endmodule

    `default_nettype none
