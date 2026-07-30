require File.expand_path('../test_helper', __dir__)

class DatetimeFormatTest < ActiveSupport::TestCase
  include IssueDatetimeTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles, :custom_fields, :custom_values

  def setup
    enable_issue_datetime(Issue.find(1).tracker_id, zone: 'Tokyo')
    @field = IssueCustomField.create!(name: 'Inspection at', field_format: 'datetime',
                                      is_for_all: true, tracker_ids: Tracker.pluck(:id))
    @issue = Issue.find(1)
  end

  test 'the format is registered and offered alongside date' do
    names = Redmine::FieldFormat.available_formats

    assert_includes names, 'datetime'
    assert_includes names, 'date', 'the built-in date format must remain available'
  end

  test 'the format is labelled for the picker' do
    assert_equal 'label_datetime', Redmine::FieldFormat.find('datetime').label
  end

  test 'a naive local value round-trips through the custom field' do
    @issue.custom_field_values = {@field.id.to_s => '2026-08-03T09:15'}

    assert @issue.save
    assert_equal '2026-08-03T09:15', @issue.reload.custom_field_value(@field)
  end

  # Stored naive, interpreted in the reference zone: the cast must land on the
  # same wall clock the user typed, not shift it.
  test 'casting interprets the stored value in the reference zone' do
    cast = @field.format.cast_single_value(@field, '2026-08-03T09:15')

    assert_equal 'Asia/Tokyo', cast.time_zone.tzinfo.name
    assert_equal '09:15', cast.strftime('%H:%M')
    assert_equal Time.utc(2026, 8, 3, 0, 15), cast.utc
  end

  test 'a value without a time is rejected' do
    @issue.custom_field_values = {@field.id.to_s => '2026-08-03'}

    assert_not @issue.save
  end

  test 'a value with a zone offset is rejected, since storage is naive' do
    @issue.custom_field_values = {@field.id.to_s => '2026-08-03T09:15+09:00'}

    assert_not @issue.save
  end

  test 'an impossible time is rejected' do
    @issue.custom_field_values = {@field.id.to_s => '2026-08-03T25:99'}

    assert_not @issue.save
  end

  test 'a blank value is allowed when the field is not required' do
    @issue.custom_field_values = {@field.id.to_s => ''}

    assert @issue.save
  end

  # The year must always be present: a locale default such as :short renders
  # "03 Aug 09:15", which is ambiguous for anything not in the current year.
  test 'formatting shows the full date and the time' do
    formatted = @field.format.formatted_value(nil, @field, '2026-08-03T09:15')

    assert_includes formatted, '09:15'
    assert_includes formatted, '2026'
  end

  test 'formatting honours the admin date and time settings' do
    with_settings date_format: '%d/%m/%Y', time_format: '%H:%M' do
      assert_equal '03/08/2026 09:15',
                   @field.format.formatted_value(nil, @field, '2026-08-03T09:15')
    end
  end

  # Values are shown on one clock for everyone, so formatting must not follow the
  # viewer's own time zone the way Redmine's format_time helper would.
  test 'formatting does not follow the viewer time zone' do
    # Captured before anything that can raise, so the ensure block always
    # restores rather than assuming what the surrounding state was.
    previous_user = User.current
    user = User.find(2)
    original_zone = user.pref.time_zone
    User.current = user
    user.pref.update(time_zone: 'UTC')

    assert_includes @field.format.formatted_value(nil, @field, '2026-08-03T09:15'), '09:15'
  ensure
    user&.pref&.update(time_zone: original_zone)
    User.current = previous_user
  end

  test 'formatting a blank value yields an empty string, not an error' do
    assert_equal '', @field.format.formatted_value(nil, @field, '')
  end

  # ISO 8601 sorts correctly as a plain string, which is why storage uses it:
  # ordering needs no special casing.
  test 'stored values sort chronologically as strings' do
    values = ['2026-08-03T09:15', '2026-08-03T08:00', '2026-01-15T23:59', '2026-08-03T10:00']

    assert_equal ['2026-01-15T23:59', '2026-08-03T08:00', '2026-08-03T09:15', '2026-08-03T10:00'],
                 values.sort
  end

  test 'the filter is declared as a datetime so the framework can filter on it' do
    assert_equal({type: :datetime}, @field.format.query_filter_options(@field, nil))
  end

  # Unlike the start/due times, an arbitrary datetime field is not forced onto
  # the interval grid: it may legitimately record an off-grid moment.
  test 'an off-grid minute is accepted' do
    @issue.custom_field_values = {@field.id.to_s => '2026-08-03T09:07'}

    assert @issue.save
    assert_equal '2026-08-03T09:07', @issue.reload.custom_field_value(@field)
  end
end
