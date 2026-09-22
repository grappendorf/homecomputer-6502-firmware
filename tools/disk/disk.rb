#!/usr/bin/env ruby
# Serial floppy for the HomeComputer 6502.
# On start it sends *DISK (monitor steps aside). Ctrl-C or exit sends *EJECT.
#
#   disk.rb [DIRECTORY] [DEVICE]
#
# DEVICE defaults to the PTY path MAME wrote to /tmp/homecomputer6502.pty.
# DIRECTORY defaults to ../../examples next to this repo.
# A name without a dot uses name.prg when that file exists, otherwise name.bas.
# A .prg file is a C64-style image: two-byte load address, then raw bytes.

DEFAULT_DIR = File.expand_path("../../examples", __dir__)

# [dir, dev]. A lone existing non-directory argument is the device.
def resolve_target(argv, usage_msg)
  args = argv.dup
  dir = args.shift
  dev = nil
  if dir.nil?
    dir = DEFAULT_DIR
  elsif !File.directory?(dir) && args.empty? && File.exist?(dir)
    dev = dir
    dir = DEFAULT_DIR
  else
    dev = args.shift
  end
  unless args.empty?
    warn usage_msg
    exit 1
  end
  unless File.directory?(dir)
    warn "not a directory: #{dir}"
    exit 1
  end
  dir = File.expand_path(dir)
  if dev.nil? || dev.empty?
    pty = "/tmp/homecomputer6502.pty"
    unless File.file?(pty)
      warn "no device. Start MAME or pass /dev/ttyUSB0"
      exit 1
    end
    dev = File.read(pty).strip
  end
  unless File.exist?(dev)
    warn "no such device: #{dev}"
    exit 1
  end
  [dir, dev]
end

def open_machine(dev)
  system("stty", "-F", dev, "19200", "raw", "-echo", "-icrnl", "-inlcr", "-ocrnl", "-onlcr", "cs8")
  io = File.open(dev, "r+")
  io.sync = true
  io.binmode
  io
end

$relay_key_io = nil
$relay_keys = :none
$relay_screen = nil
$relay_bar = false

def log(msg)
  warn msg
end

def take_line(pending)
  # A CRLF split across two reads must not become a second empty request.
  pending = pending.sub(/\A\n+/, "")
  i = pending.index(/\r|\n/)
  return nil, pending unless i
  line = pending[0...i]
  rest = pending[(i + 1)..] || +""
  rest = rest.sub(/\A\n/, "") if pending[i] == "\r"
  [line, rest]
end

def fill_line(io, pending, timeout)
  deadline = timeout && (Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout)
  loop do
    line, pending = take_line(pending)
    unless line.nil?
      return line, pending
    end
    left = deadline && (deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC))
    return nil, pending if deadline && left <= 0
    readers = [io]
    readers << $relay_key_io if $relay_key_io && $relay_keys && $relay_keys != :none
    readers << $relay_wake if $relay_wake
    ready, = IO.select(readers, nil, nil, left)
    return nil, pending unless ready
    return nil, pending if $relay_wake && ready.include?($relay_wake)
    if $relay_key_io && ready.include?($relay_key_io)
      begin
        keys = $relay_key_io.read_nonblock(256)
        keys = keys.gsub(/[^\x03]/, "") if $relay_keys == :break
        io.write(keys) unless keys.empty?
      rescue IO::WaitReadable, EOFError, Errno::EIO
      end
    end
    next unless ready.include?(io)
    begin
      pending << io.read_nonblock(256)
    rescue IO::WaitReadable
      next
    rescue EOFError, Errno::EIO
      return nil, pending
    end
  end
end

def write_line(io, text)
  io.write("#{text}\r\n")
end

