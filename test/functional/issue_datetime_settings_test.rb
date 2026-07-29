require File.expand_path('../test_helper', __dir__)

class IssueDatetimeSettingsTest < Redmine::ControllerTest
  tests SettingsController

  fixtures :projects, :users, :email_addresses, :roles, :trackers,
           :projects_trackers, :enabled_modules

  def setup
    @request.session[:user_id] = 1
  end

  test 'the plugin settings page renders' do
    get :plugin, params: {id: 'redmine_issue_datetime'}

    assert_response :success
    assert_select 'select[name=?]', 'settings[time_step]'
    assert_select 'select[name=?]', 'settings[reference_zone]'
    assert_select 'input[name=?]', 'settings[tracker_ids][]'
  end

  test 'saving the plugin settings works' do
    post :plugin, params: {
      id: 'redmine_issue_datetime',
      settings: {'tracker_ids' => ['', '1'], 'time_step' => '30', 'reference_zone' => 'Tokyo'}
    }

    assert_redirected_to '/settings/plugin/redmine_issue_datetime'
    assert RedmineIssueDatetime.enabled_for?(1)
    assert_not RedmineIssueDatetime.enabled_for?(2)
    assert_equal 30, RedmineIssueDatetime.time_step_minutes
    assert_equal 'Asia/Tokyo', RedmineIssueDatetime.reference_zone.tzinfo.name
  end
end
