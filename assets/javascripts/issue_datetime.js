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

  // Moves each wrapper (control plus its label, if any) into the date row it
  // names, so nothing is orphaned behind in the detached container.
  function relocate(container) {
    var groups = container.querySelectorAll('[data-issue-datetime-target]');
    Array.prototype.forEach.call(groups, function (group) {
      var target = document.getElementById(group.dataset.issueDatetimeTarget);
      if (target) target.appendChild(group);
    });
    // Whatever could not be relocated stays visible in place.
    if (!container.querySelector('[data-issue-datetime-target]')) {
      container.parentNode.removeChild(container);
    } else {
      container.classList.remove('issue-datetime-pending');
    }
  }

  // "All day" means "no times", so ticking it empties and disables the time
  // inputs rather than storing a flag of its own. Disabled inputs submit
  // nothing, and the server clears the times when the box is ticked, so the two
  // agree even if this script never runs.
  function applyAllDay(checkbox, times, clearValues) {
    times.forEach(function (input) {
      if (checkbox.checked && clearValues) input.value = '';
      input.disabled = checkbox.checked;
    });
  }

  function wireAllDay() {
    var checkbox = document.querySelector('input.issue-datetime-all-day');
    if (!checkbox) return;

    var times = Array.prototype.slice.call(
      document.querySelectorAll('input.issue-datetime-time')
    );
    // On load, reflect the current state without wiping times the issue already
    // has: an unticked box must not clear anything.
    applyAllDay(checkbox, times, false);
    checkbox.addEventListener('change', function () {
      applyAllDay(checkbox, times, true);
    });
    // Entering a time is an implicit "not all day".
    times.forEach(function (input) {
      input.addEventListener('input', function () {
        if (input.value && checkbox.checked) {
          checkbox.checked = false;
          applyAllDay(checkbox, times, false);
        }
      });
    });
  }

  function init() {
    var container = document.getElementById('issue-datetime-fields');
    if (container) relocate(container);

    document.querySelectorAll('input.issue-datetime-time').forEach(function (input) {
      input.addEventListener('change', function () { snapToStep(input); });
    });
    wireAllDay();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