def safe_path(dir, name)
  return nil if name.nil? || name.empty? || name.bytesize > 16
  return nil if name.include?("/") || name.include?("\\") || name.include?("..")
  if name.include?(".")
    picked = name
  else
    prg = File.join(dir, "#{name}.prg")
    picked = File.file?(prg) ? "#{name}.prg" : "#{name}.bas"
  end
  path = File.expand_path(picked, dir)
  root = dir.end_with?(File::SEPARATOR) ? dir : dir + File::SEPARATOR
  return nil unless path.start_with?(root)
  path
end

def push_back(line, pending)
  "#{line}\n#{pending}"
end

def next_command?(line)
  return false if line.nil?
  line.start_with?("*DIR", "*LOAD ", "*SAVE ", "*DELETE ", "*DISK")
end

# Serial console only. The firmware sends "*PCT n" because the bar cannot
# share the file bytes on the ACIA. Twenty cells, same steps as the LCD.
def relay_bar(pct)
  return unless $relay_screen
  pct = pct.to_i
  pct = 0 if pct.negative?
  pct = 100 if pct > 100
  filled = (pct * 20) / 100
  text = format("[%s%s] %3d%%", "#" * filled, " " * (20 - filled), pct)
  $relay_screen.write("\r#{text}")
  $relay_bar = true
end

def relay_bar_finish
  return unless $relay_bar && $relay_screen
  $relay_screen.write("\r\n")
  $relay_bar = false
end

def read_req(io, pending)
  loop do
    line, pending = fill_line(io, pending, nil)
    return line, pending unless line&.match(/\A\*PCT (\d+)\z/)
    relay_bar(Regexp.last_match(1).to_i)
  end
end

def cmd_save(io, pending, path)
  log "Speichere #{File.basename(path)}"
  File.open(path, "w") do |file|
    complete = false
    loop do
      line, pending = read_req(io, pending)
      if line == "*EOF"
        complete = true
        break
      end
      break if line.nil? || line == "*EJECT" || line == "*BREAK"
      if next_command?(line)
        pending = push_back(line, pending)
        break
      end
      file.puts line
    end
    relay_bar(100) if complete
  end
  log "Gespeichert #{File.basename(path)}"
  pending
ensure
  relay_bar_finish
end

def cmd_load(io, pending, path)
  base = File.basename(path)
  log "Lade #{base}"
  unless File.file?(path)
    _req, pending = fill_line(io, pending, nil)
    write_line(io, "!NOTFOUND")
    log "Nicht gefunden: #{base}"
    return pending
  end
  size = File.size(path)
  req, pending = read_req(io, pending)
  return pending if req.nil? || req.include?("*BREAK") || req.include?("*EJECT")
  return push_back(req, pending) if next_command?(req)
  write_line(io, format("*SIZE %d", size))
  return pending if size == 0
  if path.end_with?(".prg")
    req, pending = read_req(io, pending)
    return pending if req.nil? || req.include?("*BREAK") || req.include?("*EJECT")
    return push_back(req, pending) if next_command?(req)
    io.write("*PRG\r")
    # 32 bytes per request. The 6551 holds one RX byte, and the firmware
    # redraws the bar between chunks. Same size as prg_byte in m6502.s65.
    data = File.binread(path)
    offset = 0
    while offset < data.bytesize
      req, pending = read_req(io, pending)
      return pending if req.nil? || req.include?("*BREAK") || req.include?("*EJECT")
      return push_back(req, pending) if next_command?(req)
      n = [32, data.bytesize - offset].min
      io.write(data.byteslice(offset, n))
      offset += n
    end
    _req, pending = read_req(io, pending)
    return pending if _req.nil? || _req.include?("*BREAK") || _req.include?("*EJECT")
    if next_command?(_req)
      return push_back(_req, pending)
    end
    relay_bar(100)
    write_line(io, "*EOF")
    log "Geladen #{base}"
    return pending
  end
  File.foreach(path) do |line|
    req, pending = read_req(io, pending)
    return pending if req.nil? || req.include?("*BREAK") || req.include?("*EJECT")
    if next_command?(req)
      return push_back(req, pending)
    end
    write_line(io, line.sub(/\r?\n\z/, ""))
  end
  _req, pending = read_req(io, pending)
  return pending if _req.nil? || _req.include?("*BREAK") || _req.include?("*EJECT")
  if next_command?(_req)
    return push_back(_req, pending)
  end
  write_line(io, "*EOF")
  relay_bar(100) if $relay_bar
  log "Geladen #{base}"
  pending
