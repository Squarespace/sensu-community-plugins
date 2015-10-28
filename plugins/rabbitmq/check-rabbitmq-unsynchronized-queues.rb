#!/usr/bin/env ruby
#  encoding: UTF-8
#
# Check RabbitMQ for Unsynchronized Queues
# ===
#
# DESCRIPTION:
# This plugin checks for unsyncronized queues in a Rabbitmq cluster.
#
# PLATFORMS:
#   Linux, BSD, Solaris
#
# DEPENDENCIES:
#   RabbitMQ rabbitmq_management plugin
#   gem: sensu-plugin
#   gem: carrot-top
#
# LICENSE:
# Copyright 2015 Chris Downes <cdownes@squarespace.com>
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'sensu-plugin/check/cli'
require 'socket'
require 'carrot-top'

# main plugin class
class CheckRabbitMQUnsynchronizedQueues < Sensu::Plugin::Check::CLI
  option :host,
         description: 'RabbitMQ management API host',
         short: '-h HOST',
         long: '--host HOST',
         default: 'localhost'

  option :port,
         description: 'RabbitMQ management API port',
         long: '--port PORT',
         proc: proc(&:to_i),
         default: 15_672

  option :ssl,
         description: 'Enable SSL for connection to the API',
         short: '-s',
         long: '--ssl',
         boolean: true,
         default: false

  option :user,
         description: 'RabbitMQ management API user',
         short: '-u USER',
         long: '--user USER',
         default: 'guest'

  option :password,
         description: 'RabbitMQ management API password',
         short: '-p PASSWORD',
         long: '--password PASSWORD',
         default: 'guest'

  option :filter,
         description: 'Regular expression for filtering queues',
         short: '-f REGEX',
         long: '--filter REGEX'

  def acquire_rabbitmq_queues
    begin
      rabbitmq_info = CarrotTop.new(
        host: config[:host],
        port: config[:port],
        user: config[:user],
        password: config[:password],
        ssl: config[:ssl]
      )
    rescue
      warning 'could not get rabbitmq info'
    end
    rabbitmq_info.queues
  end

  def run
    acquire_rabbitmq_queues.each do |queue|
      if config[:filter]
        next unless queue['name'].match(config[:filter])
      end

      unsynchronised = queue['slave_nodes'] - queue['synchronised_slave_nodes']

      unless unsynchronised.empty?
        critical "queue #{queue['name']} has unsynchronized slave(s) #{unsynchronised}"
      end

    end
    ok
  end

end
