#!/usr/bin/env ruby

# Copyright 2014 Dan Shultz and contributors.
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.
#
# In order to use this plugin, you must first configure an incoming webhook
# integration in slack. You can create the required webhook by visiting
# https://{your team}.slack.com/services/new/incoming-webhook
#
# After you configure your webhook, you'll need the webhook URL from the integration.

require 'sensu-handler'
require 'json'

class Slack < Sensu::Handler
  option :json_config,
         description: 'Configuration name',
         short: '-j JSONCONFIG',
         long: '--json JSONCONFIG',
         default: 'slack'

  def slack_webhook_url
    get_setting('webhook_url')
  end

  def slack_channel
    get_setting('channel')
  end

  def slack_proxy_addr
    get_setting('proxy_addr')
  end

  def slack_proxy_port
    get_setting('proxy_port')
  end

  def slack_message_prefix
    get_setting('message_prefix')
  end

  def slack_bot_name
    get_setting('bot_name')
  end

  def slack_surround
    get_setting('surround')
  end

  def markdown_enabled
    get_setting('markdown_enabled') || true
  end

  def sensu_server_url
    get_setting('sensu_server_url')
  end

  def client_name
    @event['client']['name']
  end

  def get_setting(name)
    settings[config[:json_config]][name]
  end

  def handle
    post_data
  end

  def post_data

    uri = URI(slack_webhook_url)

    if (defined?(slack_proxy_addr)).nil?
      http = Net::HTTP.new(uri.host, uri.port)
    else
      http = Net::HTTP::Proxy(slack_proxy_addr, slack_proxy_port).new(uri.host, uri.port)
    end

    http.use_ssl = true

    req = Net::HTTP::Post.new("#{uri.path}?#{uri.query}")
    req.body = payload.to_json

    response = http.request(req)
    verify_response(response)
  end

  def verify_response(response)
    case response
    when Net::HTTPSuccess
      true
    else
      fail response.error!
    end
  end

  def payload
    check_name = @event['check']['name']
    check_notification = @event['check']['notification']
    date_executed = @event['check']['executed']
    check_result = @event['check']['output']
    fallback_text = "#{check_notification} @ #{client_name} - #{date_executed}"
    check_text = "#{fallback_text}"
    check_result_value = "Result: #{check_result}"
    markdown_fields = ["text", "fields"]
    if (markdown_enabled)
      check_text = "*<#{sensu_server_url}#/events?q=#{check_name}|#{check_notification}>* @ *<#{sensu_server_url}/#/clients?q=#{client_name}|#{client_name}>* - `#{date_executed}`"
      check_result_value = "*Result*: `#{check_result}`"
      if sensu_server_url.to_s.strip.length == 0
        check_text = "*#{check_notification}* @ *#{client_name}* - `#{date_executed}`"
      end
    else
      markdown_fields = []
    end
    {
      channel: slack_channel,
      username: slack_bot_name,
      icon_url: 'http://sensuapp.org/img/sensu_logo_large-c92d73db.png',
      attachments: [{
        fallback: fallback_text,
        text: check_text,
        color: color,
        mrkdwn_in: markdown_fields,
        fields: [{
            value: check_result_value,
            short: false
          }]
      }]
    }.tap do |payload|
    end
  end

  def color
    color = {
      0 => '#36a64f',
      1 => '#FFCC00',
      2 => '#FF0000',
      3 => '#6600CC'
    }
    color.fetch(check_status.to_i)
  end

  def check_status
    @event['check']['status']
  end
end
