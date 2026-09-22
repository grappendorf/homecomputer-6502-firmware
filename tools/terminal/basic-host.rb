#!/usr/bin/env ruby
# Serial BASIC console and floppy on one ACIA.
# Picocom talks to a local PTY. This process copies that to the machine and,
# when the firmware emits *LOAD / *SAVE / *DIR / *DELETE, runs the disk
# protocol from tools/disk/disk.rb. Exit sends QUIT, not *EJECT.
#
#   basic-host.rb [DIRECTORY] [DEVICE]
#
# DIRECTORY defaults to examples. A lone device path is the ACIA.
# DEVICE defaults to the PTY path MAME wrote to /tmp/homecomputer6502.pty.

require "pty"
require_relative "../disk/disk.rb"

# Picocom has the terminal raw. warn's LF does not return to column 0,
# so the next firmware line starts mid-screen. Status stays off this tty.
def log(_msg)
end

USAGE = "usage: basic-host.rb [DIRECTORY] [DEVICE]"

def disk_command(line)
  case line
  when /\A\*SAVE "([^"]*)"\z/ then [:save, Regexp.last_match(1)]
  when /\A\*LOAD "([^"]*)"\z/ then [:load, Regexp.last_match(1)]
  when /\A\*DELETE "([^"]*)"\z/ then [:delete, Regexp.last_match(1)]
  when "*DIR" then [:dir, nil]
  end
end

def show_line(pico, line)
  pico.write("#{line}\r\n")
end

# DELETE prints the question before the newline, then waits for a key.
def wait_line(machine, pico, pending)
  loop do
    line, pending = take_line(pending)
    return line, pending unless line.nil?
    unless pending.empty?
      pico.write(pending)
      pending = +""
    end
    readers = [machine, pico]
    readers << $relay_wake if $relay_wake
    ready, = IO.select(readers)
    return nil, pending unless ready
    return nil, pending if $relay_wake && ready.include?($relay_wake)
    if ready.include?(pico)
      begin
        keys = pico.read_nonblock(256)
        machine.write(keys) unless keys.empty?
      rescue IO::WaitReadable, EOFError, Errno::EIO
      end
    end
    next unless ready.include?(machine)
    begin
      pending << machine.read_nonblock(256)
    rescue IO::WaitReadable
      next
    rescue EOFError, Errno::EIO
      return nil, pending
    end
  end
end

def relay_dir(machine, pico, pending, dir)
  names = Dir.children(dir).reject { |n| n.start_with?(".") }.sort
  names.select! { |n| File.file?(File.join(dir, n)) }
  idx = 0
  log "Verzeichnis angefordert"
  loop do
    line, pending = fill_line(machine, pending, nil)
    return pending if line.nil? || line.include?("*BREAK") || line.include?("*EJECT")
    if line.empty?
      if idx >= names.size
        write_line(machine, "*EOF")
        log "Verzeichnis: #{names.size} Dateien"
        return pending
      end
      name = names[idx]
      idx += 1
      path = File.join(dir, name)
      write_line(machine, format("%04d %s", File.size(path), name))
    else
      show_line(pico, line)
    end
  end
end

def relay_delete(machine, pico, pending, path)
  base = File.basename(path)
  unless File.file?(path)
    write_line(machine, "!NOTFOUND")
    log "Nicht gefunden: #{base}"
    return pending
  end
  write_line(machine, "*FOUND")
  loop do
    line, pending = wait_line(machine, pico, pending)
    return pending if line.nil?
    case line
    when "*YES"
      File.delete(path)
      log "Gelöscht #{base}"
      return pending
    when "*NO", "*BREAK", "*EJECT"
      log "Nicht gelöscht #{base}"
      return pending
    else
      show_line(pico, line)
    end
  end
end

