require File.expand_path('../test_helper', __dir__)

class IssueCopyTest < ActiveSupport::TestCase
  include IssueDatetimeTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  def setup
    @issue = Issue.find(1)
    enable_issue_datetime(@issue.tracker_id)
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15',
                   due_date: Date.new(2026, 8, 4), due_time: '17:00')
    @issue.reload
  end

  # The sidecar row is an association, so Redmine's issue copy does not carry
  # it over by itself; the copy support in IssueExtension does.
  test 'copying an issue keeps its times' do
    copy = @issue.copy
    assert copy.save

    record = copy.reload.issue_datetime
    assert_not_nil record, 'the copy must get its own sidecar row'
    assert_equal Time.utc(2026, 8, 3, 9, 15), record.starts_at
    assert_equal Time.utc(2026, 8, 4, 17, 0), record.ends_at
  end

  test 'a copy with changed dates keeps the times of day' do
    copy = @issue.copy
    copy.start_date = Date.new(2026, 9, 1)
    copy.due_date = Date.new(2026, 9, 2)
    assert copy.save

    record = copy.reload.issue_datetime
    assert_equal Time.utc(2026, 9, 1, 9, 15), record.starts_at
    assert_equal Time.utc(2026, 9, 2, 17, 0), record.ends_at
  end

  test 'copying an all-day issue stays all day' do
    @issue.all_day = '1'
    assert @issue.save

    copy = @issue.reload.copy
    assert copy.save
    assert_nil copy.reload.issue_datetime
  end

  test 'times set while copying win over the inherited ones' do
    copy = @issue.copy
    copy.start_time = '10:30'
    assert copy.save

    assert_equal Time.utc(2026, 8, 3, 10, 30), copy.reload.issue_datetime.starts_at
  end

  test 'the original keeps its own row untouched' do
    copy = @issue.copy
    assert copy.save

    assert_not_equal @issue.reload.issue_datetime.id, copy.reload.issue_datetime.id
    assert_equal Time.utc(2026, 8, 3, 9, 15), @issue.issue_datetime.starts_at
  end
end
