require_relative 'redmine_issue_datetime/drift_check'
require_relative 'redmine_issue_datetime/datetime_format'
require_relative 'redmine_issue_datetime/issue_extension'
require_relative 'redmine_issue_datetime/issue_query_extension'
require_relative 'redmine_issue_datetime/hooks'

module RedmineIssueDatetime
  TIME_OF_DAY = /\A([01]?\d|2[0-3]):([0-5]\d)\z/

  def self.setup
    Issue.include(IssueExtension) unless Issue.include?(IssueExtension)
    IssueQuery.prepend(IssueQueryExtension) unless IssueQuery.include?(IssueQueryExtension)
  end

  # Whether the plugin is switched on for any tracker at all. Used to keep the
  # optional list columns out of the column picker on an instance that has not
  # enabled the plugin anywhere.
  def self.any_tracker_enabled?
    enabled_tracker_ids.any?
  end

  def self.settings
    Setting.plugin_redmine_issue_datetime
  end

  # The tracker ids the plugin is enabled for. The setting is stored as an
  # array of strings and contains a blank entry from the form's hidden field.
  def self.enabled_tracker_ids
    Array(settings['tracker_ids']).reject(&:blank?).map(&:to_i)
  end

  def self.enabled_for?(tracker_id)
    return false if tracker_id.blank?

    enabled_tracker_ids.include?(tracker_id.to_i)
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

  # Zone labels for the UI.
  #
  # Times are always shown on one clock, the instance's reference zone, never
  # converted to each viewer's own zone. For work that happens at a physical
  # place, everyone must mean the same wall-clock time by "09:15", and the
  # visible zone label is what makes that unambiguous.
  #
  # There are two label methods because the correct label depends on context:
  #
  # - zone_abbreviation(at) is daylight-saving aware, so it requires the
  #   instant being displayed (deliberately no default: "now" would be wrong
  #   for a time in another part of the year). Use it next to a specific time.
  # - zone_name is season-independent. Use it where many dates are covered,
  #   or none yet: list headers, empty forms.
  def self.zone_abbreviation(at)
    at.in_time_zone(reference_zone).strftime('%Z')
  end

  def self.zone_name
    reference_zone.name
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
        snap_to_step((match[1].to_i * 60) + match[2].to_i).divmod(60)
      elsif previous
        prev = previous.in_time_zone(reference_zone)
        [prev.hour, prev.min]
      end
    return nil if hour.nil?

    reference_zone.local(date.year, date.month, date.day, hour, minute)
  end

  # Rounds minutes-since-midnight to the nearest configured interval, so a
  # value typed past the widget (or sent to the API) still lands on the grid
  # the scheduler and the picker use. Clamped so rounding up from the last
  # slot cannot roll over into the next day, which the date field could not
  # express.
  def self.snap_to_step(minutes)
    step = time_step_minutes
    return minutes if step <= 1

    snapped = (minutes.to_f / step).round * step
    last = ((23 * 60) + 59) / step * step
    snapped > last ? last : snapped
  end
end
