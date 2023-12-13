python isa.py data/mandelbrot.txt
iverilog -g2012 -o sim.out sim/top_level_tb.sv hdl/controller.sv hdl/fma_memory_buffer.sv hdl/fma_write_buffer.sv hdl/fma.sv hdl/memory.sv hdl/xilinx_true_dual_port_read_first_2_clock_ram.v
vvp sim.out
