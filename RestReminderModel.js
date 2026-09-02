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

// The plugin's own entry in shell.json `plugins[]`. Settings are inline on the
// entry; there is no config sub-object and no merge layer.
function entryFor(shellConfig, pluginId) {
  var plugins = shellConfig && shellConfig.plugins
  if (!Array.isArray(plugins)) return null

  for (var i = 0; i < plugins.length; i++) {
    var entry = plugins[i]
    if (entry && String(entry.id) === String(pluginId)) return entry
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

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULT_WORK_MINUTES: DEFAULT_WORK_MINUTES,
    DEFAULT_BREAK_SECONDS: DEFAULT_BREAK_SECONDS,
    DEFAULT_WARNING_SECONDS: DEFAULT_WARNING_SECONDS,
    entryFor: entryFor,
    settingsFrom: settingsFrom,
    sameSettings: sameSettings
  }
}
