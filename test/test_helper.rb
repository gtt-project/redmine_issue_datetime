require File.expand_path('../../../test/test_helper', __dir__)

module IssueDatetimeTestHelper
  def enable_issue_datetime(tracker_ids, zone: 'UTC', step: '15')
    Setting.plugin_redmine_issue_datetime = {
      'tracker_ids' => Array(tracker_ids).map(&:to_s),
      'time_step' => step,
      'reference_zone' => zone
    }
  end
end
