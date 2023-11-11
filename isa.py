with open("data/all-no-ops.mem", "w") as f:
    no_op = 0b0000_0000_0000000000_0000_0000_000000
    end   = 0b0001_0000_0000000000_0000_0000_000000
    program = [no_op] * 7 + [end]
    f.write( "\n".join([f"{line:08x}" for line in program]) )

