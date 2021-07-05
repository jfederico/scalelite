require 'test_helper'

class PlaybackControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get playback_index_url
    assert_response :success
  end

end