ensure
  relay_bar_finish
end

def cmd_delete(io, pending, path)
  base = File.basename(path)
  unless File.file?(path)
    write_line(io, "!NOTFOUND")
    log "Nicht gefunden: #{base}"
    return pending
  end
  write_line(io, "*FOUND")
  line, pending = fill_line(io, pending, nil)
  return pending if line.nil? || line == "*EJECT" || line == "*BREAK" || line == "*NO"
  if line == "*YES"
    File.delete(path)
    log "Gelöscht #{base}"
  else
    log "Nicht gelöscht #{base}"
  end
  pending
end

def cmd_dir(io, pending, dir)
  log "Verzeichnis angefordert"
  names = Dir.children(dir).reject { |n| n.start_with?(".") }.sort
  count = 0
  names.each do |name|
    path = File.join(dir, name)
    next unless File.file?(path)
    req, pending = fill_line(io, pending, nil)
    return pending if req.nil? || req.include?("*BREAK") || req.include?("*EJECT")
    return push_back(req, pending) if next_command?(req)
    write_line(io, format("%04d %s", File.size(path), name))
    count += 1
  end
  req, pending = fill_line(io, pending, nil)
  return pending if req.nil? || req.include?("*BREAK") || req.include?("*EJECT")
  return push_back(req, pending) if next_command?(req)
  write_line(io, "*EOF")
  log "Verzeichnis: #{count} Dateien"
  pending
end

def run_disk
  dir, dev = resolve_target(ARGV, "usage: disk.rb [DIRECTORY] [DEVICE]")
  io = open_machine(dev)
  $stderr.sync = true
  pending = +""
  mounted = false

  eject = lambda do
    return unless mounted
    mounted = false
    log "Ausgeworfen"
    io.write("*EJECT\r") rescue nil
  end

  trap("INT") { eject.call; exit 0 }
  trap("TERM") { eject.call; exit 0 }

  begin
  io.write("*DISK\r")
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
  ok = false
  loop do
    left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    break if left <= 0
    line, pending = fill_line(io, pending, left)
    break if line.nil?
    next if line.empty?
    if line == "*OK"
      ok = true
      break
    end
  end
  unless ok
    log "Kein *OK vom Computer (läuft diese Firmware?)"
    exit 1
  end
  mounted = true
  log "Diskette bereit: #{dir}"
  log "Gerät: #{dev}"

  loop do
    line, pending = fill_line(io, pending, nil)
    break if line.nil?
    case line
    when /\A\*SAVE "([^"]*)"\z/
      path = safe_path(dir, Regexp.last_match(1))
      if path.nil?
        # Drain until *EOF so the machine does not stay in the transfer.
        loop do
          junk, pending = fill_line(io, pending, nil)
          break if junk.nil? || junk == "*EOF"
        end
        log "Name abgelehnt"
      else
        pending = cmd_save(io, pending, path)
      end
    when /\A\*LOAD "([^"]*)"\z/
      path = safe_path(dir, Regexp.last_match(1))
      if path.nil?
        _req, pending = fill_line(io, pending, nil)
        write_line(io, "!NOTFOUND")
      else
        pending = cmd_load(io, pending, path)
      end
    when /\A\*DELETE "([^"]*)"\z/
      path = safe_path(dir, Regexp.last_match(1))
      if path.nil?
        write_line(io, "!NOTFOUND")
        log "Name abgelehnt"
      else
        pending = cmd_delete(io, pending, path)
      end
    when "*DIR"
      pending = cmd_dir(io, pending, dir)
    end
  end
ensure
  eject.call
  io.close rescue nil
  end
end

run_disk if $PROGRAM_NAME == __FILE__
