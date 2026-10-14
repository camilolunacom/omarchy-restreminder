// Pure helpers for the Rest Reminder service. Kept free of QML types so the
// timing rules can be reasoned about (and tested) on their own.

var DEFAULT_WORK_MINUTES = 20
var DEFAULT_BREAK_SECONDS = 20
var DEFAULT_WARNING_SECONDS = 10

// The 20-20-20 rule spelled out on the break screen: the number the break is
// named after is the distance, not the duration, and it is the part a tired
// user needs reminding of.
// nf-md-pause. Both the bar label and the popup's frozen countdown show this
// rather than spelling it out: it is the same mark as the Pause button, so the
// state and the control that caused it read as one thing.
var PAUSE_GLYPH = "󰏤"

// The freedesktop sound theme's "a task finished" event, which is exactly
// what the end of a break is. Omarchy ships no sounds of its own, and
// sound-theme-freedesktop is only ever pulled in as somebody else's
// dependency, so this file is not guaranteed to exist -- see the service,
// which degrades to silence rather than to an error every twenty minutes.
var DEFAULT_BREAK_END_SOUND_FILE = "/usr/share/sounds/freedesktop/stereo/complete.oga"

// The same rule in metres is 6, not a literal 6.096: the number has to be
// one a tired user can picture at a glance.
var BREAK_TEXT = {
  imperial: {
    headline: "Look 20 feet away",
    message: "Rest your eyes on something far off, at least 20 feet away"
  },
  metric: {
    headline: "Look 6 metres away",
    message: "Rest your eyes on something far off, at least 6 metres away"
  }
}

var DEFAULT_UNITS = "imperial"
var DEFAULT_BREAK_HEADLINE = BREAK_TEXT[DEFAULT_UNITS].headline
var DEFAULT_BREAK_MESSAGE = BREAK_TEXT[DEFAULT_UNITS].message

function positiveNumber(value, fallback) {
  var n = Number(value)
  return isFinite(n) && n > 0 ? n : fallback
}

function nonNegativeNumber(value, fallback) {
  var n = Number(value)
  return isFinite(n) && n >= 0 ? n : fallback
}

// Only a real boolean counts. A string "false" is a mistake in shell.json, and
// guessing what it meant is worse than falling back to the default.
function boolean(value, fallback) {
  return value === true || value === false ? value : fallback
}

// An empty string is a typo, not an intent to blank the break screen; only a
// real string overrides the default.
function nonEmptyString(value, fallback) {
  if (typeof value !== "string") return fallback
  var trimmed = value.trim()
  return trimmed === "" ? fallback : trimmed
}

// "metric" or "imperial", or null for anything else, so a typo falls back
// rather than picking a side.
function unitsValue(value) {
  return value === "metric" || value === "imperial" ? value : null
}

// Feet only where the locale measures in US customary units. Qt reports
// en_GB as "Imperial UK", but distances on a break screen read naturally in
// metres there too, so it goes with the rest of the world.
function unitsForLocale(isImperialUS) {
  return isImperialUS ? "imperial" : "metric"
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
//
// `fallbackUnits` stands in for a missing or malformed `units`: the service
// passes the one it detected from the locale.
function settingsFrom(shellConfig, pluginId, fallbackUnits) {
  var entry = entryFor(shellConfig, pluginId) || {}

  var units = unitsValue(entry.units) || unitsValue(fallbackUnits) || DEFAULT_UNITS
  var breakText = BREAK_TEXT[units]

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
    idlePauseMinutes: idlePauseMinutes,
    units: units,
    breakHeadline: nonEmptyString(entry.breakHeadline, breakText.headline),
    breakMessage: nonEmptyString(entry.breakMessage, breakText.message),
    breakEndSound: boolean(entry.breakEndSound, true),
    breakEndSoundFile: nonEmptyString(entry.breakEndSoundFile, DEFAULT_BREAK_END_SOUND_FILE)
  }
}

// The plugin's entry with `units` added, for writing back on first run, or
// null when there is nothing to write: no entry to put it on yet, or `units`
// already present. A present but malformed value is the user's to fix; it is
// left alone rather than silently overwritten.
//
// The shell replaces the whole entry on write, so the copy carries every
// other setting along with it.
function entryWithUnits(shellConfig, pluginId, units) {
  var entry = entryFor(shellConfig, pluginId)
  if (!entry || entry.units !== undefined || !unitsValue(units)) return null

  var next = {}
  for (var key in entry) next[key] = entry[key]
  next.units = units
  return next
}

