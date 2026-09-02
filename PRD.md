# PRD (draft): Rest Reminder — an Omarchy eye-break plugin

**Status:** draft for review
**Author:** Camilo Luna
**Date:** 2026-09-02
**Target platform:** Omarchy 4.x (`omarchy-shell` / Quickshell plugin host)
**Plugin id:** `io.github.camilolunacom.restreminder` — repo `omarchy-restreminder`

## 1. Summary

An Omarchy shell plugin that enforces the 20-20-20 rule: every X minutes of work, a fullscreen overlay covers every display for Y seconds, prompting the user to look away and rest their eyes. It is the Omarchy equivalent of LookAway on macOS.

Defaults: X = 20 minutes, Y = 20 seconds. Both are user-configurable.

## 2. Problem

Omarchy has no break reminder. The built-in `omarchy.reminders` plugin is a one-shot "remind me in N minutes" flow that ends in a notification; it does not repeat, does not enforce anything, and a notification is trivially ignored. Long uninterrupted screen sessions cause eye strain, and the only current workarounds are third-party tools that do not follow the Omarchy theme, do not know about idle state, and add another process to the session.

## 3. Goals

- Recurring, automatic break reminders with no user action required after install.
- A fullscreen overlay that is hard to ignore, on all connected displays.
- Configurable work interval and break duration, defaulting to 20 min / 20 s.
- Never interrupt something that must not be interrupted: idle, inhibited, or fullscreen sessions.
- A bar widget showing when the next break lands.
- Native to Omarchy: installs with `omarchy plugin add`, themed by the shell, runs inside the existing `omarchy-shell` process (no extra daemon).

### Non-goals (MVP)

- Stretch/posture/hydration reminders, or any break type other than eyes.
- Statistics, streaks, history, or reporting.
- Per-application or per-time-of-day rules and schedules.
- Sync of settings between machines.
- A GUI settings panel (config is file-based for the MVP).
- A `restreminder` CLI. Specified in section 10 and deliberately deferred; the MVP still ships the IPC target it will wrap, so adding it later needs no redesign.
- Hard, unskippable enforcement modes.

## 4. Users and use cases

Single user: an Omarchy desktop user who works long sessions at the keyboard.

- As a user, I install the plugin and get a break screen every 20 minutes without configuring anything.
- As a user, I get a short heads-up before the break lands, so it never cuts me off mid-sentence.
- As a user, I change the interval to 30 minutes and the break to 30 seconds by editing one config file, and it takes effect without restarting anything.
- As a user, I am in the middle of something urgent, so I press Esc and get back to work; the timer restarts.
- As a user, I walk away for lunch; the timer is suspended while I am gone, and when I come back I get a full work interval before the next break, not a break screen in my face nor a backlog of missed ones.
- As a user watching a film fullscreen, I am not interrupted; the break waits until I exit fullscreen.

## 5. Functional requirements

### 5.1 Timing

- FR1: The plugin runs a work timer of `workMinutes` (default 20). When it elapses, the break overlay is shown.
- FR2: The overlay stays up for `breakSeconds` (default 20), showing a visible countdown, then closes on its own and the work timer restarts.
- FR3: The work timer starts when the shell starts (i.e. at login) and restarts after every completed or skipped break.
- FR4: While the overlay is up, the work timer is not running.

### 5.2 Pre-break warning

- FR5: `warningSeconds` (default 10) before the break, a small unobtrusive notice appears announcing the upcoming break with a countdown.
- FR6: The warning never takes keyboard focus and never blocks input.
- FR7: Setting `warningSeconds` to 0 disables the warning.
- FR8: If the break is deferred (see 5.5), the warning is not shown; it appears only for a break that is actually about to fire.

### 5.3 Overlay

