# encoding: ASCII-8BIT

require 'thread'
require 'timeout'
require 'trollop'

require './generate_harness.rb'

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


opts = Trollop::options do
  version("ximage-ng")

  opt :h,       "Gotta use --help if you want help!", :type => :boolean, :default => false
  opt :threads, "Number of parallel threads (16 works well)", :type => :integer, :default => 16
  opt :out,     "Output file (used for saving progress, will also load this file if it exists)", :type => :string, :default => "result.m"
  opt :in,      "Input file (optional; used to generate the testcases. Needs to be in the same format as the output file; designed for chaining, basically, so the output can be re-processed; will perform every test in the file, no matter which status they had)", :type => :string, :default => nil
  opt :s,       "Save frequency in seconds (default 600, once per minute)", :type => :integer, :default => 600
  opt :length,  "The maximum length of the test strings (has to be 3 or less right now)", :type => :integer, :default => 3
  opt :shuffle, "Will shuffle the order of the tests; if turned off, will sort them", :type => :boolean, :default => false
end

if(opts[:h])
  puts("Please use --help for help!")
  exit()
end

`make clean all`

if(opts[:out] == opts[:in])
  puts("It's a really bad idea to use the same output and input file!")
  exit()
end

def generate_test_cases(opts)
  if(opts[:in])
    puts("Opening %s..." % opts[:in])
    File.open(opts[:in]) do |f|
      puts("Reading and loading %s..." % opts[:in])
      input = Marshal.load(f.read())
      puts("Loaded %d test cases!" % input.length())
      return input.keys()
    end
  else
    puts("Generating test cases...")
    tests = []
    0x00.upto(0xFF) do |i|
      tests << ("%c" % i)

      if(opts[:length] > 1)
        0x00.upto(0xFF) do |j|
          tests << ("%c%c" % [i, j])

          if(opts[:length] > 2)
            0x00.upto(0xFF) do |k|
              tests << ("%c%c%c" % [i, j, k])
            end
          end
        end
      end
    end

    puts("Generated %d tests!" % tests.length)
    return tests
  end
end

def filter_completed_tests(tests, results)
  puts("Eliminating completed tests")
  tests.select!() { |t| results[t].nil?() }
end

tests = generate_test_cases(opts)

results = {}
begin
  puts("Loading results file...")
  File.open(opts[:out], 'rb') do |f|
    results = Marshal.load(f.read()) || {}
  end
  puts("Loaded!")

  filter_completed_tests!(tests, results)
rescue Errno::ENOENT
  puts("Failed to load! Starting over...")
end


if(opts[:shuffle])
  puts("Shuffling tests")
  tests.shuffle!()
else
  puts("Sorting tests")
  tests.sort!()
end

def read_registers(str)
  result = {}
  result[:edi], result[:esi], result[:ebp], result[:esp], result[:ebx], result[:edx], result[:ecx], result[:eax], str = str.unpack("VVVVVVVVa*")

  return result, str
end

def do_single_test(code)
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

def do_test(tests, results)
  test = nil
  TEST_MUTEX.synchronize() do
    test = tests.shift()
  end

  if(test.nil?)
    Thread.exit()
  end

  result = do_single_test(test)
  TEST_MUTEX.synchronize() do
    if(result[:status] == :good)
      set   = result[:set_flags].map()   { |f| "set:%s" % f }
      unset = result[:unset_flags].map() { |f| "unset:%s" % f }

      puts("%s => %s :: %s :: %s" % [test.unpack("H*"), result[:status], result[:changed_registers] + set + unset, result[:disassembled].join(' / ')])
    elsif(result[:status] == :timeout)
      puts("%s => %s :: %s" % [test.unpack("H*"), result[:status], result[:disassembled].join(' / ')])
    elsif(result[:status] == :weird)
      puts("%s => %s :: %s" % [test.unpack("H*"), result[:status], result[:disassembled].join(' / ')])
    else
      puts("%s => %s" % [test.unpack("H*"), result[:status]])
    end

    results[test] = result
  end
end

threads = []
0.upto(opts[:threads]) do
  threads << Thread.new() do
    loop do
      do_test(tests, results)
    end
  end
end

Thread.new() do
  last_length  = results.length
  loop do
    sleep(3600)
    TEST_MUTEX.synchronize() do
      puts("\nSaving...\n")
      last_length = results.length
      File.open(opts[:out], "wb") do |f|
        f.write(Marshal::dump(results))
      end
      puts("Saved!")
    end
  end
end

STATUS_TIME = 10
Thread.new() do
  last_results_length = results.length
  loop do
    sleep(STATUS_TIME)

    puts()
    puts("********************************************************************************")
    puts("* STATUS UPDATE")
    puts("********************************************************************************")
    puts()

    results_length = results.length
    tests_length = tests.length
    total_length = results_length + tests_length

    progress = results_length - last_results_length
    progress_per_second = progress.to_f / STATUS_TIME.to_f

    if(progress_per_second == 0)
      time_required_str = "(infinite)"
    else
      time_required_total = tests_length.to_f / progress_per_second.to_f

      mm, ss = time_required_total.divmod(60)
      hh, mm = mm.divmod(60)
      dd, hh = hh.divmod(24)

      time_required_str = "%d days, %02d:%02d:%02d" % [
        dd,
        hh,
        mm,
        ss,
      ]

    end

    puts("Status: %d (%f%%) tests done, %d (%f%%) tests remaining" % [
      results_length,
      (results_length.to_f / total_length.to_f) * 100,
      tests_length,
      (tests_length.to_f / total_length.to_f) * 100,
    ])

    puts("%d completed in %d seconds, so %f per second" % [progress, STATUS_TIME, progress_per_second])
    puts("There are %d tests remaining, therefore..." % tests_length)
    puts("Badly estimated time remaining based on that: %s" % time_required_str)

    puts()

    last_results_length = results_length
  end
end

threads.each() do |t|
  t.join()
end

puts("All done! Writing output file!")
File.open(opts[:out], "wb") do |f|
  f.write(Marshal::dump(results))
end
