import QtQuick
import qs.Commons
import qs.Ui
import "RestReminderModel.js" as Model

// Countdown to the next break.
//
// A view onto the service and nothing more: it holds no timer and no settings
// of its own, so removing it from the bar cannot change when breaks happen.
BarWidget {
  id: root
  moduleName: "camilo.restreminder"

  readonly property var service: root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor(root.moduleName)
    : null

  readonly property string state: root.service ? root.service.stateName : "unknown"
  readonly property int secondsToBreak: root.service ? root.service.secondsToBreak : -1

  readonly property string label: Model.widgetLabel(root.state, root.secondsToBreak)
  readonly property string tooltip: Model.widgetTooltip(root.state, root.secondsToBreak)

  // A break due within the warning window is the one moment this widget has
  // something urgent to say.
  readonly property bool imminent: root.state === "counting"
    && root.service
    && root.service.warningSecondsLeft >= 0

  function takeBreak() {
    if (root.service && typeof root.service.startBreak === "function") root.service.startBreak()
  }

  function togglePause() {
    if (!root.service) return
    if (root.service.paused) root.service.unpause()
    else root.service.pause(0)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    active: root.imminent || root.state === "paused"
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (b === Qt.RightButton) root.togglePause()
      else root.takeBreak()
    }
  }
}
