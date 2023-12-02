# FPGA-GPU
6.205 Final Project by Laker and Hanfei

## Steps to program the GPU

1. Write an assembly-style program (e.g., `matrix-mult.txt`)
2. Convert into machine code using `python isa.py <program_name.txt>`
3. Update the program file in BRAM initialization in `hdl/controller.sv`
4. Update the instruction count parameter when initializating `controller.sv`
5. Run testbench `sim/top_level_tb.sv` or real deal `hdl/top_level.sv`
