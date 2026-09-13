import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "components" as Comp
import "Yerrr.js" as Y

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
      baseColor: root.capturing ? Color.urgent : (root.hasLocation ? Color.accent : Util.alpha(Color.foreground, 0.85))
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
      root.hoverOpen = false
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
    open: root.hoverOpen && !(ready && !!service.dashVisible)
    triggerMode: "hover"
    contentWidth: Math.min(840, Math.max(560, Style.space(760)))
    contentHeight: Math.min(680, Style.space(640))
    onVisibleChanged: if (!visible) root.hoverOpen = false
    onContainsMouseChanged: {
      if (containsMouse) root.hoverOpen = true
      else if (!hoverHandler.hovered) root.hoverOpen = false
    }

    // Polished hover peek — compact Jarvis summary
    ColumnLayout {
      width: parent.width - Style.space(16)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(12)
      spacing: Style.space(10)

      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Comp.WavySprite { Layout.preferredWidth: 72; Layout.preferredHeight: 22; capturing: root.capturing; text: "YERRR"; fontSize: 13; baseColor: root.capturing ? Color.urgent : Color.accent }
        Column { Layout.fillWidth: true; spacing: 2
          Text { width: parent.width; text: ready ? service.crossSummary : "Loading NYC…"; color: Util.alpha(Color.foreground,0.75); font.family: Style.font.family; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight }
          Text { width: parent.width; text: ready ? ("📍 " + (service.zip||service.borough||"NYC") + " • " + (isFinite(service.effectiveLat()) ? service.effectiveLat().toFixed(3) + "," + service.effectiveLon().toFixed(3) : "locating") + " • " + service.data311.length + " 311 • " + service.dataCiti.length + " Citi") : "Locating…"; color: Util.alpha(Color.foreground,0.55); font.family: Style.font.family; font.pixelSize: 10; elide: Text.ElideRight }
        }
        Rectangle { Layout.preferredWidth: 52; Layout.preferredHeight: 22; radius: 11; color: Util.alpha(Color.accent, 0.12); border.width: 1; border.color: Util.alpha(Color.accent, 0.22); Text { anchors.centerIn: parent; text: ready ? service.data311.length + " 311" : "—"; color: Color.accent; font.family: Style.font.family; font.pixelSize: 10; font.bold: true } }
      }
      Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground,0.08) }
      GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 8
        rowSpacing: 8
        Repeater {
          model: ready ? [
            {k:"311", key:"311", v: service.data311.length + " reports", sub: service.data311[0] ? String(service.data311[0].subtype||"").slice(0,20) : "—"},
            {k:"Subway", key:"subway", v: service.dataSubway.length + " lines", sub: service.dataSubway[0] ? String(service.dataSubway[0].status||"").slice(0,20) : "—"},
            {k:"Citi", key:"citi", v: service.dataCiti.length + " stations", sub: service.dataCiti[0] ? (service.dataCiti[0].bikes + " bikes • " + (service.dataCiti[0].name||"").slice(0,14)) : "—"},
            {k:"Dispensaries", key:"disp", v: service.dataDisp.length + " retail", sub: service.dataDisp[0] ? String(service.dataDisp[0].dba||"").slice(0,18) + (service.dataDisp[0].zip ? " • " + service.dataDisp[0].zip : "") : "—"},
            {k:"NYPD", key:"nypd", v: service.dataNYPD.length + " complaints", sub: service.dataNYPD[0] ? String(service.dataNYPD[0].subtype||"").slice(0,18) : "—"},
            {k:"Lottery", key:"lottery", v: service.dataLottery[0] ? String(service.dataLottery[0].raw.winning_numbers||"").slice(0,18) : service.dataLottery.length + " winners", sub: service.dataLottery[0] ? String(service.dataLottery[0].subtype||"") + " " + Y.timeAgo(new Date(service.dataLottery[0].ts).toISOString()) : "—"}
          ] : []
          delegate: Rectangle {
            required property var modelData
            Layout.fillWidth: true; Layout.preferredHeight: 56; radius: 10
            color: Util.alpha(Color.foreground,0.04); border.width:1; border.color: Util.alpha(Color.foreground,0.07)
            Column { anchors.centerIn: parent; width: parent.width - 16; spacing: 3
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.k; color: Util.alpha(Color.foreground,0.6); font.family: Style.font.family; font.pixelSize: 10; font.bold: true }
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.v; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight }
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.sub; color: Util.alpha(Color.foreground,0.5); font.family: Style.font.family; font.pixelSize: 9; elide: Text.ElideRight }
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onEntered: parent.border.color = Util.alpha(Color.accent,0.55)
              onExited: parent.border.color = Util.alpha(Color.foreground,0.07)
              onClicked: {
                if (modelData.key && root.service) root.service.dashRequest = modelData.key
                if (root.service && !root.service.dashVisible && root.service.toggleDash) root.service.toggleDash()
              }
            }
          }
        }
      }
      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text { Layout.fillWidth: true; text: "Click YERRR or a card to open full dash • drag map, scroll zoom"; color: Util.alpha(Color.foreground,0.38); font.family: Style.font.family; font.pixelSize: 9; elide: Text.ElideRight }
        Rectangle { Layout.preferredWidth: 28; Layout.preferredHeight: 20; radius: 8; color: Util.alpha(Color.accent,0.12); border.width: 1; border.color: Util.alpha(Color.accent,0.22); Text { anchors.centerIn: parent; text: "↗"; color: Color.accent; font.pixelSize: 10 } MouseArea { anchors.fill: parent; onClicked: if (root.service && root.service.toggleDash) root.service.toggleDash() } }
      }
    }
  }
}
