module RedmineIssueDatetime
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_issues_form_details_bottom, partial: 'hooks/issue_datetime_form'
    render_on :view_issues_show_details_bottom, partial: 'hooks/issue_datetime_show'
  end
end