- FR9: The overlay covers the full area of every connected display, above all windows, including fullscreen ones.
- FR10: The overlay is opaque and fully obscures whatever is underneath. There is no dim-only mode: if the content stays readable, the eyes do not rest.
- FR11: The overlay content is a headline, a countdown of the remaining seconds, a one-line message, and a hint that Esc skips. Headline and message default to the 20-20-20 rule's distance ("Look 20 feet away" / "Rest your eyes on something far off, at least 20 feet away") and are both settings, so the reminder can be reworded, translated, or given in metres.
- FR12: The overlay grabs keyboard input while it is up, so keystrokes do not leak into the application underneath.
- FR13: The overlay uses the shell's current theme (`Color`, `Style` singletons), like every other Omarchy surface.
- FR14: The overlay never appears on top of the lock screen or the screensaver, and never keeps the machine awake.

### 5.4 Skipping

- FR15: Pressing Esc dismisses the overlay and restarts the work timer. A break is advisory, not enforced.

### 5.5 Deferral: idle, inhibitors, fullscreen

- FR16: Once the user has been idle for longer than `idlePauseMinutes`, the work timer is suspended and no break fires. Being away from the screen is already a break. `idlePauseMinutes` defaults to the current value of `workMinutes`, so lowering the work interval lowers the idle threshold with it unless the user sets it explicitly.
- FR17: When activity resumes after such an idle, the work timer restarts from zero. The next break lands a full `workMinutes` after the user comes back, never immediately on return.
- FR18: Idle shorter than `idlePauseMinutes` does not affect the timer. Short pauses neither suspend it nor reset it.
- FR19: A break that comes due while the user is briefly away is shown normally, counts down to nobody, and restarts the cycle. That is accepted behaviour: the coffee run was the break. With the default `idlePauseMinutes == workMinutes` this can happen at most once per absence, because the suspend always lands before a second break could fire.
- FR20: The break overlay must not itself register as user activity. Its presence cannot reset or hold off the idle monitor.
- FR21: The plugin respects Wayland idle inhibitors, so a break does not interrupt a video call or a fullscreen video that has inhibited idle.
- FR22: If a fullscreen window is active when the break comes due, the break is deferred rather than skipped. The plugin re-checks periodically and fires the break as soon as fullscreen is exited, preceded by the normal warning.
- FR23: Fullscreen deferral has no ceiling. A three-hour film defers for three hours; the break lands when it ends. Deferral does not stack either: however long it lasts, exactly one break is owed, and the work timer restarts from that break.

### 5.6 Configuration

- FR24: Settings live in the plugin's single entry in `~/.config/omarchy/shell.json`, inline on the entry, per the Omarchy plugin storage rules. Because this plugin is both a service and a bar widget, that entry sits in `bar.layout.<section>` while the widget is on the bar and in `plugins[]` when it is not; the settings move with it, and the service reads whichever holds it:

```json
{
  "version": 1,
  "plugins": [
    {
      "id": "io.github.camilolunacom.restreminder",
      "workMinutes": 20,
      "breakSeconds": 20,
      "warningSeconds": 10,
      "breakHeadline": "Look 20 feet away",
      "breakMessage": "Rest your eyes on something far off, at least 20 feet away"
    }
  ]
}
```

- FR25: `idlePauseMinutes` is optional and omitted from the example above on purpose: it tracks `workMinutes` unless the user sets it, and is only worth setting to decouple the two.
- FR26: Missing or invalid values fall back to the defaults (20 / 20 / 10, `workMinutes` for `idlePauseMinutes`, and the 20-20-20 wording for the two break strings) instead of breaking the shell. A blank string counts as missing: it is a typo, not an intent to blank the break screen.
- FR27: Saving `shell.json` applies the new values without restarting the shell (the shell already hot-reloads it); a change to the interval takes effect on the next timer cycle. Rewording the break screen is not a change to the interval and must not restart the cycle: only the timing values are compared when deciding to reschedule.

### 5.7 Manual control

