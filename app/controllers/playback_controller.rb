# frozen_string_literal: true

class PlaybackController < ApplicationController
  def index
    #parameters should come in the form
    #    {"playback_format"=>"presentation", "player_version"=>"2.3", "record_id"=>"15209c1759bc11ca0283af0e5d08e37a7848b74d-1624999602880"}

    # Lookup for recording
    recording = Recording.find_by!(record_id: playback_params[:record_id])

    cookie_name = "recording_#{recording.record_id}"
    expires = Time.now.utc + Rails.configuration.x.recording_cookie_ttl

    unless recording.protected?
      # If recording isn't protected, don't need to check tokens/cookies
      deliver_resource(request.host_with_port, request.method, expires)
      return
    end

    #Otherwise validate the token

  end

  def resource
    deliver_resource(request.host_with_port, request.method)
    return
  end

  private

  def playback_params
    params.permit(:playback_format, :player_version, :record_id)
  end

  def deliver_resource(host, method = 'GET', expires = nil)
    expires ||= Time.now.utc + Rails.configuration.x.recording_cookie_ttl

    resource_path = request.path
    static_resource_path = "static-resource#{resource_path}"

    response.headers['X-Accel-Redirect'] =
      "/#{static_resource_path}"

    head(:ok)
  end

end
