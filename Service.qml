import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
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
    : "io.github.camilolunacom.restreminder"

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

  // A break came due while something was blocking it. Exactly one is owed, no
  // matter how long the block lasts.
  property bool breakPending: false
  property bool suspended: false

  // Epoch milliseconds a timed pause runs out, or 0. An indefinite pause is
  // deliberately not persisted: forgotten, it would defeat the plugin
  // silently, while a timed pause cut short by a shell restart -- and
  // `omarchy update` restarts the shell -- would be a bug.
  property double pausedUntil: 0
  property bool pausedIndefinitely: false
  readonly property bool paused: root.pausedIndefinitely || root.pausedUntil > 0

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: root.home + "/.local/state/omarchy"
  readonly property string statePath: root.stateDir + "/restreminder"

  // Wayland exposes no way to ask whether some app is holding an idle
  // inhibitor. Two monitors on the same timeout answer it indirectly: when
  // input has stopped but only the inhibitor-blind one reports idle, an
  // inhibitor is what is holding the session awake. It reads as "a player or a
  // call is running and the user is not typing" -- which is exactly when a
  // break screen would be an interruption rather than a rest.
  readonly property bool inhibitorActive: inhibitorProbeRaw.isIdle && !inhibitorProbeRespecting.isIdle

  readonly property bool fullscreenActive: Hyprland.focusedWorkspace
    ? Hyprland.focusedWorkspace.hasFullscreen === true
    : false

  readonly property bool deferring: root.fullscreenActive || root.inhibitorActive

  readonly property string deferReason: root.fullscreenActive
    ? (root.inhibitorActive ? "fullscreen+inhibitor" : "fullscreen")
    : (root.inhibitorActive ? "inhibitor" : "")
  property string lastEvent: "starting"
  property string lastEventAt: ""

  // Maintained by the tick rather than derived from nextBreakAt: Date.now()
  // emits no change signal, so a computed countdown would never update
  // anything bound to it -- the bar widget included. -1 means "not counting".
  property int secondsToBreak: -1

  // The one place the visible state is named. The widget renders off this and
  // the status IPC reports it, so they can never disagree.
  readonly property string stateName: root.breaking ? "breaking"
    : root.paused ? "paused"
    : root.suspended ? "idle"
    : root.breakPending ? "deferred"
    : "counting"

  function logEvent(event, details) {
    var suffix = details === undefined || details === null || details === "" ? "" : ": " + String(details)
    root.lastEventAt = new Date().toISOString()
    root.lastEvent = event + suffix
    console.log("restreminder " + root.lastEventAt + " " + root.lastEvent)
  }

  function scheduleNextBreak(reason) {
    root.nextBreakAt = Date.now() + root.settings.workMinutes * 60000
    root.secondsToBreak = Math.round(root.settings.workMinutes * 60)
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

  // One action for both sides of a break starting: mid-break it ends the
  // break, otherwise it drops the break that is coming. Either way the next
  // one is a full work interval out, which is what the widget's Skip button
  // promises whichever state it is pressed in.
  function skipBreak() {
    if (root.breaking) {
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
      root.breakFinished(true)
      return "ok"
    }

    // Nothing is owed while paused or away, and restarting the cycle from
    // here would quietly undo the pause on the next resume.
    if (root.paused) return "paused"

    root.breakPending = false
    root.warningSecondsLeft = -1
    if (root.suspended) return "away"

    logEvent("break-skipped", "before it started")
    scheduleNextBreak("skipped")
    return "ok"
  }

  function updateWarning(secondsLeft) {
    var warnAt = root.settings.warningSeconds

    // A zero warning is the documented way to turn the notice off. A deferred
    // break has no landing time to announce, so it stays quiet until the
    // block clears.
    if (warnAt <= 0 || secondsLeft > warnAt || root.deferring) {
      if (root.warningSecondsLeft >= 0) root.warningSecondsLeft = -1
      return
    }

    if (root.warningSecondsLeft < 0) logEvent("warning-start", secondsLeft + "s to break")
    root.warningSecondsLeft = Math.max(0, secondsLeft)
  }

  function expirePauseIfDue() {
    if (root.pausedUntil <= 0) return
    if (Date.now() < root.pausedUntil) return

    root.pausedUntil = 0
    persistPause()
    logEvent("pause-expired")
    if (!root.suspended) scheduleNextBreak("pause-expired")
  }

  function persistPause() {
    // Only the timed pause is durable; anything else clears the file.
    pauseState.setText(root.pausedUntil > 0 ? String(Math.round(root.pausedUntil)) : "")
  }

  function restorePause() {
    var stored = Number(String(pauseState.text() || "").trim())
    if (!isFinite(stored) || stored <= Date.now()) {
      if (stored > 0) persistPause()
      return
    }

    root.pausedUntil = stored
    root.nextBreakAt = 0
    root.warningSecondsLeft = -1
    logEvent("pause-restored", Math.round((stored - Date.now()) / 1000) + "s left")
  }

  function pause(minutes) {
    var mins = Number(minutes)
    root.breakPending = false
    root.nextBreakAt = 0
    root.warningSecondsLeft = -1

    if (isFinite(mins) && mins > 0) {
      root.pausedIndefinitely = false
      root.pausedUntil = Date.now() + mins * 60000
      persistPause()
      logEvent("pause", mins + "m")
      return "paused for " + mins + "m"
    }

    root.pausedIndefinitely = true
    root.pausedUntil = 0
    persistPause()
    logEvent("pause", "indefinite")
    return "paused"
  }

  function unpause() {
    if (!root.paused) return "not paused"

    root.pausedIndefinitely = false
    root.pausedUntil = 0
    persistPause()
    logEvent("resume", "requested")
    if (!root.suspended) scheduleNextBreak("resumed")
    return "resumed"
  }

  function statusJson() {
    return JSON.stringify({
      state: root.stateName,
      secondsToBreak: root.secondsToBreak,
      warningSecondsLeft: root.warningSecondsLeft,
      breaking: root.breaking,
      deferring: root.deferring,
      deferReason: root.deferReason,
      fullscreen: root.fullscreenActive,
      inhibitor: root.inhibitorActive,
      idle: root.awayMonitor ? root.awayMonitor.isIdle === true : false,
      idleTimeout: root.idleTimeoutSeconds,
      suspended: root.suspended,
      paused: root.paused,
      pausedUntil: root.pausedUntil,
      settings: root.settings,
      lastEvent: root.lastEvent,
      lastEventAt: root.lastEventAt
    })
  }

  function tick() {
    expirePauseIfDue()

    if (root.paused || root.breaking || root.suspended) {
      root.secondsToBreak = -1
      return
    }

    if (root.breakPending) {
      root.secondsToBreak = -1
      if (!root.deferring) releaseDeferredBreak()
      return
    }

    if (root.nextBreakAt <= 0) {
      root.secondsToBreak = -1
      return
    }

    var secondsLeft = Math.max(0, Math.ceil((root.nextBreakAt - Date.now()) / 1000))
    root.secondsToBreak = secondsLeft
    updateWarning(secondsLeft)

    if (secondsLeft > 0) return

    if (root.deferring) {
      if (!root.breakPending) logEvent("break-deferred", root.deferReason)
      root.breakPending = true
      root.nextBreakAt = 0
      return
    }

    root.startBreak()
  }

  // Coming back from a deferral re-arms the warning rather than dropping the
  // break screen on a user who just closed a video.
  function releaseDeferredBreak() {
    if (!root.breakPending || root.suspended) return
    root.breakPending = false

    var lead = root.settings.warningSeconds
    if (lead <= 0) {
      logEvent("break-released", "no warning configured")
      root.startBreak()
      return
    }

    logEvent("break-released", "warning in " + lead + "s")
    root.nextBreakAt = Date.now() + lead * 1000
  }

  function suspend(reason) {
    if (root.suspended) return
    root.suspended = true
    root.breakPending = false
    root.nextBreakAt = 0
    root.warningSecondsLeft = -1
    logEvent("suspend", reason)
  }

  function resume(reason) {
    if (!root.suspended) return
    root.suspended = false
    scheduleNextBreak(reason)
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

  // Being away from the screen for a whole idle threshold is the break. The
  // timer stops while the user is gone and starts over when they return, so a
  // break never greets someone walking back to their desk.
  // IdleMonitor takes its timeout when the underlying idle notification is
  // registered and ignores a binding that resolves later: bound to a config
  // value it silently never reports idle. So it is built by hand, with the
  // timeout passed as an initial property, and rebuilt whenever the
  // configured threshold changes.
  Component {
    id: awayMonitorComponent

    IdleMonitor {
      enabled: true
      respectInhibitors: true
      onIsIdleChanged: {
        if (isIdle) root.suspend("idle over " + root.settings.idlePauseMinutes + "m")
        else root.resume("back from idle")
      }
    }
  }

  property var awayMonitor: null

  // Floored: sub-second thresholds are not honoured by the compositor, and a
  // monitor that never fires would silently disable the idle rules.
  readonly property int idleTimeoutSeconds: Math.max(
    5, Math.round(root.settings.idlePauseMinutes * 60))

  function rebuildAwayMonitor() {
    if (root.awayMonitor) {
      root.awayMonitor.destroy()
      root.awayMonitor = null
    }

    root.awayMonitor = awayMonitorComponent.createObject(root, { timeout: root.idleTimeoutSeconds })
    if (!root.awayMonitor) {
      logEvent("idle-monitor-failed", "could not create the idle monitor")
      return
    }

    // A fresh monitor starts out not-idle and reports no transition, so a
    // rebuild while suspended would strand the timer with nothing to restart
    // it.
    if (root.suspended && root.awayMonitor.isIdle !== true) root.resume("idle monitor rebuilt")
  }

  onIdleTimeoutSecondsChanged: if (root.started) rebuildAwayMonitor()

  // The inhibitor probe pair. Short and equal timeouts; only the gap between
  // them carries meaning.
  IdleMonitor {
    id: inhibitorProbeRaw
    enabled: true
    timeout: 60
    respectInhibitors: false
  }

  IdleMonitor {
    id: inhibitorProbeRespecting
    enabled: true
    timeout: 60
    respectInhibitors: true
  }

  // FileView cannot create the directory it writes into.
  Process {
    id: stateDirInit
    running: true
    command: ["mkdir", "-p", root.stateDir]
    onExited: {
      pauseState.reload()
      root.restorePause()
    }
  }

  FileView {
    id: pauseState
    path: root.statePath
    atomicWrites: true
    printErrors: false
  }

  IpcHandler {
    target: "restreminder"

    function status(): string { return root.statusJson() }

    function breakNow(): string {
      if (root.breaking) return "already breaking"
      root.startBreak()
      return "ok"
    }

    function skip(): string { return root.skipBreak() }

    // Bare `pause` is indefinite and session-only; `pause 30` survives a
    // restart and expires on its own.
    function pause(minutes: string): string { return root.pause(minutes) }

    function resume(): string { return root.unpause() }
  }

  Component.onCompleted: {
    root.started = true
    root.appliedSettings = root.settings
    rebuildAwayMonitor()
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