def dispatch(kind, name, machine, pico, pending, dir)
  $relay_key_io = pico
  $relay_keys = :break
  $relay_screen = pico
  case kind
  when :save
    path = safe_path(dir, name)
    if path.nil?
      loop do
        junk, pending = fill_line(machine, pending, nil)
        break if junk.nil? || junk == "*EOF"
      end
      log "Name abgelehnt"
    else
      pending = cmd_save(machine, pending, path)
    end
  when :load
    path = safe_path(dir, name)
    if path.nil?
      _req, pending = fill_line(machine, pending, nil)
      write_line(machine, "!NOTFOUND")
      log "Name abgelehnt"
    else
      pending = cmd_load(machine, pending, path)
    end
  when :delete
    path = safe_path(dir, name)
    if path.nil?
      write_line(machine, "!NOTFOUND")
      log "Name abgelehnt"
    else
      pending = relay_delete(machine, pico, pending, path)
    end
  when :dir
    pending = relay_dir(machine, pico, pending, dir)
  end
  pending
ensure
  $relay_keys = :none
  $relay_key_io = nil
  $relay_screen = nil
  $relay_bar = false
end

# Bytes from the machine go to Picocom unchanged. Rebuilding each line as
# CR+LF inserted a blank line under --imap lfcrlf, and holding a lone "*"
# glued the monitor prompt onto the next line. A finished *LOAD/*SAVE/*DIR/
# *DELETE is not a second copy: its bytes were already shown, and the
# following protocol is handled by dispatch instead of the screen.
def console_relay(machine, pico, dir, wake)
  line = +""
  loop do
    begin
      ready, = IO.select([machine, pico, wake])
      return if ready.nil? || ready.include?(wake)
      if ready.include?(pico)
        begin
          keys = pico.read_nonblock(256)
          machine.write(keys) unless keys.empty?
        rescue IO::WaitReadable
        end
      end
      next unless ready&.include?(machine)
      begin
        data = machine.read_nonblock(256)
      rescue IO::WaitReadable
        next
      end
      idx = 0
      while idx < data.bytesize
        ch = data[idx]
        idx += 1
        if ch == "\r" || ch == "\n"
          cmd = disk_command(line)
          line = +""
          pico.write(ch)
          if cmd
            rest = data[idx..] || +""
            rest = rest[1..] if ch == "\r" && rest.start_with?("\n")
            rest = dispatch(cmd[0], cmd[1], machine, pico, rest, dir)
            data = rest
            idx = 0
          end
          next
        end
        line << ch
        line = line[-160..] if line.bytesize > 200
        pico.write(ch)
      end
    rescue EOFError, Errno::EIO, IOError
      return
    end
  end
end

def run_basic
  dir, dev = resolve_target(ARGV, USAGE)
  machine = open_machine(dev)
  $stderr.sync = true
  master, slave = PTY.open
  master.sync = true
  master.binmode
  slave_path = File.readlink("/proc/self/fd/#{slave.fileno}")
  # Default PTY echo would send our screen bytes back as keystrokes.
  # The monitor then parses "MON 6502" and answers with "?" and a dump.
  system("stty", "-F", slave_path, "raw", "-echo", "-icrnl", "-inlcr",
         "-ocrnl", "-onlcr", "-isig", "-icanon", "-iexten", "cs8")
  pid = Process.spawn(
    "picocom", "--b", "19200", "--imap", "lfcrlf", "--omap", "crlf",
    "--initstring", "*BASIC\r", slave_path
  )
  # Our slave fd stays open: closing it before Picocom opens the port
  # looks like a hangup and the host exits at once. Picocom's exit is
  # reported on this pipe instead.
  wake_r, wake_w = IO.pipe
  $relay_wake = wake_r
  watcher = Thread.new do
    Process.wait(pid)
    wake_w.write("x") rescue nil
  end
  sent = false
  begin
    console_relay(machine, master, dir, wake_r)
  ensure
    unless sent
      sent = true
      machine.write("\x03QUIT\r") rescue nil
    end
    Process.kill("TERM", pid) rescue nil
    $relay_wake = nil
    watcher.join
    wake_r.close rescue nil
    wake_w.close rescue nil
    master.close rescue nil
    slave.close rescue nil
    machine.close rescue nil
  end
end

run_basic if $PROGRAM_NAME == __FILE__
