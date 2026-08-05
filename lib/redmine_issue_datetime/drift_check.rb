module RedmineIssueDatetime
  # Finds and optionally repairs sidecar rows that no longer agree with the core
  # date columns.
  #
  # The mirror is maintained by ActiveRecord callbacks, so anything that bypasses
  # them puts the two out of step: raw SQL, update_column/update_all, a restored
  # database, or a bulk operation in another plugin. Nothing in normal use should
  # produce drift, which is exactly why it needs a way to be checked rather than
  # assumed.
  class DriftCheck
    # An issue whose stored timestamp disagrees with its core date.
    Finding = Struct.new(:issue_id, :field, :date, :timestamp, :reason, keyword_init: true) do
      def to_s
        "issue ##{issue_id} #{field}: #{reason} " \
          "(date=#{date.inspect}, stored=#{timestamp&.iso8601.inspect})"
      end
    end

    DATE_MISMATCH = 'date does not match the stored timestamp'.freeze
    ORPHAN_TIME = 'a time is stored but the date is empty'.freeze

    FIELDS = [
      {time: :starts_at, date: :start_date, name: 'start'},
      {time: :ends_at, date: :due_date, name: 'due'}
    ].freeze

    def initialize(zone: RedmineIssueDatetime.reference_zone)
      @zone = zone
    end

    # Every disagreement, ordered by issue then field.
    #
    # The scan is batched so a large instance never loads every row at once.
    # It is deliberately unordered: find_each batches by primary key and
    # silently ignores an order clause (or raises when
    # ActiveRecord.error_on_ignored_order is set). Sorting the few findings
    # at the end is cheap and, unlike an order clause here, actually applied.
    def findings
      results = []
      IssueDatetime.includes(:issue).find_each(batch_size: 500) do |record|
        # A foreign key makes an orphaned row impossible in practice; the guard
        # is here so a database whose constraint was dropped degrades to skipping
        # the row rather than raising mid-scan.
        issue = record.issue
        next if issue.nil?

        FIELDS.each do |field|
          finding = compare(record, issue, field)
          results << finding if finding
        end
      end
      results.sort_by { |finding| [finding.issue_id, finding.field] }
    end

    # Repairs by re-deriving the core date from the stored timestamp, because the
    # timestamp is the more specific value: it carries the time of day, which the
    # date cannot express. A stored time whose date is empty is cleared instead,
    # since "a time on no date" has no meaning.
    #
    # Uses update_column deliberately: this must not fire the mirror callbacks it
    # is repairing, nor bump updated_on, nor create a journal entry for a
    # correction the user did not make.
    def repair!
      repaired = findings
      repaired.group_by(&:issue_id).each do |issue_id, group|
        issue = Issue.find_by(id: issue_id)
        next if issue.nil?

        group.each { |finding| apply_repair(issue, finding) }
      end
      repaired
    end

    private

    def compare(record, issue, field)
      timestamp = record.public_send(field[:time])
      date = issue.public_send(field[:date])
      return nil if timestamp.nil?

      if date.nil?
        Finding.new(issue_id: issue.id, field: field[:name], date: nil,
                    timestamp: timestamp, reason: ORPHAN_TIME)
      elsif timestamp.in_time_zone(@zone).to_date != date
        Finding.new(issue_id: issue.id, field: field[:name], date: date,
                    timestamp: timestamp, reason: DATE_MISMATCH)
      end
    end

    def apply_repair(issue, finding)
      field = FIELDS.detect { |f| f[:name] == finding.field }
      record = issue.issue_datetime
      return if record.nil?

      if finding.reason == ORPHAN_TIME
        record.update_column(field[:time], nil)
        record.destroy if record.reload.blank_times?
      else
        issue.update_column(field[:date], finding.timestamp.in_time_zone(@zone).to_date)
      end
    end
  end
end
