GPU Architecture lives here

Components:
- FMA blocks (done)
- FMA read buffer (done)
- FMA write buffer (not started)
- Data cache (in progress)
- Controller (not started)
- Instruction Cache (not started)
- ISA (in progress)
- Frame buffer (not started)
- HDMI video gen module (reused from lab 5&6)

Data cache - Controller - Instruction Cache - FMA buffer interaction
LOAD instruction
- Controller gets a LOAD instruction from instruction cache
- Controller verifies that memory is idle
- Controller sends request to memory to set value at ADDR to be the DATA in the instruction 
- Memory completes the LOAD, signals idle back to controller
FMA_LOAD instruction (also doubles as a start-compute instruction)
- Controller gets a FMA_LOAD instruction from instruction cache
- Controller verifies that memory is idle
- Controller sends a request to memory to load into the FMA read buffer values starting at ADDR 
    until ADDR + LENGTH, with SPACING between each value. 
- Memory completes the FMA_LOAD, signals idle back to controller
- FMA read buffer is full, it flushes its data to the FMA block on the next cycle
FMA_STORE instruction
- Controller gets a FMA_STORE instruction from instruction cache
- Controller pulls the FMA write buffer's valid flag high. In one cycle, the output from all FMA blocks
    are loaded into the FMA write buffer
- Controller verifies that memory is idle
- Controller sends a request to memory to read the FMA write buffer and store the values starting at ADDR 
    until ADDR + LENGTH, with SPACING between each value. 
- Memory completes the FMA_STORE, signals idle back to the controller
