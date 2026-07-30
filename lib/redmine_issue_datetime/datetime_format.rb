module RedmineIssueDatetime
  # A "Date and time" custom field format, offered alongside Redmine's built-in
  # "Date" rather than replacing it: a field either wants a time or it does not,
  # and that is per field.
  #
  # No sidecar table is involved. The whole mirror machinery elsewhere in this
  # plugin exists because issues.start_date is a real `date` column that cannot
  # be changed; a custom value is a string column, so a timestamp fits natively.
  #
  # Stored as naive local time in the instance reference zone ("2026-08-03T09:15",
  # no offset). Three reasons: it matches how the built-in date format stores,
  # it keeps ISO strings sortable as plain strings so ordering needs no special
  # casing, and it is consistent with this plugin showing one clock for everyone
  # rather than converting per viewer.
  # Named DatetimeFormat in datetime_format.rb on purpose: Redmine adds every
  # plugin's lib/ as an eager-load path, so Zeitwerk derives the constant from
  # the filename. A mismatch here passes every test (test and development load
  # lazily) and then kills a production boot with a NameError.
  class DatetimeFormat < Redmine::FieldFormat::Unbounded
    add 'datetime'
    self.form_partial = 'custom_fields/formats/datetime'
    self.searchable_supported = false

    # Naive local: date and time, deliberately no zone offset.
    PATTERN = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/
    STORAGE_FORMAT = '%Y-%m-%dT%H:%M'.freeze

    def label
      'label_datetime'
    end

    def cast_single_value(custom_field, value, _customized = nil)
      return nil if value.blank?

      # Interpreted in the reference zone, which is the clock the value was
      # entered on.
      RedmineIssueDatetime.reference_zone.strptime(value.to_s, STORAGE_FORMAT)
    rescue ArgumentError
      nil
    end

    def validate_single_value(custom_field, value, customized = nil)
      errors = super
      return errors if value.blank?

      unless PATTERN.match?(value.to_s) && cast_single_value(custom_field, value)
        errors << ::I18n.t('activerecord.errors.messages.invalid')
      end
      errors
    end

    # Formatted on the reference zone, deliberately not via the view's
    # format_time, which converts to the viewer's own zone: this plugin shows one
    # clock for everyone. Admin date/time settings are honoured when set, and the
    # fallbacks are explicit rather than a locale default, because those can omit
    # the year (:short renders "03 Aug 09:15").
    def formatted_value(_view, custom_field, value, customized = nil, _html = false)
      time = cast_single_value(custom_field, value, customized)
      return '' if time.nil?

      date_part = Setting.date_format.presence || '%Y-%m-%d'
      time_part = Setting.time_format.presence || '%H:%M'
      time.strftime("#{date_part} #{time_part}")
    end

    def edit_tag(view, tag_id, tag_name, custom_value, options = {})
      datetime_field(view, tag_name, custom_value.value,
                     options.merge(id: tag_id))
    end

    def bulk_edit_tag(view, tag_id, tag_name, custom_field, objects, value, options = {})
      datetime_field(view, tag_name, value, options.merge(id: tag_id)) +
        bulk_clear_tag(view, tag_id, tag_name, custom_field, value)
    end

    # Filtering and grouping come from the framework once the type is declared.
    def query_filter_options(_custom_field, _query)
      {type: :datetime}
    end

    def group_statement(custom_field)
      order_statement(custom_field)
    end

    private

    # The step makes the browser's picker move in the configured interval, the
    # same grid as the start/due time fields. It is deliberately not enforced
    # server-side: unlike the scheduling times, an arbitrary datetime field may
    # legitimately record something off the grid, such as when an incident was
    # reported.
    def datetime_field(view, name, value, options = {})
      value = value.strftime(STORAGE_FORMAT) if value.respond_to?(:strftime)
      view.text_field_tag(name, value, options.merge(
                                         type: 'datetime-local',
                                         step: RedmineIssueDatetime.time_step_seconds
                                       ))
    end
  end
end
