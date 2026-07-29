require_relative 'lib/redmine_issue_datetime'

Redmine::Plugin.register :redmine_issue_datetime do
  name 'Redmine Issue Datetime'
  author 'GTT Project'
  description 'Adds time of day to issue start and due dates without changing the core schema'
  version '0.1.0'
  url 'https://github.com/gtt-project/redmine_issue_datetime'
  author_url 'https://github.com/gtt-project'
  requires_redmine version_or_higher: '6.0'

  settings partial: 'settings/redmine_issue_datetime',
           default: {
             'tracker_ids' => [],
             'time_step' => '15',
             'reference_zone' => ''
           }
end

RedmineIssueDatetime.setup
