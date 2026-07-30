require File.expand_path('../test_helper', __dir__)

class DriftCheckTest < ActiveSupport::TestCase
  include IssueDatetimeTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  Check = RedmineIssueDatetime::DriftCheck

  def setup
    @issue = Issue.find(1)
    enable_issue_datetime(@issue.tracker_id)
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15',
                   due_date: Date.new(2026, 8, 4), due_time: '17:00')
    @issue.reload
  end

  # Drift can only be created by bypassing the callbacks, which is precisely the
  # situation the task exists for.
  def drift_date!(field, date)
    @issue.update_column(field, date)
  end

  test 'a consistent issue produces no findings' do
    assert_empty Check.new.findings
  end

  test 'a start date moved behind the callbacks is reported' do
    drift_date!(:start_date, Date.new(2026, 8, 10))

    findings = Check.new.findings

    assert_equal 1, findings.size
    assert_equal 'start', findings.first.field
    assert_equal Check::DATE_MISMATCH, findings.first.reason
    assert_equal @issue.id, findings.first.issue_id
  end

  test 'both fields drifting are reported separately' do
    drift_date!(:start_date, Date.new(2026, 8, 10))
    drift_date!(:due_date, Date.new(2026, 8, 11))

    assert_equal %w[due start], Check.new.findings.map(&:field).sort
  end

  test 'a stored time whose date was cleared is reported as an orphan' do
    drift_date!(:start_date, nil)

    findings = Check.new.findings

    assert_equal 1, findings.size
    assert_equal Check::ORPHAN_TIME, findings.first.reason
  end

  test 'repair re-derives the date from the timestamp' do
    drift_date!(:start_date, Date.new(2026, 8, 10))

    repaired = Check.new.repair!

    assert_equal 1, repaired.size
    # The timestamp is the more specific value, so the date follows it.
    assert_equal Date.new(2026, 8, 3), @issue.reload.start_date
    assert_equal Time.utc(2026, 8, 3, 9, 15), @issue.issue_datetime.starts_at
    assert_empty Check.new.findings
  end

  test 'repair clears an orphaned time rather than inventing a date' do
    drift_date!(:start_date, nil)

    Check.new.repair!

    @issue.reload
    assert_nil @issue.start_date
    assert_nil @issue.issue_datetime.starts_at
    # The due half is untouched.
    assert_equal Time.utc(2026, 8, 4, 17, 0), @issue.issue_datetime.ends_at
    assert_empty Check.new.findings
  end

  test 'repairing the last remaining time removes the sidecar row' do
    @issue.update!(due_time: '')
    @issue.reload
    drift_date!(:start_date, nil)

    Check.new.repair!

    assert_nil @issue.reload.issue_datetime
  end

  test 'repair does not journalize or touch updated_on' do
    before = @issue.updated_on
    drift_date!(:start_date, Date.new(2026, 8, 10))
    journals = @issue.journals.count

    Check.new.repair!

    @issue.reload
    assert_equal journals, @issue.journals.count
    assert_equal before.to_i, @issue.updated_on.to_i
  end

  test 'repair is idempotent' do
    drift_date!(:start_date, Date.new(2026, 8, 10))

    Check.new.repair!

    assert_empty Check.new.repair!
  end

  test 'the reference zone decides what counts as drift' do
    # Only the start half here, so the assertion is about the zone and nothing
    # else. 23:30 UTC on Aug 3 is 08:30 on Aug 4 in Tokyo, so which core date is
    # correct depends on the zone: reading it in the wrong one invents drift.
    @issue.update!(due_time: '')
    @issue.reload
    @issue.issue_datetime.update_column(:starts_at, Time.utc(2026, 8, 3, 23, 30))
    @issue.update_column(:start_date, Date.new(2026, 8, 4))

    assert_empty Check.new(zone: ActiveSupport::TimeZone['Tokyo']).findings
    assert_equal 1, Check.new(zone: ActiveSupport::TimeZone['UTC']).findings.size
  end

  # A corollary of the above worth pinning: changing the reference_zone setting
  # after times are stored makes existing rows drift, because the core date was
  # derived under the old zone. The task is how an admin finds that out.
  test 'changing the reference zone surfaces existing rows as drift' do
    assert_empty Check.new.findings

    tokyo = Check.new(zone: ActiveSupport::TimeZone['Tokyo']).findings

    # Only the times that cross midnight in the new zone drift: 09:15 UTC is
    # still Aug 3 in Tokyo (18:15), while 17:00 UTC on Aug 4 becomes Aug 5.
    assert_equal ['due'], tokyo.map(&:field)
    assert_equal Check::DATE_MISMATCH, tokyo.first.reason
  end

end
