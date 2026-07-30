require File.expand_path('../test_helper', __dir__)

class AllDayTest < ActiveSupport::TestCase
  include IssueDatetimeTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  def setup
    @issue = Issue.find(1)
    enable_issue_datetime(@issue.tracker_id)
  end

  test 'an issue with no times reports itself as all day' do
    assert @issue.all_day
  end

  test 'an issue with a time does not report itself as all day' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15')

    assert_not @issue.reload.all_day
  end

  test 'ticking all day clears both times and keeps the dates' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15',
                   due_date: Date.new(2026, 8, 4), due_time: '17:00')

    @issue.reload
    @issue.all_day = '1'
    assert @issue.save

    @issue.reload
    assert_nil @issue.issue_datetime
    assert_equal Date.new(2026, 8, 3), @issue.start_date
    assert_equal Date.new(2026, 8, 4), @issue.due_date
  end

  # The time inputs are disabled in the browser when the box is ticked, but a
  # stale or hand-crafted submission could still carry values. The flag has to
  # win, or ticking "all day" would appear to do nothing.
  test 'ticking all day beats time values submitted alongside it' do
    @issue.start_date = Date.new(2026, 8, 3)
    @issue.start_time = '09:15'
    @issue.due_date = Date.new(2026, 8, 3)
    @issue.due_time = '17:00'
    @issue.all_day = '1'

    assert @issue.save
    assert_nil @issue.reload.issue_datetime
  end

  test 'the flag wins regardless of assignment order' do
    @issue.all_day = '1'
    @issue.start_date = Date.new(2026, 8, 3)
    @issue.start_time = '09:15'

    assert @issue.save
    assert_nil @issue.reload.issue_datetime
  end

  test 'unticking all day does not by itself invent times' do
    @issue.update!(start_date: Date.new(2026, 8, 3))

    @issue.reload
    @issue.all_day = '0'
    assert @issue.save

    assert_nil @issue.reload.issue_datetime
  end

  test 'clearing all day and setting a time in one save keeps the time' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15')

    @issue.reload
    @issue.all_day = '0'
    @issue.start_time = '10:30'
    assert @issue.save

    assert_equal Time.utc(2026, 8, 3, 10, 30), @issue.reload.issue_datetime.starts_at
  end

  test 'all_day is only writable for enabled trackers' do
    enable_issue_datetime([])
    @issue.update!(start_date: Date.new(2026, 8, 3))

    assert_not @issue.safe_attribute_names.include?('all_day')
  end
end