// Timing only, on purpose. This is what decides whether an edit to shell.json
// restarts the cycle, and rewording the break screen must not cost the user
// the interval they had already served.
function sameSettings(a, b) {
  if (!a || !b) return false
  return a.workMinutes === b.workMinutes
    && a.breakSeconds === b.breakSeconds
    && a.warningSeconds === b.warningSeconds
    && a.idlePauseMinutes === b.idlePauseMinutes
}

// ------------------------------------------------------------------- state

// The pause state file used to hold a bare epoch-millis timestamp; it now
// holds the frozen remainder alongside it. Both are read, so upgrading in
// place over a live pause does not resurrect it with a full interval behind
// it. Anything unparseable reads as no pause at all rather than throwing:
// a corrupt state file must not take the shell down on startup.
function storedPause(raw) {
  var text = String(raw || "").trim()
  if (text === "") return null

  if (text.charAt(0) === "{") {
    var parsed = null
    try { parsed = JSON.parse(text) } catch (e) { return null }
    if (!parsed) return null

    var until = Number(parsed.pausedUntil)
    if (!isFinite(until) || until <= 0) return null

    var remaining = Number(parsed.remaining)
    return {
      pausedUntil: until,
      remaining: isFinite(remaining) && remaining >= 0 ? remaining : -1
    }
  }

  var legacy = Number(text)
  if (!isFinite(legacy) || legacy <= 0) return null
  return { pausedUntil: legacy, remaining: -1 }
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
    case "paused": return PAUSE_GLYPH
    case "idle": return "away"
    case "deferred": return "hold"
    case "counting": return formatCountdown(seconds)
    default: return "--"
  }
}

// The popup has room the bar slot does not, so it shows the exact time
// rather than the rounded minute the label has to settle for.
function formatClock(seconds) {
  if (!isFinite(seconds) || seconds < 0) return "--:--"
  var total = Math.max(0, Math.round(seconds))
  var minutes = Math.floor(total / 60)
  var rest = total % 60
  return String(minutes) + ":" + (rest < 10 ? "0" : "") + String(rest)
}

// ------------------------------------------------------------------- popup

// Paused shows a number too: it is frozen, not spent, and hiding it would
// make a pause look like the interval had been thrown away.
function panelCountdown(state, seconds) {
  if (state !== "counting" && state !== "paused") return "--:--"
  return formatClock(seconds)
}

function panelStatus(state) {
  switch (state) {
    case "breaking": return "Break in progress"
    case "paused": return "Reminders paused"
    case "idle": return "Away from the keyboard"
    case "deferred": return "Waiting for fullscreen"
    case "counting": return "Until the next break"
    default: return "Rest Reminder"
  }
}

// Skip means two different things either side of a break starting, and the
// button says which one it is about to do.
function skipLabel(state) {
  return state === "breaking" ? "End break" : "Skip"
}

function skipTooltip(state) {
  return state === "breaking"
    ? "End this break now"
    : "Skip the next break and start a fresh interval"
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULT_WORK_MINUTES: DEFAULT_WORK_MINUTES,
    DEFAULT_BREAK_SECONDS: DEFAULT_BREAK_SECONDS,
    DEFAULT_WARNING_SECONDS: DEFAULT_WARNING_SECONDS,
    PAUSE_GLYPH: PAUSE_GLYPH,
    DEFAULT_BREAK_END_SOUND_FILE: DEFAULT_BREAK_END_SOUND_FILE,
    DEFAULT_BREAK_HEADLINE: DEFAULT_BREAK_HEADLINE,
    DEFAULT_BREAK_MESSAGE: DEFAULT_BREAK_MESSAGE,
    BREAK_TEXT: BREAK_TEXT,
    unitsValue: unitsValue,
    unitsForLocale: unitsForLocale,
    entryFor: entryFor,
    settingsFrom: settingsFrom,
    entryWithUnits: entryWithUnits,
    sameSettings: sameSettings,
    storedPause: storedPause,
    formatCountdown: formatCountdown,
    formatClock: formatClock,
    widgetLabel: widgetLabel,
    panelCountdown: panelCountdown,
    panelStatus: panelStatus,
    skipLabel: skipLabel,
    skipTooltip: skipTooltip
  }
}
