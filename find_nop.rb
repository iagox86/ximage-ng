# encoding: ASCII-8BIT

require 'yaml'
require 'timeout'
require 'pp'

`make all`

def go(code)
  if(code.length > 3)
    raise(ValueError)
  end

  result = {
    :code => code,
  }

  while(code.length < 3)
    code = "\x90" + code
  end

  filename = "test_code_%d.bin" % Thread.current.object_id
  File.open(filename, "wb") do |w|
    w.write(code)
  end


  out = ''

  begin
    Timeout::timeout(1) do
      out = `./run < #{filename} 2>/dev/null`
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

  # Disassemble the original code
  File.open("test_code.bin", "wb") do |w|
    w.write(result[:code])
  end
  result[:disassembled] = `ndisasm -b32 test_code.bin | cut -b29-`.strip().split("\n")

  return result
end

results = {}

puts()
puts("1-byte values...")
puts()
0x0.upto(0xFF) do |i|
  str = "%c" % i
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

puts()
puts("2-byte values...")
puts()
0.upto(0xFFFF) do |i|
  str = "%c%c" % [
    (i >> 8)  & 0x0000FF,
    (i >> 0)  & 0x0000FF,
  ]

  # Skip over stuff that we've seen before
#  if(results[str[0,1]] && results[str[0,1]][:status] == :good)
#    puts("%s => skipped, because it has a known working prefix" % str.unpack("H*"))
#    next
#  end

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
    (i >> 16) & 0x0000FF,
    (i >> 8)  & 0x0000FF,
    (i >> 0)  & 0x0000FF,
  ]

#  if(results[str[0,1]] && results[str[0,1]][:status] == :good)
#    puts("%s => skipped, because it has a known working 1-byte prefix" % str.unpack("H*"))
#    next
#  end
#
#  if(results[str[0,2]] && results[str[0,2]][:status] == :good)
#    puts("%s => skipped, because it has a known working 2-byte prefix" % str.unpack("H*"))
#    next
#  end
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
