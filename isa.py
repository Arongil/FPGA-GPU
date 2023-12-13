# The module below is a lightweight compiler from assembly-like
# program files into ISA-compliant files that can be loaded on
# to the controller in the GPU.

import sys

###########################################################
#                                                         #
# The functions below convert commands into machine code. #
# All registers are 4 bits. All immediates are 16 bits.   #
# Registers and immediates are stored as little endian.   #
#                                                         #
###########################################################


def nop():
    return (0b0000 << 28)

def end():
    return (0b0001 << 28)

def xor(a_reg, b_reg):
    return (0b0010 << 28) + (a_reg << 24) + (b_reg << 4)

def addi(a_reg, b_reg, val):
    return (0b0011 << 28) + (a_reg << 24) + (val << 8) + (b_reg << 4)

def bge(a_reg, b_reg):
    return (0b0100 << 28) + (a_reg << 24) + (b_reg << 4)

def jump(jump_to_val):
    return (0b0101 << 28) + (jump_to_val << 8)

def fbswap():
    return (0b0110 << 28)

def loadi(a_reg, val):
    return (0b0111 << 28) + (a_reg << 24) + (val << 8)

def sendl(val):
    return (0b1000 << 28) + (val << 8)

def loadb(shuffle1, shuffle2, shuffle3):
    return (0b1001 << 28) + (shuffle1 << 24) + (shuffle2 << 4) + (shuffle3 << 0)

def load(abc, b_reg, diff):
    return (0b1010 << 28) + (abc << 24) + (diff << 8) + (b_reg << 4)

def writeb(val, replace_c, fma_valid):
    return (0b1011 << 28) + (replace_c << 24) + (val << 8) + (fma_valid << 4)

def write(replace_c, fma_valid):
    return (0b1100 << 28) + (replace_c << 24) + (fma_valid << 4)

def op_or(iters):
    return (0b1101 << 28) + (iters << 24)

def senditers(a_reg, b_reg):
    return (0b1110 << 28) + (a_reg << 24) + (b_reg << 4)

def pause():
    return (0b1111 << 28)

str_to_command = {
    "nop": nop,
    "end": end,
    "xor": xor,
    "addi": addi,
    "bge": bge,
    "jump": jump,
    "fbswap": fbswap,
    "loadi": loadi,
    "sendl": sendl,
    "loadb": loadb,
    "load": load,
    "writeb": writeb,
    "write": write,
    "or": op_or,
    "senditers": senditers,
    "pause": pause,
}

##########################################################
#                                                        #
# The function below converts jump markers and fixed     #
# point numbers into machine code interpretable form.    #
#                                                        #
##########################################################


def float_to_fixed_point_binary_base10(value: float) -> int:
    """
    Converts a float to a fixed-point binary number with 10 places after the fixed point
    and 16 bits in total, then returns that binary number represented in base 10.
    
    Args:
        value (float): The float value to convert. Should be in the range -63 to 64.

    Returns:
        int: The fixed-point binary number represented in base 10.

    Credit: function written by GPT-4, Dec 10th, 2023
    """

    # Constants
    MAX_BITS = 16
    FRACTIONAL_BITS = 10

    # Scale the float to fixed point value
    scaled_value = int(round(value * (1 << FRACTIONAL_BITS)))

    # Handle negative values using two's complement
    if scaled_value < 0:
        scaled_value = (1 << MAX_BITS) + scaled_value

    return scaled_value


def interpret_arg(arg: str, instructions: list) -> int:
    """
    Given an argument (str) and the full program instructions,
    return an int that represents the desired interpretation.
    1. Jump markers: (((X))) is converted to the line where X is marked.
    2. Fixed point: 1.5f is converted to 1.5 as a fixed point number.
    3. Negative: -3 is converted to b1101 as 4-bit two's complement.
    """

    # Jump marker -- find the marker and go to that line
    if arg[0:3] == "(((" and arg[-3:] == ")))":
        marker = arg[3:-3]
        for line_num, line in enumerate(instructions):
            if f"[JUMP MARKER {marker}]" in line:
                return line_num

    # Fixed point -- convert to 16 bit fixed point (10 "decimal places")
    if arg[-1] == "f":
        num = float(arg[:-1])
        return float_to_fixed_point_binary_base10(num)
    
    if arg[0] == "-":
        num = int(arg[1:])
        return 16 - num

    return int(arg) 


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
    # ignore any comments, empty lines, and extra whitespace.
    instructions = program.split("\n")[:-1]
    instructions = [i for i in instructions if i.split("#")[0].lower().strip() != ""]
    instructions.append("nop")  # an extra no_op at the end to avoid undefined
    
    isa_commands = []
    for line_num, line in enumerate(instructions):
        instruction = line.split("#")[0].lower().strip()
        args = instruction.split(" ")
        command = None
        op_name = args[0]
        op_args = [interpret_arg(arg, instructions) for arg in args[1:]]
        if op_name in str_to_command:
            try:
                command = str_to_command[op_name](*op_args)
            except:
                raise ValueError(f"Invalid number of arguments on line {line_num}:\n\t{instruction}")
        else:
            raise ValueError(f"Didn't recognize command {op_name}")
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

