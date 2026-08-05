# redmine_issue_datetime

A Redmine plugin that adds a time of day to issue start and due dates,
without changing the Redmine core schema.

Redmine stores `start_date` and `due_date` as plain dates. Adding a time
has been requested for a long time
([redmine.org #5458](https://www.redmine.org/issues/5458), open since
2010). This plugin solves it with parallel storage: times live in a
plugin-owned table, and the date part is mirrored into the core columns.
Filters, calendar, Gantt, exports, and the REST API keep working exactly
as before, and an issue without times behaves exactly like stock Redmine.

## Features

- Time inputs next to the start and due date fields on the issue form,
  with a configurable step (15 minutes by default) and an "All day"
  toggle
- Enabled per tracker; issues of other trackers are untouched
- Time changes appear in the issue history (journal)
- Optional "Start time" / "Due time" columns on the issue list
- A "Date and time" custom field format, offered alongside the built-in
  "Date" format
- JSON API for reading and writing times, including a bulk endpoint for
  external consumers such as schedulers and sync clients
- Consistency check and repair tasks for operators

## Requirements

- Redmine 6.0 or later (tested against Redmine 6.1 and 7.0, on Ruby 3.4
  and 4.0)
- No other plugins and no GIS stack required

## Installation

```bash
cd /path/to/redmine/plugins
git clone https://github.com/gtt-project/redmine_issue_datetime.git
cd /path/to/redmine
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

Restart Redmine, then open
**Administration → Plugins → Redmine Issue Datetime → Configure** and
enable the trackers that should have time fields.

To uninstall, revert the migration and remove the plugin directory:

```bash
bundle exec rake redmine:plugins:migrate NAME=redmine_issue_datetime VERSION=0 RAILS_ENV=production
rm -rf plugins/redmine_issue_datetime
```

Uninstalling drops only the plugin's own table; core issue data is not
affected.

## Configuration

| Setting | Meaning | Default |
| --- | --- | --- |
| Enabled for trackers | Trackers whose issues get time fields | none |
| Time input step | Interval of the time picker; typed values are snapped to it | 15 min |
| Reference time zone | The clock all times are entered and shown in (see below) | application default |

## How times are shown: one clock for everyone

Times are stored as instants (UTC in the database) but always entered
and displayed in one time zone, the configured reference zone. They are
deliberately **not** converted to each viewer's personal time zone: for
work that happens at a physical place, a dispatcher and a worker must
mean the same wall-clock time by "09:15". The zone is labelled in the UI
so this is never ambiguous.

The reference zone also decides which date is mirrored into
`start_date`/`due_date`. Changing it after times have been stored can
make existing rows inconsistent; run the check task below afterwards.

## Custom field format "Date and time"

The plugin also registers a `datetime` custom field format next to the
built-in `date` one. Values are stored as naive local timestamps in the
reference zone (for example `2026-08-03T09:15`) and support filtering and
grouping. Unlike the start/due times, custom field values are not
snapped to the step: an arbitrary datetime field may legitimately record
an off-grid moment. Currently offered for issue custom fields
([#15](https://github.com/gtt-project/redmine_issue_datetime/issues/15)
tracks widening the scope).

## REST API

All endpoints are JSON and use Redmine's regular API authentication.
Reading requires issue visibility; writing requires permission to edit
issue attributes.

```
GET    /issues/:issue_id/datetime.json
PUT    /issues/:issue_id/datetime.json
DELETE /issues/:issue_id/datetime.json
GET    /projects/:project_id/issue_datetimes.json?updated_since=<iso8601>
```

Write timestamps must carry an explicit offset (`Z` or `+09:00`), so a
request means the same thing regardless of the server's local zone:

```bash
curl -X PUT -H 'Content-Type: application/json' \
  -H 'X-Redmine-API-Key: <key>' \
  -d '{"starts_at": "2026-08-03T09:15:00+09:00", "ends_at": null}' \
  https://redmine.example.org/issues/123/datetime.json
```

A timestamp sets both the core date and the time; `null` clears the time
and keeps the date; omitted keys are left untouched. `DELETE` clears all
times (back to "all day") and keeps the dates.

## Consistency tasks

The date mirror is maintained by ActiveRecord callbacks. Anything that
bypasses them (raw SQL, `update_column`, a restored database) can put
the stored times and the core dates out of step:

```bash
# Report disagreements; exits non-zero when any are found (cron/monitoring friendly)
bundle exec rake redmine_issue_datetime:check RAILS_ENV=production

# Repair them: the core date is re-derived from the stored timestamp
bundle exec rake redmine_issue_datetime:repair RAILS_ENV=production
```

## Development

Tests run inside a Redmine checkout, like any Redmine plugin:

```bash
bundle exec rails test plugins/redmine_issue_datetime/test RAILS_ENV=test
```

CI covers Redmine 6.1/7.0 on Ruby 3.4/4.0 with PostgreSQL, plus a
`zeitwerk:check` eager-loading gate. See
[docs/design.md](docs/design.md) for the design document.

## Related projects

This plugin is standalone and has no GIS dependency. It is developed as
part of the [GTT Project](https://github.com/gtt-project), where it
provides the time foundation for
[redmine_gtt_scheduler](https://github.com/gtt-project/redmine_gtt_scheduler).

## License

GPL-3.0, see [LICENSE](LICENSE).
