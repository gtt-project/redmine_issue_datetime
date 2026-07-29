// Places each time field next to the date field it belongs to, and snaps
// typed values to the configured interval.
//
// Redmine renders no hook between the date inputs and their labels, so the
// fields are rendered in a detached container and moved here. The targets are
// Redmine's own wrapper ids (start_date_area / due_date_area). If either is
// missing, the field is left where it was rendered rather than lost.
(function () {
  'use strict';

  // Marks that this script actually loaded. The stylesheet only hides the
  // detached container when this class is present, so a failed or disabled
  // script leaves the fields visible where they were rendered instead of
  // hiding them forever.
  document.documentElement.classList.add('issue-datetime-js');

  function snapToStep(input) {
    var step = parseInt(input.getAttribute('step'), 10);
    if (!step || !input.value) return;

    var parts = input.value.split(':');
    if (parts.length < 2) return;

    var hours = parseInt(parts[0], 10);
    var mins = parseInt(parts[1], 10);
    if (!isFinite(hours) || !isFinite(mins)) return;

    var minutes = hours * 60 + mins;
    var stepMinutes = step / 60;
    if (!stepMinutes) return;

    var snapped = Math.round(minutes / stepMinutes) * stepMinutes;
    // Snapping up from the last slot of the day would roll over to 00:00 the
    // next day, which the date field cannot express; clamp instead.
    if (snapped > 23 * 60 + 59) {
      snapped = Math.floor((23 * 60 + 59) / stepMinutes) * stepMinutes;
    }
    var hh = String(Math.floor(snapped / 60)).padStart(2, '0');
    var mm = String(snapped % 60).padStart(2, '0');
    var value = hh + ':' + mm;
    if (value !== input.value) input.value = value;
  }

  function relocate(container) {
    var fields = container.querySelectorAll('[data-issue-datetime-target]');
    Array.prototype.forEach.call(fields, function (field) {
      var target = document.getElementById(field.dataset.issueDatetimeTarget);
      if (!target) return;

      var wrapper = document.createElement('span');
      wrapper.className = 'issue-datetime-inline';
      wrapper.appendChild(field);
      target.appendChild(wrapper);
    });
    // Whatever could not be relocated stays visible in place.
    if (!container.querySelector('[data-issue-datetime-target]')) {
      container.parentNode.removeChild(container);
    } else {
      container.classList.remove('issue-datetime-pending');
    }
  }

  function init() {
    var container = document.getElementById('issue-datetime-fields');
    if (container) relocate(container);

    document.querySelectorAll('input.issue-datetime-time').forEach(function (input) {
      input.addEventListener('change', function () { snapToStep(input); });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
