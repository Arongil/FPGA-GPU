# FPGA-GPU
6.205 Final Project by Laker and Hanfei

## Steps to program the GPU

1. Write an assembly-style program (e.g., `matrix-mult.txt`)
2. Convert into machine code using `python isa.py <program_name.txt>`
3. Update the program file in BRAM initialization in `hdl/controller.sv`
4. Update the instruction count parameter when initializating `controller.sv`
5. Run testbench `sim/top_level_tb.sv` or real deal `hdl/top_level.sv`

## Steps to add an ISA command

1. Update the comment in the enum for ISA in `controller.sv`
2. Possibly add a case statement in `controller.sv`, or update `memory_valid_for_memory_out` if it's a memory command
3. Possibly add a case statement in `memory.sv` if it's a memory command
4. Update `isa.py` to conform to the new arguments you use (return as below, and add to `str_to_command` dictionary)

```
return (op_code << 28) + (reg_a << 24) + (immediate << 8) + (reg_b << 4) + (reg_c << 0)
```

5. Run `isa.py data/matrix-mult.txt`, then `iverilog -g2012 -o sim.out sim/top_level_tb.sv hdl/...`, then `vvp sim.out`, then `open dump.vcd` in GTKWave and verify that the output of the matrix multiplication remains correct (\BRAM[5][95:0] in GTKWave takes on value 0x00000000001600320013002B)
