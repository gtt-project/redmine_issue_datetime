require File.expand_path('../test_helper', __dir__)

class IssueDatetimeSyncTest < ActiveSupport::TestCase
  include IssueDatetimeTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  def setup
    @issue = Issue.find(1)
    enable_issue_datetime(@issue.tracker_id)
  end

  test 'setting a time creates the sidecar row and keeps the date mirrored' do
    @issue.start_date = Date.new(2026, 8, 3)
    @issue.start_time = '09:15'
    assert @issue.save

    record = @issue.reload.issue_datetime
    assert_not_nil record
    assert_equal Time.utc(2026, 8, 3, 9, 15), record.starts_at
    assert_equal Date.new(2026, 8, 3), @issue.start_date
  end

  test 'changing the date keeps the time of day' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15')

    @issue.reload
    @issue.start_date = Date.new(2026, 8, 5)
    assert @issue.save
    assert_equal Time.utc(2026, 8, 5, 9, 15), @issue.reload.issue_datetime.starts_at
  end

  test 'clearing the date clears the timestamp' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15',
                   due_date: Date.new(2026, 8, 4), due_time: '17:00')

    @issue.reload
    @issue.start_date = nil
    assert @issue.save
    record = @issue.reload.issue_datetime
    assert_nil record.starts_at
    assert_equal Time.utc(2026, 8, 4, 17, 0), record.ends_at
  end

  test 'clearing all times removes the sidecar row' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15')

    @issue.reload
    @issue.start_time = ''
    assert @issue.save
    assert_nil @issue.reload.issue_datetime
  end

  test 'time changes are journalized' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15')

    @issue.reload
    @issue.init_journal(User.find(2))
    @issue.start_time = '10:30'
    assert @issue.save

    detail = @issue.journals.last.details.find { |d| d.prop_key == 'start_time' }
    assert_not_nil detail
    assert_equal '09:15', detail.old_value
    assert_equal '10:30', detail.value
  end

  test 'time input is ignored for disabled trackers' do
    enable_issue_datetime([])
    @issue.start_date = Date.new(2026, 8, 3)
    @issue.start_time = '09:15'
    assert @issue.save
    assert_nil @issue.reload.issue_datetime
  end

  test 'reference zone anchors the mirrored date' do
    enable_issue_datetime(@issue.tracker_id, zone: 'Tokyo')
    @issue.start_date = Date.new(2026, 8, 3)
    @issue.start_time = '09:15'
    assert @issue.save

    record = @issue.reload.issue_datetime
    assert_equal Time.utc(2026, 8, 3, 0, 15), record.starts_at
    assert_equal '09:15', RedmineIssueDatetime.format_time_of_day(record.starts_at)
  end

  test 'invalid time input keeps the stored time' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15')

    @issue.reload
    @issue.start_time = 'not a time'
    assert @issue.save
    assert_equal Time.utc(2026, 8, 3, 9, 15), @issue.reload.issue_datetime.starts_at
  end

  test 'destroying the issue destroys the sidecar row' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15')
    record_id = @issue.reload.issue_datetime.id

    @issue.destroy
    assert_nil IssueDatetime.find_by(id: record_id)
  end
end
