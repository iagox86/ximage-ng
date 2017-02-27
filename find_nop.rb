# encoding: ASCII-8BIT

require 'yaml'
require 'timeout'
require 'pp'
require 'thread'

`make clean all`

# 1 thread => 127, 107, 205
# 4 threads => 705, 713, 694
# 8 threads => 781, 720, 682
# 16 threads => 775, 790, 752
# 32 threads => 721, 716, 800
# 64 threads => 752, 705, 738
# 128 threads => 734, 681, 589
# 256 threads => 702, 674, 742
# 1024 threads => 1097, 838, 820
THREAD_COUNT = 16

OUTPUT_FILE = "result.m"

# Create a list of all the strings we plan to test
puts("Generating test cases...")
TESTS = []
0x00.upto(0xFF) do |i|
  TESTS << ("%c" % i)
  0x00.upto(0xFF) do |j|
    TESTS << ("%c%c" % [i, j])
    0x00.upto(0xFF) do |k|
      TESTS << ("%c%c%c" % [i, j, k])
    end
  end
end

begin
  puts("Loading results file...")
  File.open(OUTPUT_FILE, 'rb') do |f|
    RESULTS = Marshal.load(f.read()) || {}
  end
  puts("Loaded!")
rescue Errno::ENOENT
  puts("Failed to load! Starting over...")
  RESULTS = {}
end

puts("Eliminating completed tests")
TESTS.select!() { |t| RESULTS[t].nil?() }

puts("Ordering tests")
TESTS.sort!()
TEST_MUTEX = Mutex.new()

FLAGS = {
  0x00 => :cf,
  0x01 => :Reserved01,
  0x02 => :pf,
  0x03 => :Reserved03,
  0x04 => :af,
  0x05 => :Reserved05,
  0x06 => :zf,
  0x07 => :sf,
  0x08 => :tf,
  0x09 => :if,
  0x0a => :df,
  0x0b => :of,
  0x0c => :iopl1,
  0x0d => :iopl2,
  0x0e => :nt,
  0x0f => :Reserved15,
  0x10 => :rf,
  0x11 => :vm,
  0x12 => :ac,
  0x13 => :vif,
  0x14 => :vip,
  0x15 => :id,
  0x16 => :Reserved16,
  0x17 => :Reserved17,
  0x18 => :Reserved18,
  0x19 => :Reserved19,
  0x1a => :Reserved1a,
  0x1b => :Reserved1b,
  0x1c => :Reserved1c,
  0x1d => :Reserved1d,
  0x1e => :Reserved1e,
  0x1f => :Reserved1f,
}

def read_registers(str)
  result = {}
  result[:edi], result[:esi], result[:ebp], result[:esp], result[:ebx], result[:edx], result[:ecx], result[:eax], str = str.unpack("VVVVVVVVa*")

  return result, str
end

def go(code)
  if(code.length > 3)
    raise(ValueError)
  end

  filename = "test_code_%d.bin" % Thread.current.object_id

  result = {
    :code => code,
  }

  # Disassemble the original code
  File.open(filename, "wb") do |w|
    w.write(code)
  end
  result[:disassembled] = `ndisasm -b32 #{filename} | cut -b29-`.strip().split("\n")

  while(code.length < 3)
    code = "\x90" + code
  end

  File.open(filename, "wb") do |w|
    w.write(code)
  end

  out = ''
  begin
    Timeout::timeout(10) do
      out = `./run < #{filename} 2>/dev/null`
    end
  rescue Timeout::Error
    result[:status] = :timeout
    return result
  end

  out.force_encoding("ASCII-8BIT")


  if(out.length < 296)
    result[:status] = :crash
    return result
  end

  if(out.length != 296)
    result[:status] = :weird
    result[:msg] = "The length was %d" % out.length
    result[:out] = out
    return result
  end

  # Yay, we have the right output! Now, collect some data...
  result[:status] = :good

  set_flags, out = out.unpack("Va*")
  out_set_flags = set_flags & (~0x00000202)

  unset_flags, out = out.unpack("Va*")
  out_unset_flags = unset_flags | (~0x00244ed7)

  base1,    out = read_registers(out)
  after1_1, out = read_registers(out)
  after1_2, out = read_registers(out)

  base2,    out = read_registers(out)
  after2_1, out = read_registers(out)
  after2_2, out = read_registers(out)

  base3,    out = read_registers(out)
  after3_1, out = read_registers(out)
  after3_2, out = read_registers(out)

  result[:changed_registers] = []

  # List the changed registers
  [:eax, :ebx, :ecx, :edx, :esi, :edi, :esp, :ebp].each do |reg|
    if(base1[reg] != after1_1[reg] || base1[reg] != after1_2[reg])
      result[:changed_registers] << reg
    elsif(base2[reg] != after2_1[reg] || base2[reg] != after2_2[reg])
      result[:changed_registers] << reg
    elsif(base3[reg] != after3_1[reg] || base3[reg] != after3_2[reg])
      result[:changed_registers] << reg
    end
  end

  result[:set_flags] = []
  result[:unset_flags] = []
  0.upto(31) do |i|
    if((out_set_flags & (1 << i)) != 0)
      result[:set_flags] << FLAGS[i]
    end
    if((out_unset_flags & (1 << i)) == 0)
      result[:unset_flags] << FLAGS[i]
    end
  end

  return result
end

def do_test()
  test = nil
  TEST_MUTEX.synchronize() do
    test = TESTS.shift()
  end

  if(test.nil?)
    Thread.exit()
  end
  if(!RESULTS[test].nil?)
    puts("%s => [skipping]" % test.unpack("H*"))
    return
  end

  result = go(test)
  TEST_MUTEX.synchronize() do
    if(result[:status] == :good)
      set   = result[:set_flags].map()   { |f| "set:%s" % f }
      unset = result[:unset_flags].map() { |f| "unset:%s" % f }

      puts("%s => %s :: %s :: %s" % [test.unpack("H*"), result[:status], result[:changed_registers] + set + unset, result[:disassembled].join(' / ')])
    elsif(result[:status] == :timeout)
      puts("%s => %s :: %s" % [test.unpack("H*"), result[:status], result[:disassembled].join(' / ')])
    elsif(result[:status] == :weird)
      puts("%s => %s :: %s :: %s" % [test.unpack("H*"), result[:status], result[:disassembled].join(' / '), result[:out].unpack("H*")])
    else
      puts("%s => %s" % [test.unpack("H*"), result[:status]])
    end

    RESULTS[test] = result
  end
end

threads = []
0.upto(THREAD_COUNT) do
  threads << Thread.new() do
    loop do
      do_test()
    end
  end
end

Thread.new() do
  last_length  = RESULTS.length
  loop do
    sleep(600)
    TEST_MUTEX.synchronize() do
      puts("\nSaving...\n")
      last_length = RESULTS.length
      File.open(OUTPUT_FILE, "wb") do |f|
        f.write(Marshal::dump(RESULTS))
      end
      puts("Saved!")
    end
  end
end

Thread.new() do
  loop do
    sleep(10)
    results_length = RESULTS.length
    tests_length = TESTS.length
    total_length = results_length + tests_length
    puts("\nStatus: %d (%f%%) tests done, %d (%f%%) tests remaining\n" % [
      results_length,
      (results_length.to_f / total_length.to_f) * 100,
      tests_length,
      (tests_length.to_f / total_length.to_f) * 100,
    ])
    puts()
  end
end

threads.each() do |t|
  t.join()
end

puts("All done! Writing output file!")
File.open(OUTPUT_FILE, "wb") do |f|
  f.write(Marshal::dump(RESULTS))
end
