# frozen_string_literal: true

namespace :delayed_job do
  desc('start delayedjob')
  task start: :environment do
    bundle exec('./bin/delayed_job start')
  end

  desc('stop delayedjob')
  task stop: :environment do
    bundle exec('./bin/delayed_job stop')
  end
end
