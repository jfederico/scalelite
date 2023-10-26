# frozen_string_literal: true

require 'concurrent-ruby'
require 'mqtt'

## Hack: hardcoded values for message broker prtotype
mqtt = {
  host: '10.130.218.177',
  port: 1883,
  user: 'user1',
  pass: 'password'
}

desc 'Run a listening process to continually process push messages with updates on servers and meetings'
task :listen, [:interval] => :environment do |_t, args|
  args.with_defaults(interval: 15.seconds)
  interval = args.interval.to_f
  Rails.logger.info("Running listener")

  MQTT::Client.connect("mqtt://#{mqtt[:user]}:#{mqtt[:pass]}@#{mqtt[:host]}:#{mqtt[:port]}") do |client|
    topic = 'bigbluebutton/meetingInfo'  # Replace with the topic you want to subscribe to

    # Subscribe to the topic
    client.get(topic) do |topic, message|
      Rails.logger.info("Received message on topic '#{topic}': #{message}")
    end

    ## Publish a message to the topic (optional)
    #client.publish(topic, 'Hello, MQTT!')
  end

  loop do
    Rails.logger.info("Listening...")

    sleep(interval)
  end
rescue SignalException => e
  Rails.logger.info("Exiting listener on signal: #{e}")
end
