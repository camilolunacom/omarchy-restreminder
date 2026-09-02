// Pure helpers for the Rest Reminder service. Kept free of QML types so the
// timing rules can be reasoned about (and tested) on their own.

var DEFAULT_WORK_MINUTES = 20
var DEFAULT_BREAK_SECONDS = 20
var DEFAULT_WARNING_SECONDS = 10

function positiveNumber(value, fallback) {
  var n = Number(value)
  return isFinite(n) && n > 0 ? n : fallback
}

function nonNegativeNumber(value, fallback) {
  var n = Number(value)
  return isFinite(n) && n >= 0 ? n : fallback
}

function findInList(list, pluginId) {
  if (!Array.isArray(list)) return null

  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (entry && String(entry.id) === String(pluginId)) return entry
  }

  return null
}

// The plugin's single entry in shell.json. Settings are inline on it; there is
// no config sub-object and no merge layer.
//
// Which array holds that entry depends on where the plugin lives: a bar widget
// is stored in `bar.layout.<section>`, everything else in `plugins[]`. This
// plugin is both, so its one entry moves between the two when the widget is
// added to or removed from the bar, and the settings move with it.
function entryFor(shellConfig, pluginId) {
  if (!shellConfig) return null

  var entry = findInList(shellConfig.plugins, pluginId)
  if (entry) return entry

  var layout = shellConfig.bar && shellConfig.bar.layout
  if (!layout) return null

  var sections = ["left", "center", "right"]
  for (var i = 0; i < sections.length; i++) {
    entry = findInList(layout[sections[i]], pluginId)
    if (entry) return entry
  }

  return null
}

// Every value falls back rather than throwing: a typo in shell.json must not
// take the shell down with it.
function settingsFrom(shellConfig, pluginId) {
  var entry = entryFor(shellConfig, pluginId) || {}

  var workMinutes = positiveNumber(entry.workMinutes, DEFAULT_WORK_MINUTES)
  var breakSeconds = positiveNumber(entry.breakSeconds, DEFAULT_BREAK_SECONDS)

  // The warning has to fit inside the work interval, or it would already be
  // due the moment the cycle starts.
  var warningSeconds = Math.min(
    nonNegativeNumber(entry.warningSeconds, DEFAULT_WARNING_SECONDS),
    Math.max(0, workMinutes * 60 - 1))

  // Absent, the idle threshold tracks the work interval: being away for a
  // whole work interval is what counts as having taken the break.
  var idlePauseMinutes = positiveNumber(entry.idlePauseMinutes, workMinutes)

  return {
    workMinutes: workMinutes,
    breakSeconds: breakSeconds,
    warningSeconds: warningSeconds,
    idlePauseMinutes: idlePauseMinutes
  }
}

function sameSettings(a, b) {
  if (!a || !b) return false
  return a.workMinutes === b.workMinutes
    && a.breakSeconds === b.breakSeconds
    && a.warningSeconds === b.warningSeconds
    && a.idlePauseMinutes === b.idlePauseMinutes
}

// ------------------------------------------------------------------ widget

// Compact enough for a bar slot: minutes until the break, seconds only once
// the break is close enough for seconds to mean something.
function formatCountdown(seconds) {
  if (!isFinite(seconds) || seconds < 0) return "--"
  if (seconds < 60) return String(Math.max(0, Math.round(seconds))) + "s"
  return String(Math.ceil(seconds / 60)) + "m"
}

function widgetLabel(state, seconds) {
  switch (state) {
    case "breaking": return "break"
    case "paused": return "paused"
    case "idle": return "away"
    case "deferred": return "hold"
    case "counting": return formatCountdown(seconds)
    default: return "--"
  }
}

function widgetTooltip(state, seconds) {
  switch (state) {
    case "breaking": return "Eye break in progress"
    case "paused": return "Rest reminders paused. Right click to resume"
    case "idle": return "Away from the keyboard; the timer restarts when you get back"
    case "deferred": return "A break is waiting for fullscreen to end"
    case "counting": return "Next eye break in " + formatCountdown(seconds)
      + "\nClick to break now, right click to pause"
    default: return "Rest Reminder"
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULT_WORK_MINUTES: DEFAULT_WORK_MINUTES,
    DEFAULT_BREAK_SECONDS: DEFAULT_BREAK_SECONDS,
    DEFAULT_WARNING_SECONDS: DEFAULT_WARNING_SECONDS,
    entryFor: entryFor,
    settingsFrom: settingsFrom,
    sameSettings: sameSettings,
    formatCountdown: formatCountdown,
    widgetLabel: widgetLabel,
    widgetTooltip: widgetTooltip
  }
}
