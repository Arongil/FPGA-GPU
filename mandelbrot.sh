python isa.py data/mandelbrot.txt
iverilog -g2012 -o sim.out sim/top_level_tb.sv hdl/*
vvp sim.out
