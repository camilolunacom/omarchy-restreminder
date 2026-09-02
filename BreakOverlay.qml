import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "RestReminderModel.js" as Model

// The break screen.
//
// One opaque layer-shell window per output, above everything, for the length
// of the break. Opaque rather than dimmed on purpose: if the work underneath
// stays readable, the eyes never leave the screen and the break does nothing.
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null
  property var service: null
  property string omarchyPath: ""

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id)
    : "camilo.restreminder"

  property bool opened: false
  property int totalSeconds: 20
  property int secondsLeft: 0

  // Both lines are settings, so the reminder can be worded in the user's own
  // language. The service is the one that reads shell.json; when the overlay
  // is summoned on its own it has no service to ask, hence the defaults here.
  readonly property var settings: root.service && root.service.settings
    ? root.service.settings
    : ({})
  readonly property string headline: root.settings.breakHeadline
    || Model.DEFAULT_BREAK_HEADLINE
  readonly property string subtitle: root.settings.breakMessage
    || Model.DEFAULT_BREAK_MESSAGE

  // Summoned with a duration by the service; a bare summon (a keybinding, or
  // `omarchy-shell shell summon`) falls back to the configured break length.
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    var seconds = Number(payload.seconds)
    if (!isFinite(seconds) || seconds <= 0) {
      seconds = root.service && root.service.settings
        ? root.service.settings.breakSeconds
        : 20
    }

    root.totalSeconds = Math.max(1, Math.round(seconds))
    root.secondsLeft = root.totalSeconds
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  // Ends the break and tells the service how it ended, so the cycle restarts
  // from here either way.
  function finish(skipped) {
    if (!root.opened) return
    root.opened = false

    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    if (root.service && typeof root.service.breakFinished === "function") root.service.breakFinished(skipped === true)
  }

  function skip() {
    finish(true)
  }

  Timer {
    id: countdown
    interval: 1000
    repeat: true
    running: root.opened
    onTriggered: {
      root.secondsLeft = root.secondsLeft - 1
      if (root.secondsLeft <= 0) root.finish(false)
    }
  }

  // ------------------------------------------------------------- warning
  //
  // A passive heads-up that a break is coming, so it never lands mid-keystroke.
  // No keyboard focus and click-through everywhere except its own card: this
  // must not interrupt anything, it only announces.
  readonly property int warningSecondsLeft: root.service ? root.service.warningSecondsLeft : -1
  readonly property bool warningVisible: root.warningSecondsLeft >= 0 && !root.opened

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: warningWindow
      required property var modelData
      screen: modelData
      visible: root.warningVisible

      anchors { left: true; right: true; bottom: true }
      implicitHeight: warningCard.implicitHeight + Style.gapsOut * 4
      color: "transparent"

      WlrLayershell.namespace: "restreminder-warning"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      mask: Region { item: warningCard }

      Rectangle {
        id: warningCard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.gapsOut * 2
        implicitWidth: warningText.implicitWidth + Style.space(32)
        implicitHeight: warningText.implicitHeight + Style.space(20)
        radius: Style.cornerRadius
        color: Color.popups.background
        border.width: Math.max(1, Style.space(1))
        border.color: Color.popups.border

        Text {
          id: warningText
          anchors.centerIn: parent
          text: "Eye break in " + root.warningSecondsLeft + "s"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          textFormat: Text.PlainText
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: breakWindow
      required property var modelData
      screen: modelData
      visible: root.opened

      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"

      WlrLayershell.namespace: "restreminder-break"
      WlrLayershell.layer: WlrLayer.Overlay
      // The break has to swallow input: keystrokes must not land in whatever
      // was focused, and the user must not be able to keep working under it.
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore

      // Focus is per-window: the key catcher lives inside this delegate, one
      // copy per output, so the outer scope cannot reach it.
      onVisibleChanged: if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })

      Rectangle {
        anchors.fill: parent
        color: Color.background
        opacity: 1.0
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        // Swallow clicks rather than act on them: a stray click during a break
        // should not cut it short.
        onClicked: {}
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.skip()
            event.accepted = true
          }
        }
      }

      Column {
        anchors.centerIn: parent
        spacing: Style.space(24)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(implicitWidth, breakWindow.width * 0.8)
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: root.headline
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.displayLarge
          textFormat: Text.PlainText
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: String(root.secondsLeft)
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.displayLarge * 4
          textFormat: Text.PlainText
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(implicitWidth, breakWindow.width * 0.8)
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: root.subtitle
          color: Color.foreground
          opacity: 0.66
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          textFormat: Text.PlainText
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Esc to skip"
          color: Color.foreground
          opacity: 0.4
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          textFormat: Text.PlainText
        }
      }
    }
  }
}
