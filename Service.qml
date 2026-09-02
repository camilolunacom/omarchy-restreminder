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

  function startBreak() {
    // Milestone 2 replaces this with the overlay.
    logEvent("break-due", "break=" + root.settings.breakSeconds + "s")
    scheduleNextBreak("after-break")
  }

  function tick() {
    if (root.nextBreakAt <= 0) return
    if (Date.now() >= root.nextBreakAt) root.startBreak()
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
