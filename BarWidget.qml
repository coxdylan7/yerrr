import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components" as Comp

BarWidget {
  id: root
  moduleName: "djc.yerrr"

  readonly property var service: {
    if (!bar || !bar.shell || typeof bar.shell.serviceFor !== "function") return null
    return bar.shell.serviceFor("djc.yerrr")
  }
  readonly property bool ready: service !== null
  readonly property bool capturing: ready ? !!service.capturing : false
  readonly property bool hasLocation: ready ? (!isNaN(service.effectiveLat()) && !isNaN(service.effectiveLon())) : false
  readonly property string borough: ready ? String(service.borough||"") : ""
  readonly property string zip: ready ? String(service.zip||"") : ""

  implicitWidth: 92
  implicitHeight: bar ? bar.barSize : 28

  Rectangle { anchors.fill: parent; color: "transparent"; radius: 6 }

  Item {
    id: row
    anchors.centerIn: parent
    width: 72; height: 22
    Comp.WavySprite {
      anchors.centerIn: parent
      phase: 0
      capturing: root.capturing
      text: "YERRR"
      fontSize: 13
      baseColor: root.capturing ? Color.urgent : (root.hasLocation ? "#00e5ff" : Util.alpha(Color.foreground, 0.85))
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (service && service.toggleDash) service.toggleDash()
      else console.log("yerrr: no service for toggleDash")
    }
    onEntered: {
      if (bar && bar.showTooltip) bar.showTooltip(root, ready ? (service.terminalOutput||"YERRR — click to expand Jarvis dash") : "Loading Yerrr…")
    }
    onExited: { if (bar && bar.hideTooltip) bar.hideTooltip(root) }
  }
}
