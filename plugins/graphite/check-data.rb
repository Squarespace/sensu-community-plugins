#! /usr/bin/env ruby
#
#   check-data
#
# DESCRIPTION:
#   This plugin checks values within graphite
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: json
#   gem: open-uri
#   gem: openssl
#
# USAGE:
#   #YELLOW
#
# NOTES:
#
# LICENSE:
#   Copyright 2014 Sonian, Inc. and contributors. <support@sensuapp.org>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'
require 'json'
require 'open-uri'
require 'openssl'

class CheckGraphiteData < Sensu::Plugin::Check::CLI
  option :target,
         description: 'Graphite data target',
         short: '-t TARGET',
         long: '--target TARGET',
         required: true

  option :server,
         description: 'Server host and port',
         short: '-s SERVER:PORT',
         long: '--server SERVER:PORT',
         required: true

  option :username,
         description: 'username for basic http authentication',
         short: '-u USERNAME',
         long: '--user USERNAME',
         required: false

  option :password,
         description: 'user password for basic http authentication',
         short: '-p PASSWORD',
         long: '--pass PASSWORD',
         required: false

  option :passfile,
         description: 'password file path for basic http authentication',
         short: '-P PASSWORDFILE',
         long: '--passfile PASSWORDFILE',
         required: false

  option :warning,
         description: 'Generate warning if given value is above received value',
         short: '-w VALUE',
         long: '--warn VALUE',
         proc: proc(&:to_f)

  option :critical,
         description: 'Generate critical if given value is above received value',
         short: '-c VALUE',
         long: '--critical VALUE',
         proc: proc(&:to_f)

  option :nodes,
         description: 'Number of nodes in warning and/or critical state must be >= this setting. Does not apply to graphs with a single metric/node',
         short: '-o NODES',
         long: '--nodes NODES',
         proc: proc(&:to_i)

  option :reset_on_decrease,
         description: 'Send OK if value has decreased on any values within END-INTERVAL to END',
         short: '-r INTERVAL',
         long: '--reset INTERVAL',
         proc: proc(&:to_i)

  option :name,
         description: 'Name used in responses',
         short: '-n NAME',
         long: '--name NAME',
         default: 'graphite check'

  option :hostname_sub,
         description: 'Character used to replace periods (.) in hostname (default: _)',
         short: '-s CHARACTER',
         long: '--host-sub CHARACTER'

  option :from,
         description: 'Get samples starting from FROM (default: -10mins)',
         short: '-f FROM',
         long: '--from FROM',
         default: '-10mins'

  option :until,
         description: 'Get samples up until UNTIL (default: -1min)',
         short: '-e UNTIL',
         long: '--until UNTIL',
         default: '-1min'

  option :below,
         description: 'warnings/critical if values below specified thresholds',
         short: '-b',
         long: '--below'

  option :no_ssl_verify,
         description: 'Do not verify SSL certs',
         short: '-v',
         long: '--nosslverify'

  option :help,
         description: 'Show this message',
         short: '-h',
         long: '--help'

  option :debug,
         description: 'Show verbose debugging output',
         short: '-d',
         long: '--debug'

  # Run checks
  def run
    if config[:help]
      puts opt_parser
      exit
    end

    unknown '--nodes arg cannot be < 1' if config[:nodes] && config[:nodes] < 1

    data = retrieve_data
    puts "Data retrieved from graphite: #{ data }" if config[:debug]
    @critical_count = @warning_count = ok_count = 0
    @critical_out = []
    @warning_out = []
    data.each_pair do |_key, value|
      @value = value
      @data = value['data']
      ok_count += 1 if !check?(:critical, !config[:nodes]) && !check?(:warning, !config[:nodes])
    end
    if config[:nodes]
      send_msg = "critical: #{@critical_count}, warning: #{@warning_count - @critical_count}, ok: #{ok_count}\ncritical: #{@critical_out.join(", ")}\nwarning: #{@warning_out.join(", ")}"
      send(:critical, send_msg) if @critical_count >= config[:nodes]
      send(:warning, send_msg) if @warning_count >= config[:nodes]
    end
    ok("#{name} value okay")
  end

  # name used in responses
  def name
    base = config[:name]
    @formatted ? "#{base} (#{@formatted})" : base
  end

  # grab data from graphite
  def retrieve_data
    # #YELLOW
    unless @raw_data # rubocop:disable GuardClause
      begin
        unless config[:server].start_with?('https://', 'http://')
          config[:server].prepend('http://')
        end

        url = "#{config[:server]}/render?format=json&target=#{formatted_target}&from=#{config[:from]}&until=#{config[:until]}&noCache=True"

        url_opts = {}

        if config[:no_ssl_verify]
          url_opts[:ssl_verify_mode] = OpenSSL::SSL::VERIFY_NONE
        end

        if config[:username] && (config[:password] || config[:passfile])
          if config[:passfile]
            pass = File.open(config[:passfile]).readline
          elsif config[:password]
            pass = config[:password]
          end

          url_opts[:http_basic_authentication] = [config[:username], pass.chomp]
        end # we don't have both username and password trying without

        puts "url is: #{url}" if config[:debug]
        puts "url_opts is: #{url_opts}" if config[:debug]

        handle = open(url, url_opts)

        @raw_data = handle.gets
        if @raw_data == '[]'
          unknown 'Empty data received from Graphite - metric probably doesn\'t exists'
        else
          @json_data = JSON.parse(@raw_data)
          output = {}
          @json_data.each do |raw|
            raw['datapoints'].delete_if { |v| v.first.nil? }
            next if raw['datapoints'].empty?
            target = raw['target']
            data = raw['datapoints'].map(&:first)
            start = raw['datapoints'].first.last
            dend = raw['datapoints'].last.last
            step = ((dend - start) / raw['datapoints'].size.to_f).ceil
            output[target] = { 'target' => target, 'data' => data, 'start' => start, 'end' => dend, 'step' => step }
          end
          output
        end
      rescue OpenURI::HTTPError
        unknown 'Failed to connect to graphite server'
      rescue NoMethodError
        unknown 'No data for time period and/or target'
      rescue Errno::ECONNREFUSED
        unknown 'Connection refused when connecting to graphite server'
      rescue Errno::ECONNRESET
        unknown 'Connection reset by peer when connecting to graphite server'
      rescue EOFError
        unknown 'End of file error when reading from graphite server'
      rescue => e
        unknown "An unknown error occured: #{e.inspect}"
      end
    end
  end

  # type:: :warning or :critical
  # alert:: boolean
  # Return alert if required
  def check?(type, alert)
    # #YELLOW
    if config[type] # rubocop:disable GuardClause
      if below?(type) || above?(type)
        output = "#{@value['target']} has passed #{type} threshold (#{@data.last})"
        send(type, output) if alert
        if type.to_s == "critical"
          @critical_count += 1
          @critical_out << output
        else
          @warning_out << output
        end
        @warning_count += 1
      else
        false
      end
    end
  end

  # Check if value is below defined threshold
  def below?(type)
    config[:below] && @data.last < config[type]
  end

  # Check is value is above defined threshold
  def above?(type)
    (!config[:below]) && (@data.last > config[type]) && (!decreased?)
  end

  # Check if values have decreased within interval if given
  def decreased?
    if config[:reset_on_decrease]
      slice = @data.slice(@data.size - config[:reset_on_decrease], @data.size)
      val = slice.shift until slice.empty? || val.to_f > slice.first
      !slice.empty?
    else
      false
    end
  end

  # Returns formatted target with hostname replacing any $ characters
  def formatted_target
    if config[:target].include?('$')
      require 'socket'
      @formatted = Socket.gethostbyname(Socket.gethostname).first.gsub('.', config[:hostname_sub] || '_')
      config[:target].gsub('$', @formatted)
    else
      URI.escape config[:target]
    end
  end
end
