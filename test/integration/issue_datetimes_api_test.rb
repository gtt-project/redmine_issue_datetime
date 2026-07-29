require File.expand_path('../test_helper', __dir__)

class IssueDatetimesApiTest < Redmine::ApiTest::Base
  include IssueDatetimeTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  def setup
    Setting.rest_api_enabled = '1'
    @issue = Issue.find(1)
    enable_issue_datetime(@issue.tracker_id)
  end

  test 'GET returns null times when no row exists' do
    get "/issues/#{@issue.id}/datetime.json", headers: credentials('jsmith')

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @issue.id, body['issue_id']
    assert_nil body['starts_at']
  end

  test 'PUT sets timestamps and mirrors the dates' do
    put "/issues/#{@issue.id}/datetime.json",
        params: {starts_at: '2026-08-03T09:15:00Z', ends_at: '2026-08-03T17:00:00Z'}.to_json,
        headers: {'Content-Type' => 'application/json'}.merge(credentials('jsmith'))

    assert_response :success
    @issue.reload
    assert_equal Date.new(2026, 8, 3), @issue.start_date
    assert_equal Time.utc(2026, 8, 3, 9, 15), @issue.issue_datetime.starts_at
    assert_equal Time.utc(2026, 8, 3, 17, 0), @issue.issue_datetime.ends_at
  end

  test 'PUT with null clears the time and keeps the date' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15',
                   due_date: Date.new(2026, 8, 3), due_time: '17:00')

    put "/issues/#{@issue.id}/datetime.json",
        params: {starts_at: nil}.to_json,
        headers: {'Content-Type' => 'application/json'}.merge(credentials('jsmith'))

    assert_response :success
    @issue.reload
    assert_equal Date.new(2026, 8, 3), @issue.start_date
    assert_nil @issue.issue_datetime.starts_at
    assert_equal Time.utc(2026, 8, 3, 17, 0), @issue.issue_datetime.ends_at
  end

  test 'PUT rejects malformed timestamps' do
    put "/issues/#{@issue.id}/datetime.json",
        params: {starts_at: 'tomorrow-ish'}.to_json,
        headers: {'Content-Type' => 'application/json'}.merge(credentials('jsmith'))

    assert_response :unprocessable_entity
  end

  test 'DELETE clears all times and keeps the dates' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15')

    delete "/issues/#{@issue.id}/datetime.json", headers: credentials('jsmith')

    assert_response :no_content
    @issue.reload
    assert_equal Date.new(2026, 8, 3), @issue.start_date
    assert_nil @issue.issue_datetime
  end

  test 'bulk endpoint lists rows for a project' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15')

    get "/projects/#{@issue.project.identifier}/issue_datetimes.json",
        headers: credentials('jsmith')

    assert_response :success
    rows = JSON.parse(response.body)['issue_datetimes']
    assert_equal [@issue.id], rows.map { |r| r['issue_id'] }
  end

  test 'anonymous users cannot write when login is required' do
    with_settings login_required: '1' do
      put "/issues/#{@issue.id}/datetime.json",
          params: {starts_at: '2026-08-03T09:15:00Z'}.to_json,
          headers: {'Content-Type' => 'application/json'}

      assert_response :unauthorized
    end
  end
end
