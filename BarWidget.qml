import QtQuick
import qs.Commons
import qs.Ui
import "RestReminderModel.js" as Model

// Countdown to the next break, and the popup behind it.
//
// A view onto the service and nothing more: it holds no timer and no settings
// of its own, so removing it from the bar cannot change when breaks happen.
//
// A Panel rather than a plain BarWidget because clicking a countdown asks
// "how long exactly?", which the bar slot has no room to answer: the label
// rounds to whole minutes, the popup shows the seconds and the two controls
// worth reaching for at that moment.
Panel {
  id: root
  moduleName: "io.github.camilolunacom.restreminder"
  // Short on purpose: the plugin id is the marketplace's permanent
  // identifier, not something anyone should have to type at a prompt.
  ipcTarget: "restreminder-popup"

  readonly property var service: root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor(root.moduleName)
    : null

  readonly property string state: root.service ? root.service.stateName : "unknown"
  readonly property int secondsToBreak: root.service ? root.service.secondsToBreak : -1

  readonly property string label: Model.widgetLabel(root.state, root.secondsToBreak)

  readonly property bool pausedNow: root.service ? root.service.paused === true : false

  // Breaking now is the one thing a paused reminder should not do behind the
  // user's back: they just said not now.
  readonly property bool canBreak: root.state !== "breaking" && !root.pausedNow

  // Skipping is only meaningful while a break is running or on its way. Paused
  // and away both mean nothing is owed, so the button says so by going dim
  // rather than by failing silently.
  readonly property bool canSkip: root.state === "breaking"
    || root.state === "counting"
    || root.state === "deferred"

  // A break due within the warning window is the one moment this widget has
  // something urgent to say.
  readonly property bool imminent: root.state === "counting"
    && root.service
    && root.service.warningSecondsLeft >= 0

  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  // The label is a text block rather than an icon, so the bar's open-panel
  // mark takes the painted width instead of a fraction of the slot.
  readonly property real openPanelIndicatorWidth: button.labelWidth

  // Keyboard cursor over the two buttons. Dormant until the user actually
  // presses an arrow, so opening the popup with the mouse does not paint a
  // cursor ring nobody asked for.
  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property int lastCursorIndex: 2

  function takeBreak() {
    if (!root.canBreak) return
    if (root.service && typeof root.service.startBreak === "function") root.service.startBreak()
    root.close()
  }

  function skipBreak() {
    if (!root.canSkip) return
    if (root.service && typeof root.service.skipBreak === "function") root.service.skipBreak()
  }

  function togglePause() {
    if (!root.service) return
    if (root.service.paused) root.service.unpause()
    else root.service.pause(0)
  }

  function moveCursor(dx) {
    if (dx === 0) return
    root.cursorActive = true
    root.cursorIndex = Math.max(0, Math.min(root.lastCursorIndex, root.cursorIndex + dx))
  }

  function activateCursor() {
    if (root.cursorIndex === 0) root.takeBreak()
    else if (root.cursorIndex === 1) root.skipBreak()
    else root.togglePause()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    root.cursorActive = false
    root.cursorIndex = 0
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    active: root.imminent || root.state === "paused"
    // No hover tooltip: the popup a click away says all of it, in more detail
    // and without ambushing the cursor on its way across the bar.
    tooltipText: ""

    // Middle click keeps break-now one press away now that the left button
    // opens the popup instead.
    onPressed: function(b) {
      if (b === Qt.RightButton) root.togglePause()
      else if (b === Qt.MiddleButton) root.takeBreak()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Wide enough for the longest status line beside the countdown; below
    // this the caption elides and the popup stops saying anything the bar
    // label wasn't already saying.
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx !== 0 ? dx : dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "b" || t === "B") root.takeBreak()
        else if (t === "s" || t === "S") root.skipBreak()
        else if (t === "p" || t === "P") root.togglePause()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.spacing.panelGap

        // ---------- Hero: title/status · countdown ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroLabels.implicitHeight, heroCountdown.implicitHeight)

          Column {
            id: heroLabels
            anchors.left: parent.left
            anchors.right: heroCountdown.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Rest Reminder"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: Model.panelStatus(root.state).toUpperCase()
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }

          // The reason the popup exists: minutes and seconds, ticking, which
          // the bar label rounds away.
          Text {
            id: heroCountdown
            textFormat: Text.PlainText
            text: Model.panelCountdown(root.state, root.secondsToBreak)
            color: root.imminent && root.bar ? root.bar.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        // ---------- Controls ----------
        Row {
          id: actionRow
          width: parent.width
          spacing: Style.space(6)

          readonly property real cellWidth: (width - spacing * 2) / 3

          Button {
            width: actionRow.cellWidth
            iconText: "󰈉"
            iconSize: Style.font.title
            text: "Break"
            tooltipText: "Start an eye break right now"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            enabled: root.canBreak
            opacity: root.canBreak ? 1.0 : 0.45
            hasCursor: root.cursorActive && root.cursorIndex === 0
            onClicked: root.takeBreak()
            onHovered: function(h) {
              if (!h) return
              root.cursorActive = true
              root.cursorIndex = 0
            }
          }

          Button {
            width: actionRow.cellWidth
            iconText: "󰒭"
            iconSize: Style.font.title
            text: Model.skipLabel(root.state)
            tooltipText: Model.skipTooltip(root.state)
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            enabled: root.canSkip
            opacity: root.canSkip ? 1.0 : 0.45
            hasCursor: root.cursorActive && root.cursorIndex === 1
            onClicked: root.skipBreak()
            onHovered: function(h) {
              if (!h) return
              root.cursorActive = true
              root.cursorIndex = 1
            }
          }

          Button {
            width: actionRow.cellWidth
            iconText: root.pausedNow ? "󰐊" : "󰏤"
            iconSize: Style.font.title
            text: root.pausedNow ? "Resume" : "Pause"
            tooltipText: root.pausedNow
              ? "Resume rest reminders"
              : "Pause rest reminders until you resume them"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            active: root.pausedNow
            hasCursor: root.cursorActive && root.cursorIndex === 2
            onClicked: root.togglePause()
            onHovered: function(h) {
              if (!h) return
              root.cursorActive = true
              root.cursorIndex = 2
            }
          }
        }
      }
    }
  }
}
