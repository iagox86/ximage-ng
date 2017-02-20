# encoding: ASCII-8BIT

require 'yaml'
require 'timeout'
require 'pp'

`gcc -m32 -o run ./run.c`

def go(code)
  if(code.length != 3)
    raise(ValueError)
  end

  File.open("test_code.bin", "wb") do |w|
    w.write(code)
  end

  result = {
    :code => code,
  }

  out = ''

  begin
    Timeout::timeout(1) do
      out = `./run < test_code.bin 2>/dev/null`
    end
  rescue Timeout::Error
    result[:status] = :timeout
    return result
  end

  out.force_encoding("ASCII-8BIT")

  result[:out] = out

  if(out.length == 32)
    result[:status] = :crash
    return result
  end

  if(out.length != 64)
    result[:status] = :weird
    result[:msg] = "The length was %d" % out.length
    return result
  end

  result[:status] = :good
  result[:changed_registers] = []

  before_bin = out[0,32]
  after_bin = out[32,64]

  before = {}
  after = {}

  before[:edi], before[:esi], before[:ebp], before[:esp], before[:ebx], before[:edx], before[:ecx], before[:eax] = before_bin.unpack("VVVVVVVV")
  after[:edi],  after[:esi],  after[:ebp],  after[:esp],  after[:ebx],  after[:edx],  after[:ecx],  after[:eax]  = after_bin.unpack("VVVVVVVV")

  # List the changed registers
  [:eax, :ebx, :ecx, :edx, :esi, :edi, :esp, :ebp].each do |reg|
    if(before[reg] != after[reg])
      result[:changed_registers] << reg
    end
  end

  # Disassemble it
  result[:disassembled] = `ndisasm -b32 test_code.bin | cut -b29-`.strip().split("\n")

  return result
end

results = {}

pp go("\xeb\xfe\x90")

0.upto(0xFF) do |i|
  str = "\x90\x90%c" % i
  result = go(str)
  results[str] = result

  if(result[:status] == :good)
    puts("%s => %s :: %s :: %s" % [str.unpack("H*"), result[:status], result[:changed_registers], result[:disassembled].join(' / ')])
  else
    puts("%s => %s" % [str.unpack("H*"), result[:status]])
  end

  File.open("result", "wb") do |f|
    f.write(YAML::dump(results))
  end
end

0.upto(0xFFFF) do |i|
  str = "\x90%c%c" % [
    (i >> 0)  & 0x0000FF,
    (i >> 8)  & 0x0000FF,
  ]
  result = go(str)
  results[str] = result

  if(result[:status] == :good)
    puts("%s => %s :: %s :: %s" % [str.unpack("H*"), result[:status], result[:changed_registers], result[:disassembled].join(' / ')])
  else
    puts("%s => %s" % [str.unpack("H*"), result[:status]])
  end

  File.open("result", "wb") do |f|
    f.write(YAML::dump(results))
  end
end

0.upto(0xFFFFFF) do |i|
  str = "%c%c%c" % [
    (i >> 0)  & 0x0000FF,
    (i >> 8)  & 0x0000FF,
    (i >> 16) & 0x0000FF,
  ]
  result = go(str)
  results[str] = result

  if(result[:status] == :good)
    puts("%s => %s :: %s :: %s" % [str.unpack("H*"), result[:status], result[:changed_registers], result[:disassembled].join(' / ')])
  else
    puts("%s => %s" % [str.unpack("H*"), result[:status]])
  end

  File.open("result", "wb") do |f|
    f.write(YAML::dump(results))
  end
end
