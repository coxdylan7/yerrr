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

  implicitWidth: Math.max(row.implicitWidth + Style.space(14)*2, 92)
  implicitHeight: bar ? bar.barSize : 28

  Rectangle { anchors.fill: parent; color: "transparent"; radius: 6 }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Item {
      width: 72; height: 22
      anchors.verticalCenter: parent.verticalCenter
      Comp.WavySprite {
        anchors.centerIn: parent
        phase: 0
        capturing: root.capturing
        text: "YERRR"
        fontSize: 13
        baseColor: root.capturing ? Color.urgent : (root.hasLocation ? "#00e5ff" : Util.alpha(Color.foreground, 0.85))
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      Text {
        text: {
          if (!ready) return "yerrr"
          if (root.capturing) return "● listening"
          if (root.borough && root.borough!=="All") return root.borough.slice(0,3).toUpperCase() + (root.zip ? " " + root.zip : "")
          if (service.lastUpdate) return "NYC"
          return "YERRR"
        }
        color: root.capturing ? Color.urgent : (bar ? bar.foreground : Color.foreground)
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: 11
        font.bold: true
      }
      Text {
        visible: ready && !!service.crossSummary
        text: ready ? String(service.crossSummary).slice(0, 44) : ""
        color: Util.alpha(Color.foreground, 0.58)
        font.family: Style.font.family
        font.pixelSize: 9
        elide: Text.ElideRight
        width: 110
      }
    }

    // Small dot indicator for data freshness
    Rectangle {
      width: 6; height: 6; radius: 3
      color: ready && service.lastUpdate ? "#22c55e" : Util.alpha(Color.foreground, 0.25)
      anchors.verticalCenter: parent.verticalCenter
      SequentialAnimation on opacity {
        running: ready && service.data311 && service.data311.length>0
        loops: Animation.Infinite
        NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
      }
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
