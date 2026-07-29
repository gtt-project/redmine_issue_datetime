# redmine_issue_datetime

A Redmine plugin that adds time of day to issue start and due dates,
without changing the Redmine core schema.

Redmine stores `start_date` and `due_date` as plain dates. The ability to
set a time as well has been requested for a long time
([redmine.org #5458](https://www.redmine.org/issues/5458)). This plugin
solves it with parallel storage: times live in a plugin-owned table and
the date part is mirrored into the core columns, so filters, calendar,
Gantt, exports, and the REST API keep working exactly as before.

## Status

Early development, no release yet. The core pieces (sidecar storage,
date mirroring, issue form integration, JSON API) are implemented and
covered by tests. See [docs/design.md](docs/design.md) for the full
design document.

## Planned highlights

- Time inputs next to the start and due date fields, with a configurable
  step (15 minutes by default)
- Per-tracker enablement; issues without times behave exactly like stock
  Redmine
- Times journalized in the issue history
- JSON API for reading and writing times, including a bulk endpoint for
  external consumers such as schedulers and sync clients

## Related projects

This plugin is standalone and has no GIS dependency. It is developed as
part of the [GTT Project](https://github.com/gtt-project), where it
provides the time foundation for
[redmine_gtt_scheduler](https://github.com/gtt-project/redmine_gtt_scheduler).

## License

GPL-3.0, see [LICENSE](LICENSE).
