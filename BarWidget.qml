import QtQuick
import QtQuick.Layouts
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

  property bool hoverOpen: false

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

  HoverHandler {
    id: hoverHandler
    onHoveredChanged: {
      if (hovered) root.hoverOpen = true
      else if (!popup.containsMouse) root.hoverOpen = false
    }
  }
  MouseArea {
    anchors.fill: parent
    z: 10
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton
    onClicked: {
      if (service && service.toggleDash) service.toggleDash()
      else console.log("yerrr: no service for toggleDash")
      // also toggle hover popup for click fallback
      root.hoverOpen = !root.hoverOpen
    }
    onEntered: {
      root.hoverOpen = true
      if (bar && bar.showTooltip) bar.showTooltip(root, ready ? (service.terminalOutput||"YERRR — hover to expand Jarvis dash") : "Loading Yerrr…")
    }
    onExited: {
      if (!popup.containsMouse) root.hoverOpen = false
      if (bar && bar.hideTooltip) bar.hideTooltip(root)
    }
  }

  // Hover dash — PopupCard like pot-head (reliable, no PanelWindow service injection issue)
  PopupCard {
    id: popup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.hoverOpen || (ready && !!service.dashVisible)
    triggerMode: "hover"
    contentWidth: Math.min(840, Math.max(560, Style.space(760)))
    contentHeight: Math.min(680, Style.space(640))
    onVisibleChanged: if (!visible) root.hoverOpen = false
    onContainsMouseChanged: {
      if (containsMouse) root.hoverOpen = true
      else if (!hoverHandler.hovered) root.hoverOpen = false
    }

    // Minimal dash content for hover — full Dash.qml is the click-expanded overlay
    Column {
      width: parent.width - Style.space(16)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(12)
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: 8
        Comp.WavySprite { width: 72; height: 22; capturing: root.capturing; text: "YERRR"; fontSize: 13; baseColor: root.capturing ? Color.urgent : "#00e5ff" }
        Text { text: ready ? service.crossSummary : "Loading NYC…"; color: Util.alpha(Color.foreground,0.65); font.family: Style.font.family; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width - 80; anchors.verticalCenter: parent.verticalCenter }
      }
      Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.foreground,0.08) }
      Text { width: parent.width; wrapMode: Text.Wrap; text: ready ? ("📍 " + (service.zip||service.borough||"loc") + " • " + service.data311.length + " 311 • " + service.dataSubway.length + " subway • " + service.dataDisp.length + " dispos") : "Loading…"; color: Util.alpha(Color.foreground,0.6); font.family: Style.font.family; font.pixelSize: 11 }
      GridLayout {
        width: parent.width
        columns: 2
        columnSpacing: 8
        rowSpacing: 8
        Repeater {
          model: ready ? [
            {k:"311", v: service.data311.length + " • " + (service.data311[0] ? String(service.data311[0].subtype||"").slice(0,22) : "—")},
            {k:"Subway", v: service.dataSubway.length + " lines • " + (service.dataSubway[0] ? String(service.dataSubway[0].status||"").slice(0,22) : "—")},
            {k:"Citi", v: service.dataCiti.length + " stations"},
            {k:"Dispensaries", v: service.dataDisp.length + " NY retail"},
            {k:"Lottery", v: service.dataLottery.length + " winners"}
          ] : []
          delegate: Rectangle {
            required property var modelData
            Layout.fillWidth: true; height: 48; radius: 8
            color: Util.alpha(Color.foreground,0.04); border.width:1; border.color: Util.alpha(Color.foreground,0.07)
            Column { anchors.centerIn: parent; spacing: 2
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.k; color: Util.alpha(Color.foreground,0.5); font.family: Style.font.family; font.pixelSize: 10; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.v; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width - 12; horizontalAlignment: Text.AlignHCenter }
            }
          }
        }
      }
      Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Hover keeps open — click YERRR for full Jarvis overlay (terminal ❯)"; color: Util.alpha(Color.foreground,0.38); font.family: Style.font.family; font.pixelSize: 9 }
    }
  }
}
