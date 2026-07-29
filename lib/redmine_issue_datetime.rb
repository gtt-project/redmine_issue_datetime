require_relative 'redmine_issue_datetime/issue_extension'
require_relative 'redmine_issue_datetime/hooks'

module RedmineIssueDatetime
  TIME_OF_DAY = /\A([01]?\d|2[0-3]):([0-5]\d)\z/

  def self.setup
    Issue.include(IssueExtension) unless Issue.include?(IssueExtension)
  end

  def self.settings
    Setting.plugin_redmine_issue_datetime
  end

  def self.enabled_for?(tracker_id)
    return false if tracker_id.blank?

    Array(settings['tracker_ids']).reject(&:blank?).map(&:to_i).include?(tracker_id.to_i)
  end

  def self.time_step_minutes
    step = settings['time_step'].to_i
    step.positive? ? step : 15
  end

  def self.time_step_seconds
    time_step_minutes * 60
  end

  # The zone used to derive the date part mirrored into the core
  # start_date/due_date columns. Falls back to the application zone.
  def self.reference_zone
    ActiveSupport::TimeZone[settings['reference_zone'].to_s] ||
      Time.zone ||
      ActiveSupport::TimeZone['UTC']
  end

  def self.format_time_of_day(timestamp)
    timestamp && timestamp.in_time_zone(reference_zone).strftime('%H:%M')
  end

  # Combines a core date with a submitted time-of-day input.
  #
  #   date      the issue's start_date or due_date (may be nil)
  #   input     "HH:MM" to set, "" to clear, nil when not submitted
  #   previous  the currently stored timestamp (may be nil)
  #
  # When no input was submitted, the stored time of day is kept and
  # re-anchored on the (possibly changed) date. Unparsable input is
  # treated as not submitted.
  def self.combine(date, input, previous)
    return nil if date.nil?

    submitted = input.nil? ? nil : input.to_s.strip
    return nil if submitted == ''

    match = submitted && TIME_OF_DAY.match(submitted)
    hour, minute =
      if match
        [match[1].to_i, match[2].to_i]
      elsif previous
        prev = previous.in_time_zone(reference_zone)
        [prev.hour, prev.min]
      end
    return nil if hour.nil?

    reference_zone.local(date.year, date.month, date.day, hour, minute)
  end
end
