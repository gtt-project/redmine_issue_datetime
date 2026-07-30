require File.expand_path('../test_helper', __dir__)

class ZoneLabelTest < ActiveSupport::TestCase
  include IssueDatetimeTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  def setup
    @issue = Issue.find(1)
  end

  test 'the label names the configured reference zone' do
    enable_issue_datetime(@issue.tracker_id, zone: 'Tokyo')

    assert_equal 'JST', RedmineIssueDatetime.zone_abbreviation(Time.utc(2026, 8, 3, 0, 0))
  end

  test 'UTC is labelled as UTC' do
    enable_issue_datetime(@issue.tracker_id, zone: 'UTC')

    assert_equal 'UTC', RedmineIssueDatetime.zone_abbreviation(Time.utc(2026, 8, 3, 0, 0))
  end

  # The abbreviation depends on the moment, which is why it takes one: a zone
  # with daylight saving reports a different name in summer and winter.
  test 'the label follows daylight saving for the given instant' do
    enable_issue_datetime(@issue.tracker_id, zone: 'Berlin')

    winter = RedmineIssueDatetime.zone_abbreviation(Time.utc(2026, 1, 15, 12, 0))
    summer = RedmineIssueDatetime.zone_abbreviation(Time.utc(2026, 7, 15, 12, 0))

    assert_not_equal winter, summer
  end

  # Times are deliberately shown on one clock for everyone rather than converted
  # per viewer, so a formatted time must not depend on User.current's zone.
  test 'formatting ignores the viewer time zone' do
    enable_issue_datetime(@issue.tracker_id, zone: 'Tokyo')
    at = Time.utc(2026, 8, 3, 0, 15)

    User.current = User.find(2)
    User.current.pref.update(time_zone: 'UTC')
    as_utc_user = RedmineIssueDatetime.format_time_of_day(at)
    User.current.pref.update(time_zone: 'Tokyo')
    as_tokyo_user = RedmineIssueDatetime.format_time_of_day(at)

    assert_equal '09:15', as_utc_user
    assert_equal as_utc_user, as_tokyo_user
  ensure
    User.current = nil
  end
end
