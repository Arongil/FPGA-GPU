# The module below is a lightweight compiler from assembly-like
# program files into ISA-compliant files that can be loaded on
# to the controller in the GPU.

import sys

###############################################################
#                                                             #
# The functions below convert commands into machine code.     #
# All register inputs are 4 bits. All immediates are 16 bits. #
#                                                             #
###############################################################


def nop():
    return (0b0000 << 28)

def end():
    return (0b0001 << 28)

def xor(a_reg, b_reg):
    return (0b0010 << 28) + (a_reg << 24) + (b_reg << 4)

def addi(a_reg, b_reg, val):
    return (0b0011 << 28) + (a_reg << 24) + (val << 20) + (b_reg << 4)

def bge(a_reg, b_reg):
    return (0b0100 << 28) + (a_reg << 24) + (b_reg << 4)

def jump(jump_to_val):
    return (0b0101 << 28) + (val << 20)


##########################################################
#                                                        #
# The function below converts a newline-delimited string #
# into a machine code program that conforms to the ISA.  #
#                                                        #
##########################################################

def str_to_isa(program: str): 
    """
    Given a newline-delimited string, whose inner arguments are
    space-delimited, return a string that complies with the ISA.
    """

    # Split the input on newlines (skipping empty last line),
    # ignore any comments, and remove extra whitespace.
    instructions = program.split("\n")[:-1]
    instructions = [i.split("#")[0].lower().strip() for i in instructions]
    
    isa_commands = []
    for instruction in instructions:
        args = instruction.split(" ")
        command = None
        match args[0]:
            case "nop":
                command = nop()
            case "end":
                command = end()
            case "xor":
                command = xor(args[1], args[2])
            case "addi":
                command = addi(args[1], args[2], args[3])
            case "bge":
                command = bge(args[1], args[2])
            case "jump":
                command = jump(args[1])
            case unrecognized:
                raise ValueError(f"Didn't recognize command {unrecognized}")
        # Format the 32 bit binary number as an 8 bit hex string
        isa_commands.append(f"{command:08x}")

    return "\n".join(isa_commands)

if __name__ == "__main__":
    args = sys.argv[1:]
    
    if len(args) != 1:
        print("\tPlease pass one argument <program_file_path> to convert to ISA.")
        exit()

    if len(args[0].split(".")) > 2:
        print("\tPlease pass in a file name without multiple periods.")
        exit()

    orig_name = args[0].split("/")[-1].split(".")[0]
    filename = "isa-" + orig_name + ".mem"

    with open(args[0], "r") as f:
        program = f.read()

    with open(f"data/{filename}", "w") as f:
        isa = str_to_isa(program)
        f.write(isa)

