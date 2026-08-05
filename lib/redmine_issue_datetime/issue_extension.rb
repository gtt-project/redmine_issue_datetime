module RedmineIssueDatetime
  # Adds the sidecar association and the mirror logic to Issue.
  #
  # The sync runs in two steps: journal details must be in place before
  # the core create_journal after_save callback writes the journal, so
  # the new timestamps are computed (and journalized) in before_save and
  # persisted to the sidecar row in after_save.
  module IssueExtension
    extend ActiveSupport::Concern

    included do
      has_one :issue_datetime, dependent: :destroy

      safe_attributes 'start_time', 'due_time', 'all_day',
                      if: ->(issue, _user) { RedmineIssueDatetime.enabled_for?(issue.tracker_id) }

      before_save :prepare_issue_datetime_sync
      after_save :persist_issue_datetime
    end

    def start_time=(value)
      @start_time_input = value
    end

    def due_time=(value)
      @due_time_input = value
    end

    # "All day" means "no times"; there is no stored flag. Setting it to
    # true clears both times. The flag is applied during the save, not
    # here, so it wins regardless of the order the attributes were
    # assigned in.
    def all_day=(value)
      @all_day_input = ActiveRecord::Type::Boolean.new.cast(value)
    end

    def all_day
      return @all_day_input unless @all_day_input.nil?

      issue_datetime.nil? || issue_datetime.blank_times?
    end
    alias all_day? all_day

    def start_time
      @start_time_input || RedmineIssueDatetime.format_time_of_day(issue_datetime&.starts_at)
    end

    def due_time
      @due_time_input || RedmineIssueDatetime.format_time_of_day(issue_datetime&.ends_at)
    end

    private

    def prepare_issue_datetime_sync
      @issue_datetime_pending = nil
      return unless RedmineIssueDatetime.enabled_for?(tracker_id)

      # Ticking "all day" clears both times, even if the (disabled) time
      # inputs still submitted stale values.
      if @all_day_input
        @start_time_input = ''
        @due_time_input = ''
      end

      # A copied issue has no sidecar row of its own yet, so use the
      # original's row as the source. This is what makes a copy keep its
      # times. Core exposes the original only as the @copied_from ivar
      # (its public API is just copy?).
      source = issue_datetime
      source ||= @copied_from.issue_datetime if new_record? && copy?
      return if source.nil? && @start_time_input.blank? && @due_time_input.blank?

      touched = !@start_time_input.nil? || !@due_time_input.nil? ||
                will_save_change_to_start_date? || will_save_change_to_due_date?
      return unless touched

      old_starts = source&.starts_at
      old_ends = source&.ends_at
      new_starts = RedmineIssueDatetime.combine(start_date, @start_time_input, old_starts)
      new_ends = RedmineIssueDatetime.combine(due_date, @due_time_input, old_ends)

      if new_starts && new_ends && new_ends < new_starts
        errors.add(:due_date, :greater_than_start_date)
        throw :abort
      end

      journalize_issue_datetime('start_time', old_starts, new_starts)
      journalize_issue_datetime('due_time', old_ends, new_ends)

      @issue_datetime_pending = {starts_at: new_starts, ends_at: new_ends}
    end

    def persist_issue_datetime
      pending = @issue_datetime_pending
      @issue_datetime_pending = nil
      @start_time_input = nil
      @due_time_input = nil
      @all_day_input = nil
      return if pending.nil?

      record = issue_datetime || build_issue_datetime
      record.assign_attributes(pending)
      if record.starts_at.nil? && record.ends_at.nil?
        record.destroy unless record.new_record?
        association(:issue_datetime).reset
      elsif record.changed?
        record.save!
      end
    end

    def journalize_issue_datetime(prop_key, old_value, new_value)
      return unless current_journal

      old_text = RedmineIssueDatetime.format_time_of_day(old_value)
      new_text = RedmineIssueDatetime.format_time_of_day(new_value)
      return if old_text == new_text

      current_journal.details << JournalDetail.new(
        property: 'attr', prop_key: prop_key,
        old_value: old_text, value: new_text
      )
    end
  end
end