- FR28: The service registers its own IPC target, `restreminder`, exposing `breakNow`, `skip`, `pause`, `resume` and `status`. It is in the MVP even though the CLI is not: it is a handful of lines, it makes the plugin drivable from a Hyprland keybinding on day one, and it is the surface the post-MVP CLI wraps unchanged.
- FR29: A pause with an expiry is persisted to `~/.local/state/omarchy/restreminder`, with an absolute wake time, and survives a shell restart. An indefinite pause is session state and is dropped on restart. Shell restarts are not rare — `omarchy update`, a font change, and `omarchy refresh shell` all trigger one — so a timed pause that silently expired early would be a bug, while a forgotten indefinite pause that survived forever would quietly defeat the plugin.
- FR30: The generic overlay calls keep working as a fallback: `omarchy-shell shell summon io.github.camilolunacom.restreminder '{}'` to take a break now, `omarchy-shell shell hide io.github.camilolunacom.restreminder` to dismiss.

### 5.8 Bar widget

- FR31: The plugin ships a bar widget showing the time remaining until the next break. It refreshes once per minute above a minute, and once per second below it.
- FR32: The widget renders the current state distinctly: counting down, deferred by fullscreen, suspended by idle, or paused by the user.
- FR33: Clicking the widget opens a popup: the countdown to the minute and second, the current state in words, and buttons to skip and to pause or resume. Clicking a countdown asks how long exactly, which the bar slot has no room to answer. Right click pauses and resumes without opening the popup, and middle click takes a break immediately.
- FR33a: Skip means "the next break is a full work interval away" on both sides of a break starting: during a break it ends the break, otherwise it drops the break that is coming. It is inert while paused or away, where nothing is owed, and the button says so by going dim rather than by failing silently.
- FR34: The widget is a view, not a second source of truth. It reads state from the resident service through `shell.serviceFor("io.github.camilolunacom.restreminder")` and holds no timer or settings of its own. There is one entry in shell.json, never two.
- FR35: The manifest sets `barWidget.defaultSection`, so enabling the plugin places the widget on the bar automatically. No manual `omarchy bar move` is needed to see it.
- FR36: The widget is optional. Removing it from the bar must not stop the timer or affect breaks in any way.

## 6. Technical approach

Omarchy 4 runs one long-lived Quickshell process (`omarchy-shell`) that hosts every surface as a plugin, so this is a plugin, not a daemon.

- Distributed as a git repo with `manifest.json` at the root, installable with `omarchy plugin add <url> --enable --yes`.
- `kinds: ["service", "overlay", "bar-widget"]`:
  - the `service` entry point holds the work timer, the idle monitor and the deferral logic; it is mounted at shell startup and stays resident;
  - the `overlay` entry point is the break screen, summoned by the service and torn down when the break ends;
  - the `barWidget` entry point is the countdown, reading state off the service. `omarchy.media` is the in-tree precedent for one plugin declaring both `service` and `bar-widget`.
