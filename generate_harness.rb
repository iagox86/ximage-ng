##
# generate_harness.rb
# By Ron Bowes <ron@skullsecurity.net>
# Created March 11, 2017
#
# The purpose of this class is to generate an assembly test harness that will
# incorporate some chosen code, and anything possible around it in an attempt
# to crash any code that might be bad.
##

require 'tempfile'

STACK_GUARD_SIZE = 8 # 4096
JUMP_GUARD_SIZE = 8 # 1024

# These are the order that the registers and flags are printed, nested; we need
# to know the order elsewhere so we can parse the output properly
REGISTER_PRINT_REGISTERS = ["0x00000000", "0x7fffffff", "0x80000000", "0xffffffff"]
REGISTER_PRINT_FLAGS = ["0x00000000", "0x00000080", "0xfffffeff"]

def random_string()
  return (0...16).map { (0x61 + rand(26)).chr }.join
end

# This is designed to run before each operation; it basically sets up the stack
# with a ton of invalid addresses. That way, if something pushes or pops a value
# then tries to dereference it, it will crash
def write_stack_guard(f)
  whisper_comment(f, "Creating stack guard (part 1)")
  f.puts("mov eax, 0x41414141")
  f.puts("mov ebx, 0x42424242")
  f.puts("mov ecx, 0x43434343")
  f.puts("mov edx, 0x44444444")
  f.puts("mov esi, 0x45454545")
  f.puts("mov edi, 0x46464646")
  f.puts("mov ebp, 0x47474747")

  0.upto(STACK_GUARD_SIZE) do
    f.puts("pushad")
  end
  0.upto(STACK_GUARD_SIZE / 2) do
    f.puts("popad")
  end

  yield()

  whisper_comment(f, "Creating stack guard (part 2)")
  0.upto(STACK_GUARD_SIZE / 2) do
    f.puts("popad")
  end
end

# This should be run immediately before and after each test. It creates a huge
# block of "guard values - 0xcc - and jumps over them. This is designed to catch
# instructions that jump forward or backward, or that try to "consume" the
# instruction immediately before or after them
def write_jump_guard(f)
  whisper_comment(f, "Creating jump guard (part 1)")
  jump = random_string()
  f.puts("jmp %s" % jump)
  0.upto(JUMP_GUARD_SIZE) do
    f.puts("db %s" % (["0xcc"] * 64).join(", "))
  end
  f.puts("%s:" % jump)

  yield()

  whisper_comment(f, "Creating jump guard (part 2)")
  jump = random_string()
  f.puts("jmp %s" % jump)
  0.upto(JUMP_GUARD_SIZE) do
    f.puts("db %s" % (["0xcc"] * 64).join(", "))
  end
  f.puts("%s:" % jump)
end

def give_me_clean_slate(f, registers, flags)
  write_stack_guard(f) do
    if(registers)
      set_all_registers(f, registers)
    end
    if(flags)
      set_flags(f, flags)
    end

    write_jump_guard(f) do
      yield
    end
  end
end

def set_all_registers(f, value)
  whisper_comment(f, "Set registers to 0x%08x" % value)
  f.puts("mov eax, %s" % value)
  f.puts("mov ebx, %s" % value)
  f.puts("mov ecx, %s" % value)
  f.puts("mov edx, %s" % value)
  f.puts("mov esi, %s" % value)
  f.puts("mov edi, %s" % value)
  f.puts("mov ebp, %s" % value)
end

def set_flags(f, value)
  whisper_comment(f, "Set flags to 0x%08x" % value)
  f.puts("push %s" % value)
  f.puts("popfd")
end

def run_code(f, value)
  whisper_comment(f, "Running the code!!")
  f.puts("db %s" % (value.bytes().map() { |b| "0x%02x" % b}).join(", "))
end

def yell_comment(f, str)
  f.puts()
  f.puts(";" * 80)
  f.puts("; %s" % str)
  f.puts(";" * 80)
end

def whisper_comment(f, str)
  f.puts()
  f.puts("; %s" % str)
end

# This will cause all registers to be printed to stdout
def print_registers(f)
  whisper_comment(f, "Print registers")
  f.puts("pushad")
  f.puts("mov eax, 4   ; syscall 4 = write")
  f.puts("mov ebx, 1   ; fd 0 = stdout")
  f.puts("mov ecx, esp ; buf = esp, where we just pushed the registers")
  f.puts("mov edx, 32  ; len = 32, the number of pushed registers")
  f.puts("int 0x80     ; do syscall")
  f.puts("popad        ; restore the stack")
end

# This will cause all flags to be printed to stdout
def print_flags(f)
  whisper_comment(f, "Print flags")
  f.puts("pushfd ; push the 32-bits of flags")
  f.puts("mov eax, 4   ; syscall 4 = write")
  f.puts("mov ebx, 1   ; fd 0 = stdout")
  f.puts("mov ecx, esp ; buf = esp, where we just pushed the flags")
  f.puts("mov edx, 4   ; len = 4, there are 4 bytes of flags")
  f.puts("int 0x80     ; do syscall")
  f.puts("add esp, 4   ; restore the stack")
end

def generate_harness(code)
  Tempfile.open('ximage') do |f|
    f.puts("bits 32")

    # Try every combination of registers and flags to try and make it crash
    ["0x00000000", "0x7fffffff", "0x80000000", "0xffffffff", nil].each do |registers|
      ["0x00000000", "0xfffffeff", "0x00000080", nil].each do |flags|
        yell_comment(f, "Running crash-test with registers = %s and flags = %s" % [registers || '(nil)', flags || '(nil)'])
        give_me_clean_slate(f, registers, flags) do
          run_code(f, code)
        end
      end
    end

    # If it hasn't crashed, hooray! Now we can just do our output capturing
    yell_comment(f, "Testing which flags are set and printing them")
    set_flags(f, "0x00000000")
    run_code(f, code)
    print_flags(f)

    yell_comment(f, "Testing which flags are unset and printing them")
    set_flags(f, "0xfffffeff")
    run_code(f, code)
    print_flags(f)

    REGISTER_PRINT_REGISTERS.each() do |registers|
      REGISTER_PRINT_FLAGS.each() do |flags|
        yell_comment(f, "Checking if registers change from %s when flags are %s" % [registers, flags])
        set_all_registers(f, registers)
        set_flags(f,flags)
        print_registers(f)
        run_code(f, code)
        print_registers(f)
      end
    end

    # Do a clean exit
    f.puts("mov eax, 1")
    f.puts("xor ebx, ebx")
    f.puts("int 0x80")

    # Ensure the file is written, then pass it up
    f.rewind()
    #yield(f.path) # TODO: Enable this
    puts(f.read())
  end
end

generate_harness("\x90")
