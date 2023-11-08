`timescale 1ns / 1ps
`default_nettype none

// 

module data_cache #() (

);

    //  DATA CACHE
    //
    //     The inputs, outputs, and intermediary result of the GPU computation are stored here. Currently, we only have
    //     one BRAM/one block of memory, to simplify logic. In the future, we can have duplicate caches to faciliate faster
    //     access (i.e. read speed). Also, note that the reason that this strcture is called a "cache" is that accessing items in 
    //     it is relatively fast (2 cycles), it is not a traditionally cache in that it stores all data we need for a program,
    //     not just the frequently-accessed elements. So the issue of cache misses does not exist. 
    //
    //     Initializtion:
    //     Initially, the controller gets input data from an external source and puts it into the data cache.
    //     Once all inputs has been stored, the cache will send a ready signal to the controller to signify 
    //     that the data cache is now idle and ready for more operations.
    //     
    //     Reading Data
    //     Once the data cache is idle, the controller can do read operations, where data starting at a given address addr in the cache 
    //     until addr + width / 16 is loaded into the data buffer from where it is given to the FMA blocks.
    //     Once the data buffer receives everything it needs, on the next cycle it will put data into the FMA blocks.
    //     At the same time, the data buffer will send a ready signal to the data cache, and the data cache will send
    //     a ready signal to the controller to signify that the data cache is now idle and ready for more operations.
    //     
    //     Writing Data
    //     Once the data cache is idle, the controller can do write operations, where results from the FMA blocks are put 
    //     into the data cache.
    //     start requesting the data cache to access certain data and sending it to certain registers in the data buffer.
    //     Once the data buffer receives everything it needs, on the next cycle it will put data into the FMA blocks.
    //     At the same time, the data buffer will send a ready signal to the data cache, and the data cache will send
    //     a ready signal to the controller to signify that the data cache is now idle and ready for more operations.
    //
    //     Inputs:
    //       sys_to_mem_in: 
    //       read_write_in: array in the format of ADDR + READ_OR_WRITE, of length ADDR_LENGTH + 1, 
    //          if READ_OR_WRITE is 1, then starting at ADDR, read to 4 fma blocks, assuming we have 4 fma blocks
    //          if READ_OR_WRITE is 0, then write from the 4 fmas sequentially to memory starting at ADDR, assuming we have 4 fma blocks
    //
    //     Outputs:


endmodule

`default_nettype wire