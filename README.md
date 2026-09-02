# Rest Reminder

A 20-20-20 eye break reminder for [Omarchy](https://omarchy.org/) 4.

Every 20 minutes of work, an opaque fullscreen screen covers every display for
20 seconds so your eyes can leave the screen. Both numbers are yours to change.
It runs inside the Omarchy shell as a plugin, not as another daemon, and it is
themed by whatever theme you are using.

It knows when not to interrupt: it stays out of the way while you are away from
the keyboard, while an app is holding an idle inhibitor, and while a window is
fullscreen.

## Install

```bash
omarchy plugin add https://github.com/<you>/omarchy-restreminder.git --enable --yes
```

That places the countdown widget on the right of the bar and starts the timer.
Nothing else to configure.

## Settings

Settings are inline on the plugin's entry in `~/.config/omarchy/shell.json`,
which hot-reloads on save. The entry lives in `bar.layout.<section>` while the
widget is on the bar, and in `plugins[]` when it is not:

```json
{
  "id": "camilo.restreminder",
  "workMinutes": 20,
  "breakSeconds": 20,
  "warningSeconds": 10
}
```

| Key                | Default        | What it does                                                     |
|--------------------|----------------|------------------------------------------------------------------|
| `workMinutes`      | `20`           | Minutes of work between breaks                                     |
| `breakSeconds`     | `20`           | How long the break screen stays up                                 |
| `warningSeconds`   | `10`           | Heads-up before the break; `0` turns it off                        |
| `idlePauseMinutes` | `workMinutes`  | Time away from the keyboard that counts as having taken the break  |

Anything missing or malformed falls back to its default rather than breaking
the shell.

## Using it

- **Esc** during a break skips it and restarts the interval.
- **Click** the bar widget to break now; **right click** to pause and resume.
- The widget shows the countdown, or the reason there isn't one: `away`,
  `hold` (waiting for fullscreen to end), `paused`, `break`.

Everything is scriptable through the shell's IPC, which is what a Hyprland
keybinding would call:

```bash
omarchy-shell restreminder status      # JSON: state, countdown, why it is deferred
omarchy-shell restreminder breakNow
omarchy-shell restreminder skip
omarchy-shell restreminder pause 30    # timed; survives a shell restart
omarchy-shell restreminder pause       # indefinite; cleared by a restart
omarchy-shell restreminder resume
```

## When a break does not fire

- **You are away.** Idle past `idlePauseMinutes` suspends the timer; coming back
  starts a fresh interval, so a break never greets you at your desk.
- **An app is holding an idle inhibitor** and you are not typing. That reads as
  a video or a call, which a break screen would interrupt rather than rest.
- **A window is fullscreen.** The break waits, with no ceiling: a three-hour
  film defers for three hours and the break lands when it ends.

At most one break is ever owed, however long the wait was.

## Hacking on it

The plugin is a plain git checkout in `~/.config/omarchy/plugins/camilo.restreminder/`.

```bash
omarchy plugin validate ~/.config/omarchy/plugins/camilo.restreminder
omarchy restart shell
journalctl -t omarchy-shell -f | grep restreminder
```

Two things that cost time here, worth knowing before they cost you the same:

- **Editing through a symlink does not work.** The plugin scanner's watcher is
  `inotifywait -r`, which does not follow symlinks, and `omarchy plugin validate`
  refuses a symlinked plugin folder outright. Keep the checkout in the real
  plugin directory.
- **Saving a file reloads the plugin but can serve stale compiled QML.** The
  service is re-instantiated, yet the code it runs may be the previous version,
  which makes for very confusing debugging. `omarchy restart shell` is the
  reliable loop; `omarchy-shell restreminder status` is the fastest way to see
  what the running code actually thinks.

## Layout

| File                    | What it is                                                   |
|-------------------------|--------------------------------------------------------------|
| `Service.qml`           | Resident service: the timer, the deferral rules, the IPC     |
| `BreakOverlay.qml`      | The break screen and the pre-break warning                   |
| `BarWidget.qml`         | The countdown widget                                         |
| `RestReminderModel.js`  | Pure helpers: settings parsing, label formatting             |
| `PRD.md`                | What this is meant to do, and why                            |
