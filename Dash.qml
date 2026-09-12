import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "components" as Comp
import "Yerrr.js" as Y

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var service: null
  readonly property bool ready: service !== null
  readonly property bool dashVisible: ready ? !!service.dashVisible : false
  readonly property bool capturing: ready ? !!service.capturing : false

  // Root overlay window
  PanelWindow {
    id: dashWindow
    visible: root.dashVisible
    screen: Quickshell.screens[0]
    anchors { top: true; left: true; right: true; bottom: true }
    color: Util.alpha(Color.background, 0.88)
    WlrLayershell.namespace: "omarchy-yerrr"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    // Background dim + click to close
    MouseArea {
      anchors.fill: parent
      onClicked: { if (service && service.toggleDash) service.toggleDash() }
    }

    // Main dash card
    Rectangle {
      id: dashCard
      width: Math.min(parent.width * 0.92, 1180)
      height: Math.min(parent.height * 0.86, 760)
      anchors.centerIn: parent
      radius: 22
      color: Util.alpha(Color.background, 0.96)
      border.width: 1
      border.color: Util.alpha(Color.foreground, 0.14)
      // Shadow
      layer.enabled: true

      MouseArea { anchors.fill: parent; onClicked: {} } // block click-through

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // Header: wavy + borough/zip pills + filters + voice + close
        RowLayout {
          Layout.fillWidth: true
          spacing: 10

          Comp.WavySprite {
            Layout.preferredWidth: 84
            Layout.preferredHeight: 30
            capturing: root.capturing
            text: "YERRR"
            fontSize: 16
            baseColor: root.capturing ? Color.urgent : "#00e5ff"
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (service) service.toggleVoice() } }
          }

          // Borough pills
          Row {
            spacing: 6
            Layout.fillWidth: true
            Repeater {
              model: ["All","Manhattan","Brooklyn","Queens","Bronx","Staten Island"]
              delegate: Rectangle {
                required property string modelData
                height: 28; width: pillTxt.implicitWidth + 16; radius: 14
                color: (service && service.filters.borough === modelData) ? Util.alpha(Color.accent, 0.18) : Util.alpha(Color.foreground, 0.06)
                border.width: 1
                border.color: (service && service.filters.borough === modelData) ? Util.alpha(Color.accent, 0.32) : Util.alpha(Color.foreground, 0.08)
                Text { id: pillTxt; anchors.centerIn: parent; text: modelData=== "All" ? "All" : Y.boroughAbbr(modelData); font.family: Style.font.family; font.pixelSize: 11; font.bold: (service && service.filters.borough === modelData); color: (service && service.filters.borough === modelData) ? Color.accent : Color.foreground }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (service) { var f=service.filters; service.filters = { borough: modelData, zip: f.zip, hours: f.hours, kinds: f.kinds } } } }
              }
            }
          }

          Text {
            visible: ready && service.zip !== ""
            text: ready ? "ZIP " + service.zip : ""
            color: Util.alpha(Color.foreground, 0.7)
            font.family: Style.font.family; font.pixelSize: 11
            Layout.preferredWidth: implicitWidth
          }

          // Voice
          Rectangle {
            width: 76; height: 28; radius: 14
            color: root.capturing ? Util.alpha(Color.urgent, 0.18) : Util.alpha(Color.foreground, 0.06)
            border.width: 1; border.color: root.capturing ? Util.alpha(Color.urgent, 0.32) : Util.alpha(Color.foreground, 0.08)
            Row { anchors.centerIn: parent; spacing: 4
              Text { text: root.capturing ? "●" : "○"; color: root.capturing ? Color.urgent : Color.foreground; font.pixelSize: 12; SequentialAnimation on opacity { running: root.capturing; loops: Animation.Infinite; NumberAnimation{to:0.5; duration:420; easing.type:Easing.InOutSine} NumberAnimation{to:1; duration:420; easing.type:Easing.InOutSine} } }
              Text { text: root.capturing ? "STOP" : "Voice"; color: root.capturing ? Color.urgent : Color.foreground; font.family: Style.font.family; font.pixelSize: 11; font.bold: root.capturing }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (service) service.toggleVoice() } }
          }

          // Refresh
          Rectangle {
            width: 34; height: 28; radius: 14
            color: Util.alpha(Color.foreground, 0.06); border.width: 1; border.color: Util.alpha(Color.foreground, 0.08)
            Text { anchors.centerIn: parent; text: ""; font.pixelSize: 12; color: Color.foreground }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (service) service.refreshAll() } }
          }

          // Close
          Rectangle {
            width: 32; height: 28; radius: 14
            color: Util.alpha(Color.foreground, 0.06); border.width: 1; border.color: Util.alpha(Color.foreground, 0.08)
            Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 12; color: Color.foreground }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (service) service.toggleDash() } }
          }
        }

        // Cross summary + time filter
        RowLayout {
          Layout.fillWidth: true
          spacing: 8
          Text {
            Layout.fillWidth: true
            text: ready ? service.crossSummary : "Loading NYC…"
            color: Util.alpha(Color.foreground, 0.72)
            font.family: Style.font.family; font.pixelSize: 12
            elide: Text.ElideRight
          }
          Row {
            spacing: 6
            Repeater {
              model: [24, 168]
              delegate: Rectangle {
                required property int modelData
                height: 22; width: 44; radius: 11
                color: (service && service.filters.hours === modelData) ? Util.alpha(Color.accent, 0.14) : Util.alpha(Color.foreground, 0.06)
                border.width: 1; border.color: (service && service.filters.hours === modelData) ? Util.alpha(Color.accent, 0.28) : Util.alpha(Color.foreground, 0.08)
                Text { anchors.centerIn: parent; text: modelData===24 ? "24h" : "7d"; font.family: Style.font.family; font.pixelSize: 10; color: (service && service.filters.hours === modelData) ? Color.accent : Color.foreground }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (service) { var f=service.filters; service.filters={ borough:f.borough, zip:f.zip, hours:modelData, kinds:f.kinds } } } }
              }
            }
          }
          Text {
            text: ready ? (service.locationSource!=="none" ? ("📍 " + (service.zip||service.borough||"loc") + " ±" + (isFinite(service.accuracy)? Math.round(service.accuracy)+"m" : "")) : "locating…") : ""
            color: Util.alpha(Color.foreground, 0.5); font.family: Style.font.family; font.pixelSize: 10
          }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, 0.08) }

        // Main content: left map placeholder + right cards
        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 12

          // Map placeholder (replace with WebEngine later)
          Rectangle {
            Layout.preferredWidth: 360
            Layout.fillHeight: true
            radius: 14
            color: Util.alpha(Color.foreground, 0.04)
            border.width: 1; border.color: Util.alpha(Color.foreground, 0.08)
            Column {
              anchors.centerIn: parent
              spacing: 8
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "🗽"; font.pixelSize: 36 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "NYC Map — OSM/tiles soon"; color: Util.alpha(Color.foreground, 0.6); font.family: Style.font.family; font.pixelSize: 11 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: ready ? (isFinite(service.effectiveLat()) ? service.effectiveLat().toFixed(4)+", "+service.effectiveLon().toFixed(4) : "no location") : ""; color: Util.alpha(Color.foreground, 0.45); font.family: Style.font.family; font.pixelSize: 10 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Cross-ref: 311 • subway • citi"; color: Util.alpha(Color.accent, 0.7); font.family: Style.font.family; font.pixelSize: 10 }
            }
          }

          // Cards scroll
          Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: cardsCol.implicitHeight
            clip: true
            flickableDirection: Flickable.VerticalFlick
            interactive: cardsCol.implicitHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: cardsCol
              width: parent.width
              spacing: 10

              // Helper to count filtered 311
              property var filtered311: ready ? (function(){
                var a = Y.filterByTime(service.data311, service.filters.hours)
                if (service.filters.borough!=="All") a = Y.filterByBorough(a, service.filters.borough)
                if (service.filters.zip) a = Y.filterByZip(a, service.filters.zip)
                return a
              })() : []

              // 311 card
              Rectangle {
                width: parent.width; radius: 12
                height: col311.implicitHeight + 20
                color: Util.alpha(Color.background, 0.92); border.width: 1; border.color: Util.alpha(Color.foreground, 0.08)
                Column { id: col311; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; spacing: 6
                  Row { width: parent.width; spacing: 8
                    Text { text: "311"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 13; font.bold: true }
                    Rectangle { height: 18; width: txt311.implicitWidth+10; radius: 8; color: Util.alpha(Color.accent,0.12); border.width:1; border.color: Util.alpha(Color.accent,0.22)
                      Text { id: txt311; anchors.centerIn: parent; text: ready ? String(cardsCol.filtered311.length) + " in " + service.filters.hours + "h" : "—"; color: Color.accent; font.family: Style.font.family; font.pixelSize: 10 }
                    }
                    Text { text: ready && service.filters.borough!=="All" ? service.filters.borough : ""; color: Util.alpha(Color.foreground,0.5); font.family: Style.font.family; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                  }
                  Repeater {
                    model: ready ? Y.topComplaintTypes(cardsCol.filtered311, 3) : []
                    delegate: Row { required property var modelData; spacing: 6; width: col311.width
                      Text { text: modelData.type; color: Util.alpha(Color.foreground,0.75); font.family: Style.font.family; font.pixelSize: 11; width: parent.width*0.62; elide: Text.ElideRight }
                      Text { text: String(modelData.count); color: Util.alpha(Color.foreground,0.55); font.family: Style.font.family; font.pixelSize: 11 }
                    }
                  }
                  Text { width: parent.width; wrapMode: Text.Wrap; text: ready && cardsCol.filtered311.length>0 ? String(cardsCol.filtered311[0].subtype || "") + " — " + String(cardsCol.filtered311[0].descriptor||"").slice(0,80) : "No 311 in filter"; color: Util.alpha(Color.foreground,0.5); font.family: Style.font.family; font.pixelSize: 10; elide: Text.ElideRight }
                }
              }

              // Subway card
              Rectangle {
                width: parent.width; radius: 12
                height: colSub.implicitHeight + 20
                color: Util.alpha(Color.background, 0.92); border.width: 1; border.color: Util.alpha(Color.foreground, 0.08)
                Column { id: colSub; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; spacing: 6
                  Row { width: parent.width; spacing: 8
                    Text { text: "MTA Subway"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 13; font.bold: true }
                    Text { text: ready ? String(service.dataSubway.length) + " lines" : "—"; color: Util.alpha(Color.foreground,0.55); font.family: Style.font.family; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                  }
                  Repeater {
                    model: ready ? service.dataSubway.slice(0,4) : []
                    delegate: Row { required property var modelData; spacing: 8; width: colSub.width
                      Rectangle { width: 28; height: 18; radius: 4; color: (String(modelData.status).toLowerCase().indexOf("del")!==-1) ? Util.alpha(Color.urgent,0.18) : Util.alpha(Color.accent,0.12); border.width:1; border.color: (String(modelData.status).toLowerCase().indexOf("del")!==-1) ? Util.alpha(Color.urgent,0.28) : Util.alpha(Color.accent,0.22)
                        Text { anchors.centerIn: parent; text: String(modelData.subtype||"").slice(0,3); font.family: Style.font.family; font.pixelSize: 10; font.bold: true; color: (String(modelData.status).toLowerCase().indexOf("del")!==-1) ? Color.urgent : Color.accent }
                      }
                      Text { text: String(modelData.status||"Good service").slice(0,64); color: Util.alpha(Color.foreground,0.75); font.family: Style.font.family; font.pixelSize: 11; width: parent.width - 36; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                  }
                  Text { visible: ready && service.dataSubway.length===0; text: "No subway data yet — polling every 30s"; color: Util.alpha(Color.foreground,0.45); font.family: Style.font.family; font.pixelSize: 10 }
                }
              }

              // Citi / NYPD / Air / DOB / Parking / Lottery small grid
              GridLayout {
                width: parent.width
                columns: 2
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                  model: ready ? [
                    {k:"Citi Bike", v: service.dataCiti.length + " stations", c: service.dataCiti.slice(0,1)[0] ? (service.dataCiti[0].bikes + " bikes") : "—"},
                    {k:"NYPD", v: service.dataNYPD.length + " complaints", c: (Y.topComplaintTypes(service.dataNYPD,1)[0] ? Y.topComplaintTypes(service.dataNYPD,1)[0].type : "—")},
                    {k:"Air Quality", v: service.dataAir.length + " sites", c: service.dataAir[0] ? ("AQI " + String(service.dataAir[0].aqi||"")) : "—"},
                    {k:"DOB Permits", v: service.dataDOB.length + " permits", c: service.dataDOB[0] ? String(service.dataDOB[0].subtype||"").slice(0,22) : "—"},
                    {k:"Parking", v: service.dataParking.length + " violations", c: service.dataParking[0] ? String(service.dataParking[0].subtype||"").slice(0,22) : "—"},
                    {k:"Lottery", v: service.dataLottery.length + " winners", c: service.dataLottery[0] ? (String(service.dataLottery[0].zip||"") + " " + String(service.dataLottery[0].amount||"").slice(0,12)) : "—"}
                  ] : []
                  delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 64; radius: 10
                    color: Util.alpha(Color.foreground, 0.04); border.width: 1; border.color: Util.alpha(Color.foreground, 0.07)
                    Column { anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: 10; spacing: 2
                      Text { text: modelData.k; color: Util.alpha(Color.foreground,0.6); font.family: Style.font.family; font.pixelSize: 10; font.bold: true }
                      Text { text: modelData.v; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight; width: parent.width }
                      Text { text: modelData.c; color: Util.alpha(Color.foreground,0.55); font.family: Style.font.family; font.pixelSize: 10; elide: Text.ElideRight; width: parent.width }
                    }
                  }
                }
              }

              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Data: NYC Open Data (Socrata) • MTA GTFS • Citi GBFS • NY Lottery • cross-ref by ZIP/borough/time"; color: Util.alpha(Color.foreground,0.32); font.family: Style.font.family; font.pixelSize: 9; wrapMode: Text.Wrap }
            }
          }
        }

        // Terminal strip
        Rectangle {
          Layout.fillWidth: true
          height: 84
          radius: 12
          color: Util.alpha("#0a0a0f", 0.96)
          border.width: 1; border.color: Util.alpha("#00e5ff", 0.14)
          Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6
            Text {
              width: parent.width
              text: ready ? String(service.terminalOutput).slice(0, 220) : "yerrr ready"
              color: "#7af0ff"
              font.family: "monospace"
              font.pixelSize: 11
              elide: Text.ElideRight
            }
            RowLayout {
              width: parent.width
              spacing: 8
              Text { text: "❯"; color: "#00e5ff"; font.family: "monospace"; font.pixelSize: 13; Layout.alignment: Qt.AlignVCenter }
              TextInput {
                id: termInput
                Layout.fillWidth: true
                text: ready ? service.terminalText : ""
                color: "#e0faff"
                font.family: "monospace"
                font.pixelSize: 12
                clip: true
                focus: root.dashVisible
                onTextChanged: { if (service) service.terminalText = text }
                Keys.onReturnPressed: { if (service) service.handleTerminalSubmit(text); termInput.text = "" }
                Keys.onEnterPressed: { if (service) service.handleTerminalSubmit(text); termInput.text = "" }
                Keys.onEscapePressed: { if (service) service.toggleDash() }
              }
              Rectangle {
                width: 28; height: 22; radius: 6
                color: Util.alpha("#00e5ff", 0.14); border.width: 1; border.color: Util.alpha("#00e5ff", 0.22)
                Text { anchors.centerIn: parent; text: "↵"; color: "#00e5ff"; font.pixelSize: 10 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (service) service.handleTerminalSubmit(termInput.text); termInput.text = "" } }
              }
            }
            Text {
              text: "try:  \"bk 311 24h\"  \"queens subway\"  \"11211 citi\"  \"clear\"  \"refresh\""
              color: Util.alpha("#7af0ff", 0.45)
              font.family: "monospace"
              font.pixelSize: 9
            }
          }
        }
      }
    }
  }
}