- The service exposes control through its own `IpcHandler` with `target: "restreminder"`, the same pattern the lock service (`target: "lock"`) and the bar (`target: "omarchy.bar"`) use. This is required rather than cosmetic: the generic `omarchy-shell shell call <id> <method>` only reaches panel, overlay and menu loaders, never services, so a service with no IPC target of its own is unreachable from the CLI.
- The overlay is a layer-shell window on the overlay layer with exclusive keyboard focus, instantiated once per screen (`Variants` over `Quickshell.screens`) so multi-monitor is covered by construction.
- The pre-break warning is a separate, non-focusing surface on the same overlay layer, or a plain notification through `omarchy-notification-send`. Decide during Milestone 3 based on how it reads in practice.
- Idle detection reuses Quickshell's `IdleMonitor` with `respectInhibitors: true`, the same primitive `omarchy.idle` already uses, with `timeout` set to `idlePauseMinutes`. Its `isIdle` transitions are the suspend and restart signals for the work timer. `IdleMonitor` reads `timeout` when it registers and ignores a binding that resolves later, so the monitor is created imperatively with the timeout as an initial property and rebuilt when the threshold changes; bound to a config value it silently never reports idle.
- Wayland exposes no way to ask whether another client holds an idle inhibitor. Two `IdleMonitor`s on the same timeout, one respecting inhibitors and one not, answer it by disagreeing: input has stopped but only the inhibitor-blind one reports idle. This detects the case that matters (a player or call running while the user is not typing) and deliberately does not fire while the user is actively typing, when a break is legitimate.
- Fullscreen detection comes from Hyprland through `Quickshell.Hyprland`: `Hyprland.focusedWorkspace.hasFullscreen`, which is a bindable property with a change signal. No first-party Omarchy plugin reads it today.
- Config is read from `shell.shellConfig` (the shell injects itself into every plugin instance) and re-read on change.
- Reference implementations to follow in-tree: `shell/plugins/services/idle/` for a resident service with timers and idle, and `shell/plugins/reminders/` for a keepLoaded overlay with an `open`/`close`/`dismiss` contract.

### Development workflow

- Develop in place under `~/.config/omarchy/plugins/<id>/`. Not through a symlink: the watcher is `inotifywait -r`, which does not follow symlinks, and `omarchy plugin validate` refuses a symlinked plugin folder outright.
- Saving a file re-instantiates the plugin but can serve stale compiled QML, so the running code may not be the code on disk. `omarchy restart shell` is the reliable loop, and `omarchy-shell shell rescanPlugins` alone does not clear the component cache.
- Validate the manifest with `omarchy plugin validate <plugin-folder>` before publishing.
- Never touch `/usr/share/omarchy/`; it is package-owned and overwritten on update. It is the reference to read, not to edit.

## 7. Success criteria

- Fresh install to first break with zero configuration.
- The break overlay appears on all displays within ~100 ms of the interval elapsing.
- No measurable idle CPU cost in `omarchy-shell` beyond a one-second-resolution timer.
- Interval changes in `shell.json` apply without a shell restart.
- A full film watched fullscreen produces exactly one break, right after it ends.
- Returning from a long absence gives a full work interval before the next break.
- Nothing in the plugin can leave the session in a state where the shell must be restarted to recover (a failed overlay must not block input).

## 8. Milestones

1. Skeleton: manifest passing `omarchy plugin validate`, service plugin that logs a tick, installable and enable/disable clean.
2. Overlay: themed opaque fullscreen break screen with countdown, all displays, Esc to skip.
3. Config and warning: read `workMinutes` / `breakSeconds` / `warningSeconds` from `shell.json` with defaults and validation, hot reload, pre-break notice.
4. Deferral: idle reset, idle inhibitors, fullscreen deferral, no collision with screensaver or lock.
5. Control surface: the `restreminder` IPC target, including persisted timed pause.
6. Bar widget: countdown, state rendering, and the popup with skip and pause.
7. Packaging: README, install instructions, screenshot.

## 9. Open questions

None blocking. Behaviour is specified end to end for the MVP scope.

## 10. Post-MVP: the `restreminder` CLI

Deferred, specified here so the MVP's IPC target is designed to carry it.

- A `restreminder` executable, symlinked into `~/.local/bin` (already on PATH) at install time.
- Subcommands: `break`, `skip`, `pause [minutes]`, `resume`, `status`.
- `status` prints machine-readable output (seconds to the next break, current state) so it can feed a script or another bar.
- A thin wrapper over `omarchy-shell restreminder <method> <arg>`, holding no logic of its own.
- It cannot be `omarchy restreminder ...`. That dispatcher enumerates `/usr/bin/omarchy-*` only, which is package-owned and off limits to a user-installed plugin. If the plugin is ever packaged for the AUR, shipping `/usr/bin/omarchy-restreminder` makes the `omarchy` form work with no change to the plugin.
