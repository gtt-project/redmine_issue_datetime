module RedmineIssueDatetime
  # Adds optional "Start time" / "Due time" columns to the issue list.
  #
  # The columns read Issue#start_time / #due_time, which come from the sidecar
  # row, so the scope has to preload it or a list of N issues costs N extra
  # queries. QueryColumn has no :preload option, hence the override of #issues.
  #
  # Not sortable: ordering would need the query to join issue_datetimes, and a
  # column that silently sorts by nothing is worse than one that plainly does
  # not offer it. Filtering by time of day is out of scope (see the design doc).
  module IssueQueryExtension
    extend ActiveSupport::Concern

    COLUMN_NAMES = %i[start_time due_time].freeze

    def available_columns
      columns = super
      return columns if @issue_datetime_columns_added

      @issue_datetime_columns_added = true
      return columns unless RedmineIssueDatetime.any_tracker_enabled?

      columns << QueryColumn.new(:start_time, caption: :field_start_time, inline: true)
      columns << QueryColumn.new(:due_time, caption: :field_due_time, inline: true)
      columns
    end

    # Redmine's own options[:include] is folded into the scope's `includes`, so
    # the association is loaded up front without this having to touch
    # ActiveRecord's Preloader directly.
    def issues(options = {})
      return super unless (column_names & COLUMN_NAMES).any?

      super(options.merge(include: Array(options[:include]) + [:issue_datetime]))
    end
  end
end
