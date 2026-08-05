require File.expand_path('../test_helper', __dir__)

class IssueQueryColumnsTest < ActiveSupport::TestCase
  include IssueDatetimeTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles, :versions, :issue_categories

  def setup
    User.current = User.find(1)
    @issue = Issue.find(1)
    enable_issue_datetime(@issue.tracker_id)
  end

  def teardown
    User.current = nil
  end

  def column_names_of(query)
    query.available_columns.map(&:name)
  end

  test 'the time columns are offered when the plugin is enabled somewhere' do
    names = column_names_of(IssueQuery.new)

    assert_includes names, :start_time
    assert_includes names, :due_time
  end

  test 'the time columns are not offered when no tracker is enabled' do
    enable_issue_datetime([])

    names = column_names_of(IssueQuery.new)

    assert_not_includes names, :start_time
    assert_not_includes names, :due_time
  end

  test 'the columns are not added twice when available_columns is called again' do
    query = IssueQuery.new
    query.available_columns

    assert_equal 1, column_names_of(query).count(:start_time)
  end

  test 'the column renders the time of an issue that has one' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15')
    query = IssueQuery.new(project: @issue.project, column_names: [:subject, :start_time])

    issue = query.issues.detect { |i| i.id == @issue.id }

    assert_equal '09:15', issue.start_time
  end

  test 'the column is blank for an issue without a time' do
    query = IssueQuery.new(project: @issue.project, column_names: [:subject, :start_time])

    issue = query.issues.detect { |i| i.id == @issue.id }

    assert_nil issue.start_time
  end

  # The sidecar row is read per issue, so without preloading a list of N issues
  # costs N extra queries. QueryColumn has no :preload option, hence the override.
  test 'selecting a time column preloads the sidecar rows' do
    @issue.update!(start_date: Date.new(2026, 8, 3), start_time: '09:15')
    query = IssueQuery.new(project: @issue.project, column_names: [:subject, :start_time])

    issues = query.issues

    assert issues.any?
    assert issues.all? { |i| i.association(:issue_datetime).loaded? },
           'issue_datetime should be preloaded when a time column is selected'
  end

  test 'no preloading happens when no time column is selected' do
    query = IssueQuery.new(project: @issue.project, column_names: [:subject])

    issues = query.issues

    assert issues.any?
    assert issues.none? { |i| i.association(:issue_datetime).loaded? }
  end

  # column_names is nil for a query on default columns - the normal state, see
  # Query#has_default_columns? - and must not crash the issues override (#22).
  test 'a query on default columns runs without error' do
    query = IssueQuery.new(project: @issue.project)
    assert_nil query.column_names

    assert query.issues.any?
  end

  test 'time columns in the instance default columns still preload' do
    # column_names stays nil, but the effective columns include start_time, so
    # the sidecar preload must kick in for the rendered list.
    with_settings issue_list_default_columns: %w[subject start_time] do
      query = IssueQuery.new(project: @issue.project)
      assert_nil query.column_names

      issues = query.issues

      assert issues.any?
      assert issues.all? { |i| i.association(:issue_datetime).loaded? }
    end
  end

  test 'the columns are not sortable, rather than sorting by nothing' do
    query = IssueQuery.new
    start_time = query.available_columns.detect { |c| c.name == :start_time }

    assert_not start_time.sortable
  end
end
