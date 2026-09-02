import QtQuick
import Quickshell
import "RestReminderModel.js" as Model

// Rest Reminder: the resident half of the plugin.
//
// It owns the work timer and, later, the deferral rules; the break screen is a
// separate overlay this service summons. Mounted at shell startup and kept for
// the life of the session, so the cycle survives every panel being closed.
Item {
  id: root

  // Injected by the shell's service loader.
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id)
    : "camilo.restreminder"

  // Re-evaluated whenever the shell reloads shell.json, which is what makes
  // an edited interval take effect without a restart.
  readonly property var settings: Model.settingsFrom(
    shell && shell.shellConfig ? shell.shellConfig : null, root.pluginId)

  // Epoch milliseconds. 0 means no cycle is scheduled.
  property double nextBreakAt: 0
  property bool breaking: false

  // Seconds left on the pre-break warning, or -1 when no warning is showing.
  // The overlay renders off this; the service decides when it applies.
  property int warningSecondsLeft: -1
  property string lastEvent: "starting"
  property string lastEventAt: ""

  readonly property int secondsToBreak: root.nextBreakAt > 0
    ? Math.max(0, Math.round((root.nextBreakAt - Date.now()) / 1000))
    : -1

  function logEvent(event, details) {
    var suffix = details === undefined || details === null || details === "" ? "" : ": " + String(details)
    root.lastEventAt = new Date().toISOString()
    root.lastEvent = event + suffix
    console.log("restreminder " + root.lastEventAt + " " + root.lastEvent)
  }

  function scheduleNextBreak(reason) {
    root.nextBreakAt = Date.now() + root.settings.workMinutes * 60000
    logEvent("cycle-start", (reason || "scheduled") + " work=" + root.settings.workMinutes + "m break=" + root.settings.breakSeconds + "s")
  }

  // The overlay owns the countdown and calls back into breakFinished(), so the
  // service stops counting for the duration of the break.
  function startBreak() {
    if (root.breaking) return
    root.breaking = true
    root.nextBreakAt = 0
    root.warningSecondsLeft = -1
    logEvent("break-start", "break=" + root.settings.breakSeconds + "s")

    if (!root.shell || typeof root.shell.summon !== "function") {
      logEvent("break-failed", "no shell to summon the overlay")
      root.breaking = false
      scheduleNextBreak("overlay-unavailable")
      return
    }

    var payload = JSON.stringify({ seconds: root.settings.breakSeconds })
    if (!root.shell.summon(root.pluginId, payload)) {
      logEvent("break-failed", "overlay refused to summon")
      root.breaking = false
      scheduleNextBreak("overlay-unavailable")
    }
  }

  // Called by the overlay when the countdown runs out or the user presses Esc.
  function breakFinished(skipped) {
    if (!root.breaking) return
    root.breaking = false
    logEvent("break-end", skipped === true ? "skipped" : "completed")
    scheduleNextBreak("after-break")
  }

  function updateWarning(secondsLeft) {
    var warnAt = root.settings.warningSeconds

    // A zero warning is the documented way to turn the notice off.
    if (warnAt <= 0 || secondsLeft > warnAt) {
      if (root.warningSecondsLeft >= 0) root.warningSecondsLeft = -1
      return
    }

    if (root.warningSecondsLeft < 0) logEvent("warning-start", secondsLeft + "s to break")
    root.warningSecondsLeft = Math.max(0, secondsLeft)
  }

  function tick() {
    if (root.breaking) return
    if (root.nextBreakAt <= 0) return

    var secondsLeft = Math.ceil((root.nextBreakAt - Date.now()) / 1000)
    updateWarning(secondsLeft)

    if (secondsLeft <= 0) root.startBreak()
  }

  // A new object arrives on every shell.json reload, so compare by value:
  // only a real change should restart the cycle.
  property var appliedSettings: null

  // The settings binding can evaluate before this object finishes
  // initializing, and property defaults are applied in declaration order, so
  // anything the handler stored before startup would be overwritten. Gate on
  // `started` instead of on stored state, which is undefined-safe either way.
  property bool started: false

  onSettingsChanged: {
    if (!root.started) return
    if (Model.sameSettings(root.appliedSettings, root.settings)) return
    root.appliedSettings = root.settings
    scheduleNextBreak("settings-changed")
  }

  Component.onCompleted: {
    root.started = true
    root.appliedSettings = root.settings
    scheduleNextBreak("startup")
  }

  // One second is enough resolution for a countdown measured in minutes, and
  // cheap enough to leave running for the life of the session.
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.tick()
  }
}
