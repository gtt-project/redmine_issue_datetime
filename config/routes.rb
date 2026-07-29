RedmineApp::Application.routes.draw do
  get 'issues/:issue_id/datetime', to: 'issue_datetimes#show',
      constraints: {issue_id: /\d+/}, as: 'issue_datetime'
  put 'issues/:issue_id/datetime', to: 'issue_datetimes#update',
      constraints: {issue_id: /\d+/}
  delete 'issues/:issue_id/datetime', to: 'issue_datetimes#destroy',
         constraints: {issue_id: /\d+/}
  get 'projects/:project_id/issue_datetimes', to: 'issue_datetimes#index',
      as: 'project_issue_datetimes'
end
