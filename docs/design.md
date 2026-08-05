# redmine_issue_datetime: Design Document

Status: As built (kept in step with the implementation)
Scope: Standalone Redmine plugin adding time of day to issue start and due dates

## 1. Problem

Redmine stores `issues.start_date` and `issues.due_date` as plain `date`
columns (see core migrations `001_setup.rb` and `005_issue_start_date.rb`).
There is no way to express *when* on a day an issue starts or ends. The
feature request is one of the oldest open issues in the tracker
([redmine.org #5458](https://www.redmine.org/issues/5458), open since 2010)
and has not moved because a change to the core schema ripples through
filters, Gantt, calendar, exports, parent/child rollup, and the REST API.

Existing workarounds use datetime custom fields
(`redmine_datetime_custom_field`, `redmine_datetime_cf` and similar). These
store values as strings in `custom_values`, have no semantic link to the
start/due fields, are hard to index and query, and create a second source of
truth.

## 2. Approach: parallel storage (sidecar table)

The plugin stores time of day in its own table and mirrors the date part
into the core columns. Core Redmine never changes.

Key invariant:

```
issues.start_date == issue_datetimes.starts_at (date part, in the configured zone)
issues.due_date   == issue_datetimes.ends_at   (date part, in the configured zone)
```

The core columns remain the authority for the *date*; the plugin is the
authority for the *time*. Everything in stock Redmine (filters, calendar,
core Gantt, CSV/PDF export, reminders, REST clients) keeps working
unchanged, because nothing about the core schema or serialization changes.

What this plugin is **not**:

- Not a scheduler or optimizer. It only stores and edits times.
- Not GIS-dependent. No relation to redmine_gtt. It is useful to any
  Redmine installation.

## 3. Data model

One new table, owned by the plugin:

```ruby
create_table :issue_datetimes do |t|
  t.references :issue, null: false, index: {unique: true}, foreign_key: true
  t.datetime :starts_at            # UTC
  t.datetime :ends_at              # UTC
  t.timestamps
end
```

Rules:

- No row for an issue means stock behavior (date only). This is the
  default for every existing and new issue.
- `starts_at` / `ends_at` may each be null independently (time set only on
  one side).
- Times are stored in UTC but always entered and displayed in one
  per-instance reference zone (plugin setting, default: the application
  default time zone), with a visible zone label. They are deliberately
  not converted to each viewer's personal time zone: for work that
  happens at a physical place, everyone must mean the same wall-clock
  time by "09:15". The same reference zone anchors the date mirror into
  `start_date` / `due_date`, so the date a user sees always matches the
  time they typed.
- Duration is intentionally not stored here. Redmine's existing
  `estimated_hours` already expresses effort/service duration and stays
  the single source for that.

## 4. Behavior

### Editing

- Setting a time creates or updates the sidecar row and mirrors the date
  part into the core column in the same save.
- Changing only the core date (via stock UI, bulk edit, or API) keeps the
  time of day and shifts the timestamp to the new date. The sync is an
  `ActiveSupport::Concern` included into `Issue` and runs in two steps:
  the new timestamps are computed and journalized in `before_save`
  (journal details must exist before core's own `create_journal`
  after_save callback writes the journal), and persisted to the sidecar
  row in `after_save`.
- Clearing the date clears the corresponding timestamp.
- Clearing the time (back to "all day") deletes or nulls the sidecar value;
  the core date stays.

### Journal

Time changes are journalized as detail entries (custom journal detail
keys), so issue history reflects them like any other field change.

### Copy / move

Issue copy duplicates the times: the copy keeps the same times of day,
re-anchored on its (possibly changed) dates. This is explicit in the
sync callback (a copied issue inherits the original's sidecar row as its
source); it does not come for free from Redmine's copy, which only
carries attributes.

### Parent/child

Redmine recalculates parent start/due dates from children. That rollup
stays date-only. Parents do not aggregate times in v1.

## 5. Configuration

- Enable per tracker (global plugin setting listing trackers), optionally
  restricted per project via a project module. An issue whose tracker is
  not enabled behaves exactly like stock Redmine and shows no time inputs.
- Time step for the input widget: default 15 minutes, configurable
  (5/10/15/30/60).
- Reference time zone for the date mirror (default: application zone).

## 6. UI

- Issue form: a `view_issues_form_details_bottom` hook renders
  `<input type="time" step="...">` next to the existing start/due date
  fields, plus a small "all day" toggle. Plain HTML time inputs, no JS
  date picker dependency.
- Issue view: a hook displays the times next to the dates when present.
- Issue list: an optional query column ("Start time", "End time") via
  `QueryColumn` registration. Filtering by time of day is out of scope for
  v1.

## 7. API

REST endpoints owned by the plugin (declared in the plugin's own routes,
JSON only) and not injected into the core issue representation:

```
GET    /issues/:issue_id/datetime.json
PUT    /issues/:issue_id/datetime.json   {"starts_at": "...", "ends_at": "..."}
DELETE /issues/:issue_id/datetime.json
```

Timestamps in ISO 8601 with offset. Permissions follow the issue: reading
requires issue visibility, writing requires edit permission on the issue.

Bulk read for consumers like schedulers:

```
GET /projects/:id/issue_datetimes.json?updated_since=...
```

## 8. Compatibility and risks

| Area | Impact |
| --- | --- |
| Core Gantt / calendar | Unchanged, day granularity as before |
| Filters ("due this week" etc.) | Unchanged, operate on core date columns |
| REST API for issues | Unchanged payloads, no client breakage |
| Reminders (`send_reminders`) | Unchanged, date-based |
| Other plugins reading dates | Unchanged, they see dates as before |
| Plugin uninstall | Drop one table, core data intact |
| Upstream #5458 ever landing | One-time script migrates sidecar values into core columns |

The main risk is drift between sidecar timestamps and core dates when other
code updates dates without going through ActiveRecord callbacks (raw SQL,
`update_column`). A consistency rake task
(`redmine_issue_datetime:check`) reports and optionally repairs drift.

## 9. Testing

- Model tests for the mirror invariant in both directions, null handling,
  time zone edges (date boundary around midnight in non-UTC zones), issue
  copy, and the drift check/repair.
- API tests for the endpoints, parsing rules, and permissions (including
  the note-only-permission case, which must not be allowed to write).
- CI matrix: Redmine 6.1 (Ruby 3.4) and 7.0 (Ruby 3.4 and 4.0) on
  PostgreSQL, plus a `zeitwerk:check` eager-loading gate.

## 10. Delivery

- Repository: new, standalone, not GTT-branded (`redmine_issue_datetime`).
- License: GPL-3.0 (matching the GTT Project plugins).
- Register on redmine.org plugin directory once 1.0 is stable.
- Consumers: `redmine_gtt_scheduler` (time windows), `redmine_canvas_gantt`
  (hour-level rendering), and external sync clients (for example QGIS or
  mobile field apps) via the bulk endpoint.
