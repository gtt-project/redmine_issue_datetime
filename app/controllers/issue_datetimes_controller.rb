class IssueDatetimesController < ApplicationController
  before_action :find_issue, only: [:show, :update, :destroy]
  before_action :require_edit_permission, only: [:update, :destroy]
  before_action :find_project, only: [:index]
  accept_api_auth :index, :show, :update, :destroy

  def show
    render json: issue_payload(@issue)
  end

  # Accepts {"starts_at": <iso8601|null>, "ends_at": <iso8601|null>}.
  # A timestamp sets both the core date and the time of day; null clears
  # the time of day and keeps the date. Omitted keys are left untouched.
  def update
    zone = RedmineIssueDatetime.reference_zone
    @issue.init_journal(User.current)

    [[:starts_at, :start_date, :start_time=], [:ends_at, :due_date, :due_time=]].each do |param, date_attr, time_writer|
      next unless params.key?(param)

      value = params[param]
      if value.present?
        timestamp = parse_timestamp(value)
        return render_parse_error(param) if timestamp.nil?

        local = timestamp.in_time_zone(zone)
        @issue.send(:"#{date_attr}=", local.to_date)
        @issue.send(time_writer, local.strftime('%H:%M'))
      else
        @issue.send(time_writer, '')
      end
    end

    if @issue.save
      render json: issue_payload(@issue.reload)
    else
      render json: {errors: @issue.errors.full_messages}, status: :unprocessable_entity
    end
  end

  # Clears the times (back to all-day); the core dates stay.
  def destroy
    @issue.init_journal(User.current)
    @issue.start_time = ''
    @issue.due_time = ''
    if @issue.save
      head :no_content
    else
      render json: {errors: @issue.errors.full_messages}, status: :unprocessable_entity
    end
  end

  # Bulk read for external consumers (schedulers, sync clients).
  def index
    unless User.current.allowed_to?(:view_issues, @project)
      return render_403
    end

    scope = IssueDatetime
            .joins(issue: :project)
            .where(issues: {project_id: @project.id})
            .where(Issue.visible_condition(User.current))
    if params[:updated_since].present?
      since = parse_timestamp(params[:updated_since])
      return render_parse_error(:updated_since) if since.nil?

      scope = scope.where('issue_datetimes.updated_at >= ?', since)
    end

    render json: {
      issue_datetimes: scope.order(:issue_id).map { |record| record_payload(record) }
    }
  end

  private

  def find_issue
    @issue = Issue.find(params[:issue_id])
    return render_403 unless @issue.visible?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def require_edit_permission
    return render_403 unless @issue.editable?
  end

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Requires an explicit offset (Z or +hh:mm) so API writes are
  # unambiguous regardless of the server's local time zone.
  def parse_timestamp(value)
    text = value.to_s
    return nil unless /(Z|[+-]\d{2}:?\d{2})\z/i.match?(text)

    Time.iso8601(text)
  rescue ArgumentError
    nil
  end

  def render_parse_error(param)
    render json: {errors: ["#{param} must be an ISO 8601 timestamp"]}, status: :unprocessable_entity
  end

  def issue_payload(issue)
    record = issue.issue_datetime
    {
      issue_id: issue.id,
      start_date: issue.start_date,
      due_date: issue.due_date,
      starts_at: record&.starts_at&.iso8601,
      ends_at: record&.ends_at&.iso8601,
      updated_at: record&.updated_at&.iso8601
    }
  end

  def record_payload(record)
    {
      issue_id: record.issue_id,
      starts_at: record.starts_at&.iso8601,
      ends_at: record.ends_at&.iso8601,
      updated_at: record.updated_at.iso8601
    }
  end
end
