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
  readonly property var effectiveService: service ? service : (shell && typeof shell.serviceFor === "function" ? shell.serviceFor("djc.yerrr") : null)
  readonly property bool ready: effectiveService !== null

  property string dashMode: "overview"   // "overview" | "detail"
  property string dashKey: ""            // dataset key for detail mode
  property string detailQuery: ""        // search box in detail
  property string pendingKey: ""         // dataset requested via service.dashRequest while window closed

  readonly property bool dashVisible: ready ? !!effectiveService.dashVisible : false
  readonly property bool capturing: ready ? !!effectiveService.capturing : false
  readonly property var filters: ready ? effectiveService.filters : ({ borough: "All", zip: "", hours: 24, kinds: [] })

  readonly property double mLat: ready && isFinite(effectiveService.effectiveLat()) ? effectiveService.effectiveLat() : 40.7128
  readonly property double mLon: ready && isFinite(effectiveService.effectiveLon()) ? effectiveService.effectiveLon() : -74.0060
  readonly property int mapZoom: 13
  readonly property int tilePx: 256

  onEffectiveServiceChanged: { console.log("yerrr Dash: effectiveService " + (effectiveService ? "yes dashVisible=" + effectiveService.dashVisible : "null")); root.dashMode = "overview" }

  // ---- dataset detail rows ----
  function detailRows(key) {
    if (!ready) return []
    var rows = []
    var h = Number(filters.hours || 24)
    var bor0 = filters.borough || "All"
    function pass(rec) {
      if (bor0 !== "All" && String(rec.borough || "").trim().toUpperCase() !== bor0.toUpperCase()) return false
      if (filters.zip && String(rec.zip || "").trim() !== String(filters.zip).trim()) return false
      return true
    }
    function timeFiltered(records) {
      var f = Y.filterByTime(records, h).filter(pass)
      if (f.length === 0 && records.length > 0) {
        // Fallback: show all matching borough/zip even if outside time window, so user sees data
        var fallback = records.filter(pass)
        if (fallback.length > 0) return fallback
      }
      return f
    }
    function searchFiltered(allRows) {
      if (root.detailQuery === "") return allRows
      var q = String(root.detailQuery).trim().toLowerCase()
      var out = []
      for (var j = 0; j < allRows.length; j++) {
        var rq = allRows[j]
        if (String(rq.primary + " " + rq.secondary + " " + rq.meta + " " + rq.badge + " " + rq.ago).toLowerCase().indexOf(q) !== -1) out.push(rq)
      }
      return out
    }
    if (key === "311") {
      var a = Y.sortByTimeDesc(timeFiltered(effectiveService.data311))
      var sa = searchFiltered(a)
      for (var i = 0; i < sa.length && i < 40; i++) {
        var r = sa[i]
        rows.push({ primary: String(r.subtype || r.raw.complaint_type || "311"), secondary: String(r.descriptor || r.status || ""), meta: String(r.neighborhood || r.raw.city || "") + (r.zip ? " " + r.zip : "") + (r.borough ? " · " + r.borough : ""), badge: String(r.borough || r.zip || ""), ago: Y.timeAgo(new Date(r.ts).toISOString()), lat: r.lat, lon: r.lon })
      }
    } else if (key === "subway") {
      var subAll = effectiveService.dataSubway.slice()
      var subFiltered = searchFiltered(subAll)
      for (i = 0; i < subFiltered.length && i < 40; i++) {
        var s2 = subFiltered[i]
        rows.push({ primary: String(s2.subtype || s2.id || ""), secondary: String(s2.status || ""), meta: String(s2.raw.cause || s2.raw.detail || ""), badge: String(s2.delayMin || 0) !== "0" ? s2.delayMin + "m del" : "ok", ago: Y.timeAgo(new Date(s2.ts).toISOString()), lat: s2.lat, lon: s2.lon })
      }
    } else if (key === "citi") {
      var cAll = timeFiltered(effectiveService.dataCiti)
      var cSearch = searchFiltered(cAll)
      for (i = 0; i < cSearch.length && i < 30; i++) {
        var ci = cSearch[i]
        rows.push({ primary: String(ci.id || ci.raw.name || ci.raw.station_id || "Station"), secondary: String(ci.bikes || 0) + " bikes · " + String(ci.docks || 0) + " docks", meta: String(ci.borough || ci.zip || ci.raw.address || "") + (isFinite(ci.lat) && isFinite(ci.lon) ? " · " + ci.lat.toFixed(3) + "," + ci.lon.toFixed(3) : ""), badge: String(ci.docks || 0) + " docks", ago: "", lat: ci.lat, lon: ci.lon })
      }
    } else if (key === "nypd") {
      var n = Y.sortByTimeDesc(searchFiltered(timeFiltered(effectiveService.dataNYPD)))
      for (i = 0; i < n.length && i < 40; i++) {
        var nr = n[i]
        rows.push({ primary: String(nr.subtype || nr.raw.ofns_desc || "NYPD"), secondary: String(nr.raw.pd_desc || ""), meta: String(nr.borough || nr.zip || "") + (nr.raw.addr_pct_cd ? " pct " + nr.raw.addr_pct_cd : ""), badge: String(nr.raw.ky_cd || ""), ago: Y.timeAgo(new Date(nr.ts).toISOString()), lat: nr.lat, lon: nr.lon })
      }
    } else if (key === "air") {
      var ar = searchFiltered(timeFiltered(effectiveService.dataAir))
      for (i = 0; i < ar.length && i < 30; i++) {
        var air = ar[i]
        rows.push({ primary: String(air.raw.site_id || air.id || "Air"), secondary: "AQI " + String(air.aqi || "—") + (air.raw.pollutant ? " · " + air.raw.pollutant : ""), meta: String(air.borough || air.zip || ""), badge: String(air.aqi || "—"), ago: Y.timeAgo(new Date(air.ts).toISOString()), lat: air.lat, lon: air.lon })
      }
    } else if (key === "dob") {
      var d = Y.sortByTimeDesc(searchFiltered(timeFiltered(effectiveService.dataDOB)))
      for (i = 0; i < d.length && i < 30; i++) {
        var dr = d[i]
        rows.push({ primary: String(dr.subtype || dr.raw.job_type || "Permit"), secondary: String(dr.raw.job__ || dr.id || ""), meta: String(dr.borough || dr.zip || ""), badge: String(dr.raw.job_status || ""), ago: Y.timeAgo(new Date(dr.ts).toISOString()), lat: dr.lat, lon: dr.lon })
      }
    } else if (key === "parking") {
      var p = Y.sortByTimeDesc(searchFiltered(timeFiltered(effectiveService.dataParking)))
      for (i = 0; i < p.length && i < 30; i++) {
        var pr = p[i]
        rows.push({ primary: String(pr.subtype || pr.raw.violation_code || "Parking"), secondary: String(pr.raw.issuing_agency || ""), meta: String(pr.borough || pr.zip || ""), badge: "$" + String(pr.raw.fine_amount || pr.raw.amount_due || ""), ago: Y.timeAgo(new Date(pr.ts).toISOString()), lat: pr.lat, lon: pr.lon })
      }
    } else if (key === "lottery") {
      var l = Y.sortByTimeDesc(searchFiltered(timeFiltered(effectiveService.dataLottery)))
      for (i = 0; i < l.length && i < 30; i++) {
        var lr = l[i]
        rows.push({ primary: String(lr.subtype || lr.raw.game || "Lottery"), secondary: "won " + String(lr.amount || lr.raw.winning_amount || ""), meta: String(lr.borough || lr.zip || ""), badge: String(lr.raw.winning_numbers || "").slice(0,12), ago: Y.timeAgo(new Date(lr.ts).toISOString()), lat: lr.lat, lon: lr.lon })
      }
    } else if (key === "disp") {
      var dr2 = searchFiltered(effectiveService.dataDisp.filter(pass))
      for (i = 0; i < dr2.length && i < 80; i++) {
        var dsp = dr2[i]
        var mi = (isFinite(dsp.lat) && isFinite(dsp.lon)) ? Y.haversineMiles(root.mLat, root.mLon, dsp.lat, dsp.lon) : NaN
        rows.push({ primary: String(dsp.dba || ""), secondary: String(dsp.city || "") + ", " + String(dsp.state || ""), meta: String(dsp.address || ""), badge: (isFinite(mi) ? mi.toFixed(1) + " mi" : String(dsp.status || "")), ago: "", lat: dsp.lat, lon: dsp.lon })
      }
      rows.sort(function(a, b){ return a.badge.indexOf("mi") !== -1 && b.badge.indexOf("mi") !== -1 ? parseFloat(a.badge) - parseFloat(b.badge) : 0 })
      if (rows.length > 40) rows = rows.slice(0,40)
    }
    return rows
  }
  function detailTitle(key) {
    var m = { "311": "City 311 Complaints", "subway": "MTA Subway Status", "citi": "Citi Bike Availability", "nypd": "NYPD Complaints", "air": "Air Quality", "dob": "DOB Permits", "parking": "Parking Violations", "lottery": "Lottery Winners", "disp": "Cannabis Dispensaries" }
    return m[key] || key
  }
  function openDetail(key) { root.dashKey = key; root.dashMode = "detail"; root.detailQuery = ""; console.log("yerrr Dash: openDetail key=" + key) }
  function backOverview() { root.dashMode = "overview"; root.dashKey = ""; console.log("yerrr Dash: backOverview") }

  Connections {
    target: root.ready ? root.effectiveService : null
    function onDashRequestChanged() {
      if (!root.effectiveService || !root.effectiveService.dashRequest) return
      var k = root.effectiveService.dashRequest
      root.effectiveService.dashRequest = ""
      console.log("yerrr Dash: request key=" + k)
      if (root.dashVisible) root.openDetail(k)
      else root.pendingKey = k
    }
  }

  onDashVisibleChanged: {
    if (root.effectiveService && root.effectiveService.dashVisible) {
      root.dashMode = "overview"
      root.dashKey = ""
      root.detailQuery = ""
      if (root.pendingKey !== "") { root.openDetail(root.pendingKey); root.pendingKey = "" }
    }
  }

  Component.onCompleted: console.log("yerrr Dash: completed shell=" + !!shell + " service=" + !!service + " effective=" + !!effectiveService)

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
      onClicked: { if (effectiveService && effectiveService.toggleDash) effectiveService.toggleDash() }
    }

    // Main dash card
    Rectangle {
      id: dashCard
      width: Math.min(parent.width * 0.92, 1220)
      height: Math.min(parent.height * 0.9, 820)
      anchors.centerIn: parent
      radius: 22
      color: Util.alpha(Color.background, 0.96)
      border.width: 1
      border.color: Util.alpha(Color.foreground, 0.14)
      layer.enabled: true

      MouseArea { anchors.fill: parent; onClicked: {} } // block click-through

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // ============ HEADER (back / pills / voice / refresh / close) ============
        RowLayout {
          Layout.fillWidth: true
          spacing: 10

          // Back (detail only) or wavy logo (overview)
          Item { Layout.preferredWidth: root.dashMode === "detail" ? 132 : 84; Layout.preferredHeight: 30
            MouseArea { anchors.fill: parent; visible: root.dashMode === "overview"; onClicked: { if (effectiveService) effectiveService.toggleVoice() } }
            Comp.WavySprite { anchors.fill: parent; visible: root.dashMode === "overview"; capturing: root.capturing; text: "YERRR"; fontSize: 16; baseColor: root.capturing ? Color.urgent : Color.accent }
            Rectangle { anchors.fill: parent; visible: root.dashMode === "detail"; radius: 14
              color: Util.alpha(Color.foreground, 0.06); border.width: 1; border.color: Util.alpha(Color.foreground, 0.1)
              Text { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; text: "← " + root.detailTitle(root.dashKey); color: Color.foreground; font.family: Style.font.family; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.backOverview() }
            }
          }

          // Borough pills - scrollable
          Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            contentWidth: pillsRow.width
            contentHeight: 28
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            Row {
              id: pillsRow
              spacing: 6
              height: 28
              Repeater {
                model: ["All","Manhattan","Brooklyn","Queens","Bronx","Staten Island"]
                delegate: Rectangle {
                  required property string modelData
                  height: 28; width: pillTxt.implicitWidth + 16; radius: 14
                  color: (ready && (filters.borough === modelData)) ? Util.alpha(Color.accent, 0.18) : Util.alpha(Color.foreground, 0.06)
                  border.width: 1
                  border.color: (ready && (filters.borough === modelData)) ? Util.alpha(Color.accent, 0.32) : Util.alpha(Color.foreground, 0.08)
                  Text { id: pillTxt; anchors.centerIn: parent; text: modelData === "All" ? "All" : Y.boroughAbbr(modelData); font.family: Style.font.family; font.pixelSize: 11; font.bold: (ready && (filters.borough === modelData)); color: (ready && (filters.borough === modelData)) ? Color.accent : Color.foreground }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (effectiveService) { var f=effectiveService.filters; effectiveService.filters = { borough: modelData, zip: f.zip, hours: f.hours, kinds: f.kinds } } } }
                }
              }
            }
          }

          Text {
            visible: ready && filters.zip !== ""
            text: ready ? "ZIP " + filters.zip : ""
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
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (effectiveService) effectiveService.toggleVoice() } }
          }

          // Refresh
          Rectangle {
            width: 34; height: 28; radius: 14
            color: Util.alpha(Color.foreground, 0.06); border.width: 1; border.color: Util.alpha(Color.foreground, 0.08)
            Text { anchors.centerIn: parent; text: ""; font.pixelSize: 12; color: Color.foreground }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (effectiveService) effectiveService.refreshAll() } }
          }

          // Close
          Rectangle {
            width: 32; height: 28; radius: 14
            color: Util.alpha(Color.foreground, 0.06); border.width: 1; border.color: Util.alpha(Color.foreground, 0.08)
            Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 12; color: Color.foreground }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (effectiveService) effectiveService.toggleDash(); root.backOverview() } }
          }
        }

        // Cross summary + time filter + location
        RowLayout {
          Layout.fillWidth: true
          spacing: 8
          Text {
            Layout.fillWidth: true
            text: ready ? effectiveService.crossSummary : "Loading NYC…"
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
                color: (ready && filters.hours === modelData) ? Util.alpha(Color.accent, 0.14) : Util.alpha(Color.foreground, 0.06)
                border.width: 1; border.color: (ready && filters.hours === modelData) ? Util.alpha(Color.accent, 0.28) : Util.alpha(Color.foreground, 0.08)
                Text { anchors.centerIn: parent; text: modelData === 24 ? "24h" : "7d"; font.family: Style.font.family; font.pixelSize: 10; color: (ready && filters.hours === modelData) ? Color.accent : Color.foreground }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (effectiveService) { var f=effectiveService.filters; effectiveService.filters={ borough:f.borough, zip:f.zip, hours:modelData, kinds:f.kinds } } } }
              }
            }
          }
          Text {
            text: ready ? (effectiveService.locationSource !== "none" ? ("📍 " + (filters.zip || effectiveService.borough || "loc") + (isFinite(effectiveService.accuracy) ? " ±" + Math.round(effectiveService.accuracy) + "m" : "")) : "locating…") : ""
            color: Util.alpha(Color.foreground, 0.5); font.family: Style.font.family; font.pixelSize: 10
          }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, 0.08) }

        // ============ CONTENT ============
        // Overview: map + local-update chips + tiles
        // Detail: dataset rows
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          Loader {
            id: contentLoader
            anchors.fill: parent
            visible: root.dashMode === "overview"
            sourceComponent: overviewComp
          }
          Loader {
            id: detailLoader
            anchors.fill: parent
            visible: root.dashMode === "detail"
            sourceComponent: detailComp
          }
        }

        // ============ TERMINAL ============
        Rectangle {
          Layout.fillWidth: true
          height: 84
          radius: 12
          color: Util.alpha(Color.background, 0.96)
          border.width: 1; border.color: Util.alpha(Color.accent, 0.14)
          Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6
            Text {
              width: parent.width
              text: ready ? String(effectiveService.terminalOutput).slice(0, 220) : "yerrr ready"
              color: Util.alpha(Color.accent, 0.95)
              font.family: "monospace"
              font.pixelSize: 11
              elide: Text.ElideRight
            }
            RowLayout {
              width: parent.width
              spacing: 8
              Text { text: "❯"; color: Color.accent; font.family: "monospace"; font.pixelSize: 13; Layout.alignment: Qt.AlignVCenter }
              TextInput {
                id: termInput
                Layout.fillWidth: true
                text: ready ? effectiveService.terminalText : ""
                color: "#e0faff"
                font.family: "monospace"
                font.pixelSize: 12
                clip: true
                focus: root.dashVisible
                onTextChanged: { if (effectiveService) effectiveService.terminalText = text }
                Keys.onReturnPressed: { if (effectiveService) effectiveService.handleTerminalSubmit(text); termInput.text = "" }
                Keys.onEnterPressed: { if (effectiveService) effectiveService.handleTerminalSubmit(text); termInput.text = "" }
                Keys.onEscapePressed: { if (effectiveService) effectiveService.toggleDash(); root.backOverview() }
              }
              Rectangle {
                width: 28; height: 22; radius: 6
                color: Util.alpha(Color.accent, 0.14); border.width: 1; border.color: Util.alpha(Color.accent, 0.22)
                Text { anchors.centerIn: parent; text: "↵"; color: Color.accent; font.pixelSize: 10 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (effectiveService) effectiveService.handleTerminalSubmit(termInput.text); termInput.text = "" } }
              }
            }
            Text {
              text: "try:  \"bk 311 24h\"  \"queens subway\"  \"11211 citi\"  \"disp near\"  \"clear\"  \"refresh\""
              color: Util.alpha(Color.accent, 0.45)
              font.family: "monospace"
              font.pixelSize: 9
            }
          }
        }
      }
    }
  }

  // ================= OVERVIEW =================
  Component {
    id: overviewComp
    ColumnLayout {
      anchors.fill: parent
      spacing: 10

      // Local updates strip (clickable chips) - scrollable
      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Flickable {
          Layout.fillWidth: true
          Layout.preferredHeight: 44
          contentWidth: chipsRow.width
          contentHeight: 44
          clip: true
          flickableDirection: Flickable.HorizontalFlick
          boundsBehavior: Flickable.StopAtBounds
          Row {
            id: chipsRow
            spacing: 8
            height: 44
            Comp.Chip { text: "311"; value: root.ready ? String(Y.filterByTime(root.effectiveService.data311, root.filters.hours).filter(function(r){ return root.filters.borough==="All" || String(r.borough||"").toUpperCase()===root.filters.borough.toUpperCase() }).length) + " in " + root.filters.hours + "h" : "—"; onClicked: root.openDetail("311") }
            Comp.Chip {
              text: "Subway"
              value: root.ready ? (function(){ var d=0, rows=[]; for (var i=0;i<root.effectiveService.dataSubway.length;i++){ var s=root.effectiveService.dataSubway[i]; if(String(s.status||"").toLowerCase().indexOf("del")!==-1) d++; rows.push(String(s.subtype||"").slice(0,3)) } return d ? d + " delayed · " + rows.join(" ") : (rows.join(" ") || "on time") })() : "—"
              onClicked: root.openDetail("subway")
            }
            Comp.Chip {
              text: "Citi"
              value: root.ready ? String(root.effectiveService.dataCiti.length) + " stations · " + (Y.filterByTime(root.effectiveService.dataCiti, root.filters.hours)[0] ? Y.filterByTime(root.effectiveService.dataCiti, root.filters.hours)[0].bikes + " bikes" : "—") : "—"
              onClicked: root.openDetail("citi")
            }
            Comp.Chip {
              text: "Pot Head"
              value: root.ready ? (function(){ var near = Y.nearestDispensaries(root.effectiveService.dataDisp, root.mLat, root.mLon, 1); return near.length ? (String(near[0].rec.dba || "").slice(0, 22) + " · " + near[0].miles.toFixed(1) + "mi") : ("0 fit filter · " + root.effectiveService.dataDisp.length + " NY") })() : "—"
              onClicked: root.openDetail("disp")
            }
            Comp.Chip { text: "Lottery"; value: root.ready ? Y.filterByTime(root.effectiveService.dataLottery, root.filters.hours).length + " winners" : "—"; onClicked: root.openDetail("lottery") }
          }
        }
        Text { text: "tap a card →"; color: Util.alpha(Color.foreground, 0.4); font.family: Style.font.family; font.pixelSize: 10; Layout.alignment: Qt.AlignVCenter }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12

        // Map - interactive with pins
        Rectangle {
          Layout.preferredWidth: 400
          Layout.fillHeight: true
          radius: 14
          clip: true
          color: Util.alpha(Color.background, 0.97)
          border.width: 1; border.color: Util.alpha(Color.accent, 0.16)

          // OSM tiles 3x3 centered on location - interactive
          Item {
            id: map
            anchors.fill: parent
            clip: true
            property double panLat: root.mLat
            property double panLon: root.mLon
            property int panZoom: root.mapZoom
            readonly property var t0: Y.tileXY(panLat, panLon, panZoom)
            readonly property double cx: width / 2
            readonly property double cy: height / 2
            onPanZoomChanged: if (root.ready && root.effectiveService && root.effectiveService.fetchMapTiles) root.effectiveService.fetchMapTiles(map.panZoom)
            // Sync pan to service location when not interacting
            onVisibleChanged: if (visible) { panLat = root.mLat; panLon = root.mLon; panZoom = root.mapZoom }
            Connections { target: root; function onMLatChanged(){ if (!mapMouse.drag.active) map.panLat = root.mLat } function onMLonChanged(){ if (!mapMouse.drag.active) map.panLon = root.mLon } }

            Repeater {
              model: 9
              delegate: Comp.TileImg {
                required property int index
                x: map.cx - 128 - map.t0.fx * 256 + ((index % 3) - 1) * 256
                y: map.cy - 128 - map.t0.fy * 256 + (Math.floor(index / 3) - 1) * 256
                txx: map.t0.tx + (index % 3) - 1
                tyy: map.t0.ty + Math.floor(index / 3) - 1
                zz: map.panZoom
                src: root.ready ? ("file:///" + root.effectiveService.mapTileDir + "/" + map.panZoom + "/" + (map.t0.tx + (index % 3) - 1) + "_" + (map.t0.ty + Math.floor(index / 3) - 1) + ".png") : ""
              }
            }

            // Drag to pan (behind pins)
            MouseArea {
              id: mapMouse
              anchors.fill: parent
              z: 0
              drag.target: null
              property point lastPos
              onPressed: function(mouse){ lastPos = Qt.point(mouse.x, mouse.y) }
              onPositionChanged: function(mouse){
                if (!pressed) return
                var dx = mouse.x - lastPos.x
                var dy = mouse.y - lastPos.y
                var degPerPx = 360 / (Math.pow(2, map.panZoom) * 256)
                var latScale = Math.cos(map.panLat * Math.PI / 180)
                if (latScale < 0.1) latScale = 0.1
                map.panLon -= dx * degPerPx
                map.panLat += dy * degPerPx / latScale
                if (map.panLat < 40.49) map.panLat = 40.49
                if (map.panLat > 40.92) map.panLat = 40.92
                if (map.panLon < -74.26) map.panLon = -74.26
                if (map.panLon > -73.68) map.panLon = -73.68
                lastPos = Qt.point(mouse.x, mouse.y)
              }
              onWheel: function(wheel){
                var delta = wheel.angleDelta.y > 0 ? 1 : -1
                var nz = Math.max(10, Math.min(16, map.panZoom + delta))
                if (nz !== map.panZoom) map.panZoom = nz
                wheel.accepted = true
              }
            }

            // Pins for events - filtered by current borough/zip/hours, clickable to pan
            Repeater {
              model: root.ready ? (function(){
                var bor = root.filters.borough, zip = root.filters.zip, h = root.filters.hours
                function pass(r){ if (bor!=="All" && String(r.borough||"").toUpperCase()!==bor.toUpperCase()) return false; if (zip && String(r.zip||"").trim()!==String(zip).trim()) return false; return true }
                var a = Y.filterByTime(root.effectiveService.data311, h).filter(pass).filter(function(r){ return isFinite(r.lat) && isFinite(r.lon) })
                if (a.length===0) a = root.effectiveService.data311.filter(pass).filter(function(r){ return isFinite(r.lat) && isFinite(r.lon) })
                return a.slice(0,20)
              })() : []
              delegate: Rectangle {
                required property var modelData
                property var pt: Y.tileXY(modelData.lat, modelData.lon, map.panZoom)
                x: map.cx + (pt.tx - map.t0.tx)*256 + (pt.fx - map.t0.fx)*256 - 6
                y: map.cy + (pt.ty - map.t0.ty)*256 + (pt.fy - map.t0.fy)*256 - 6
                width: 12; height: 12; radius: 6
                z: 10
                color: Util.alpha(Color.urgent, 0.9); border.width: 1.5; border.color: Color.background
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -4
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { map.panLat = modelData.lat; map.panLon = modelData.lon; map.panZoom = 14; root.openDetail("311"); root.detailQuery = modelData.zip || modelData.borough }
                  onEntered: parent.scale = 1.5
                  onExited: parent.scale = 1.0
                }
              }
            }
            Repeater {
              model: root.ready ? (function(){
                var bor = root.filters.borough, zip = root.filters.zip
                function pass(r){ if (bor!=="All" && String(r.borough||"").toUpperCase()!==bor.toUpperCase()) return false; if (zip && String(r.zip||"").trim()!==String(zip).trim()) return false; return true }
                return root.effectiveService.dataCiti.filter(function(r){ return isFinite(r.lat) && isFinite(r.lon) }).filter(pass).slice(0,15)
              })() : []
              delegate: Rectangle {
                required property var modelData
                property var pt: Y.tileXY(modelData.lat, modelData.lon, map.panZoom)
                x: map.cx + (pt.tx - map.t0.tx)*256 + (pt.fx - map.t0.fx)*256 - 7
                y: map.cy + (pt.ty - map.t0.ty)*256 + (pt.fy - map.t0.fy)*256 - 7
                width: 14; height: 14; radius: 7
                z: 10
                color: "#3b82f6"; border.width: 1.5; border.color: Color.background
                Text { anchors.centerIn: parent; text: "🚲"; font.pixelSize: 8 }
                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: { map.panLat = modelData.lat; map.panLon = modelData.lon; map.panZoom = 15; root.openDetail("citi") } }
              }
            }
            Repeater {
              model: root.ready ? (function(){
                var bor = root.filters.borough, zip = root.filters.zip
                function pass(r){ if (bor!=="All" && String(r.borough||"").toUpperCase()!==bor.toUpperCase()) return false; if (zip && String(r.zip||"").trim()!==String(zip).trim()) return false; return true }
                return root.effectiveService.dataDisp.filter(function(r){ return isFinite(r.lat) && isFinite(r.lon) }).filter(pass).slice(0,12)
              })() : []
              delegate: Rectangle {
                required property var modelData
                property var pt: Y.tileXY(modelData.lat, modelData.lon, map.panZoom)
                x: map.cx + (pt.tx - map.t0.tx)*256 + (pt.fx - map.t0.fx)*256 - 8
                y: map.cy + (pt.ty - map.t0.ty)*256 + (pt.fy - map.t0.fy)*256 - 8
                width: 16; height: 16; radius: 8
                z: 10
                color: "#22c55e"; border.width: 1.5; border.color: Color.background
                Text { anchors.centerIn: parent; text: "🌿"; font.pixelSize: 9 }
                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: { map.panLat = modelData.lat; map.panLon = modelData.lon; map.panZoom = 15; root.openDetail("disp") } }
              }
            }

            // Location marker (center) - above pins
            Rectangle {
              x: map.cx - 10; y: map.cy - 10; width: 20; height: 20; radius: 10
              z: 11
              color: Color.accent; border.width: 2; border.color: Color.background
              Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Color.background }
              Text {
                anchors.bottom: parent.top; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: 4
                text: root.ready && root.filters.zip !== "" ? "ZIP " + root.filters.zip : (root.ready && root.effectiveService.borough ? root.effectiveService.borough : "YOU")
                color: Color.foreground; font.family: Style.font.family; font.pixelSize: 10; font.bold: true
                style: Text.Outline; styleColor: Util.alpha(Color.background, 0.85)
              }
            }
          }

          // Zoom controls + label
          Column {
            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8
            spacing: 4
            Row { spacing: 4
              Rectangle { width: 24; height: 24; radius: 6; color: Util.alpha(Color.foreground, 0.12); border.width: 1; border.color: Util.alpha(Color.foreground, 0.18); Text { anchors.centerIn: parent; text: "+"; color: Color.foreground; font.pixelSize: 14; font.bold: true } MouseArea { anchors.fill: parent; onClicked: map.panZoom = Math.min(16, map.panZoom+1) } }
              Rectangle { width: 24; height: 24; radius: 6; color: Util.alpha(Color.foreground, 0.12); border.width: 1; border.color: Util.alpha(Color.foreground, 0.18); Text { anchors.centerIn: parent; text: "−"; color: Color.foreground; font.pixelSize: 14; font.bold: true } MouseArea { anchors.fill: parent; onClicked: map.panZoom = Math.max(10, map.panZoom-1) } }
              Rectangle { width: 28; height: 24; radius: 6; color: Util.alpha(Color.foreground, 0.08); border.width: 1; border.color: Util.alpha(Color.foreground, 0.12); Text { anchors.centerIn: parent; text: "⌖"; color: Color.foreground; font.pixelSize: 12 } MouseArea { anchors.fill: parent; onClicked: { map.panLat = root.mLat; map.panLon = root.mLon; map.panZoom = root.mapZoom } } }
              Rectangle { width: 46; height: 24; radius: 6; color: Util.alpha(Color.accent, 0.18); border.width: 1; border.color: Util.alpha(Color.accent, 0.32); Text { anchors.centerIn: parent; text: "📍 Set"; color: Color.accent; font.pixelSize: 10; font.bold: true } MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.effectiveService && root.effectiveService.setLocation) root.effectiveService.setLocation(map.panLat, map.panLon, "map"); map.panLat = map.panLat; map.panLon = map.panLon } } }
            }
            Text {
              text: "OSM z" + map.panZoom + " · " + map.panLat.toFixed(4) + ", " + map.panLon.toFixed(4) + (root.effectiveService && root.effectiveService.locationOverridden ? " • 📍 custom" : "")
              color: Util.alpha(Color.accent, 0.85); font.family: "monospace"; font.pixelSize: 9
              style: Text.Outline; styleColor: Util.alpha(Color.background, 0.85)
            }
          }
          Text {
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 8
            text: "drag to pan • scroll to zoom • pins: 311 red, Citi blue, Disp green • Set 📍 to move data"
            color: Util.alpha(Color.foreground, 0.45); font.family: Style.font.family; font.pixelSize: 8
          }
        }

        // Dataset tiles grid
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 10

          // Left/right tiles: 311 + Subway wide cards on top
          RowLayout { Layout.fillWidth: true; spacing: 10
            Comp.TileWide { Layout.fillWidth: true; title: "311"; count: root.ready ? String(Y.filterByTime(root.effectiveService.data311, root.filters.hours).length) + " in " + root.filters.hours + "h" : "—"; subtitle: root.ready ? (Y.topComplaintTypes(root.effectiveService.data311, 1)[0] ? Y.topComplaintTypes(root.effectiveService.data311, 1)[0].type : "no complaints") : ""; onClicked: root.openDetail("311") }
            Comp.TileWide { Layout.fillWidth: true; title: "Subway"; count: root.ready ? root.effectiveService.dataSubway.length + " lines" : "—"; subtitle: root.ready ? (function(){ var d=0; for (var i=0;i<root.effectiveService.dataSubway.length;i++) if(String(root.effectiveService.dataSubway[i].status||"").toLowerCase().indexOf("del")!==-1) d++; return d ? d + " delayed" : "Good service" })() : ""; onClicked: root.openDetail("subway") }
          }

          GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 8
            rowSpacing: 8

            Comp.Tile { Layout.fillWidth: true; Layout.preferredHeight: 64; title: "Citi"; value: root.ready ? root.effectiveService.dataCiti.length + " stations" : "—"; sub: root.ready ? (root.effectiveService.dataCiti[0] ? String(root.effectiveService.dataCiti[0].name||root.effectiveService.dataCiti[0].id||"").slice(0,16) + " · " + root.effectiveService.dataCiti[0].bikes + "🚲" : "—") : ""; onClicked: root.openDetail("citi") }
            Comp.Tile { Layout.fillWidth: true; Layout.preferredHeight: 64; title: "NYPD"; value: root.ready ? root.effectiveService.dataNYPD.length + " complaints" : "—"; sub: root.ready ? (Y.topComplaintTypes(root.effectiveService.dataNYPD, 1)[0] ? Y.topComplaintTypes(root.effectiveService.dataNYPD, 1)[0].type.slice(0,16) : "—") : ""; onClicked: root.openDetail("nypd") }
            Comp.Tile { Layout.fillWidth: true; Layout.preferredHeight: 64; title: "Air"; value: root.ready ? root.effectiveService.dataAir.length + " sites" : "—"; sub: root.ready ? (root.effectiveService.dataAir[0] ? "AQI " + String(root.effectiveService.dataAir[0].aqi || "") : "—") : ""; onClicked: root.openDetail("air") }
            Comp.Tile { Layout.fillWidth: true; Layout.preferredHeight: 64; title: "DOB"; value: root.ready ? root.effectiveService.dataDOB.length + " permits" : "—"; sub: root.ready ? (root.effectiveService.dataDOB[0] ? String(root.effectiveService.dataDOB[0].subtype || "").slice(0, 16) : "—") : ""; onClicked: root.openDetail("dob") }
            Comp.Tile { Layout.fillWidth: true; Layout.preferredHeight: 64; title: "Parking"; value: root.ready ? root.effectiveService.dataParking.length + " tickets" : "—"; sub: root.ready ? (root.effectiveService.dataParking[0] ? String(root.effectiveService.dataParking[0].subtype || "").slice(0, 16) : "—") : ""; onClicked: root.openDetail("parking") }
            Comp.Tile { Layout.fillWidth: true; Layout.preferredHeight: 64; title: "Dispensaries"; value: root.ready ? root.effectiveService.dataDisp.length + " retail" : "—"; sub: root.ready ? (function(){ var near=Y.nearestDispensaries(root.effectiveService.dataDisp, root.mLat, root.mLon, 1); return near.length ? String(near[0].rec.dba||"").slice(0,14) + " · " + near[0].miles.toFixed(1) + "mi" : String(root.effectiveService.dataDisp[0].dba||"").slice(0,14) })() : "—"; onClicked: root.openDetail("disp") }
            // Lottery as compact chip - shows most recent Powerball numbers
            Rectangle {
              Layout.fillWidth: true; Layout.preferredHeight: 36; radius: 10
              color: Util.alpha(Color.foreground, 0.04); border.width: 1; border.color: Util.alpha(Color.foreground, 0.07)
              Row { anchors.centerIn: parent; spacing: 6
                Text { text: "🎟 Powerball"; color: Util.alpha(Color.foreground, 0.6); font.family: Style.font.family; font.pixelSize: 9; font.bold: true }
                Text { text: root.ready && root.effectiveService.dataLottery.length ? (function(){ var r=root.effectiveService.dataLottery[0]; var nums=String(r.raw.winning_numbers||r.raw.winning_numbers||"").trim(); return nums ? nums.slice(0,20) + " • " + Y.timeAgo(new Date(r.ts).toISOString()) : r.subtype })() : "—"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 10; font.bold: true; elide: Text.ElideRight; width: 140; horizontalAlignment: Text.AlignHCenter }
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onEntered: parent.border.color = Util.alpha(Color.accent, 0.55); onExited: parent.border.color = Util.alpha(Color.foreground, 0.07); onClicked: root.openDetail("lottery") }
            }
          }

          Item { Layout.fillHeight: true; Layout.fillWidth: true }
        }
      }

      Text {
        Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
        text: "NYC Open Data (Socrata) · MTA GTFS · Citi GBFS · NY Lottery · NY OCM — cross-ref by ZIP / borough / time"
        color: Util.alpha(Color.foreground, 0.3); font.family: Style.font.family; font.pixelSize: 9; wrapMode: Text.Wrap
      }
    }
  }

  // ================= DETAIL =================
  Component {
    id: detailComp
    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          Layout.fillWidth: true
          text: root.detailTitle(root.dashKey)
          color: Color.foreground; font.family: Style.font.family; font.pixelSize: 15; font.bold: true
          elide: Text.ElideRight
          Layout.maximumWidth: 480
        }
        Rectangle {
          height: 20; width: subtxt.implicitWidth + 10; radius: 10
          color: Util.alpha(Color.accent, 0.12); border.width: 1; border.color: Util.alpha(Color.accent, 0.22)
          Text { id: subtxt; anchors.centerIn: parent; text: root.detailRows(root.dashKey).length + " shown"; color: Color.accent; font.family: Style.font.family; font.pixelSize: 10 }
        }
        Item { Layout.fillWidth: true }
        Rectangle {
          width: 120; height: 24; radius: 12
          color: Util.alpha(Color.foreground, 0.05); border.width: 1; border.color: Util.alpha(Color.accent, 0.25)
          TextInput {
            id: searchInput
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 20
            verticalAlignment: TextInput.AlignVCenter
            text: root.detailQuery
            color: Color.foreground; font.family: Style.font.family; font.pixelSize: 10
            onTextChanged: root.detailQuery = text
            Keys.onEscapePressed: root.detailQuery = ""
          }
          Text {
            anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
            visible: root.detailQuery !== ""
            text: "✕"; color: Util.alpha(Color.foreground, 0.5); font.pixelSize: 10
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.detailQuery = "" }
          }
        }
      }

      Rectangle { Layout.fillWidth: true; height: 1; color: Util.alpha(Color.foreground, 0.08) }

      ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 6
        model: root.detailRows(root.dashKey)
        delegate: Item {
          required property var modelData
          width: ListView.view.width - 4
          height: 48
          Rectangle { id: bg; anchors.fill: parent; radius: 10; color: Util.alpha(Color.foreground, 0.04); border.width: 1; border.color: Util.alpha(Color.foreground, 0.07) }
          Row {
            anchors.fill: parent; anchors.margins: 8; spacing: 10
            Rectangle {
              width: 46; height: 20; radius: 8; anchors.verticalCenter: parent.verticalCenter
              color: String(modelData.badge || "").toLowerCase().indexOf("del") !== -1 ? Util.alpha(Color.urgent, 0.16) : Util.alpha(Color.accent, 0.12)
              border.width: 1; border.color: String(modelData.badge || "").toLowerCase().indexOf("del") !== -1 ? Util.alpha(Color.urgent, 0.28) : Util.alpha(Color.accent, 0.2)
              Text { anchors.centerIn: parent; text: String(modelData.badge || "").slice(0, 12); color: String(modelData.badge || "").toLowerCase().indexOf("del") !== -1 ? Color.urgent : Color.accent; font.family: Style.font.family; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight; width: 40; horizontalAlignment: Text.AlignHCenter }
            }
            Column { anchors.verticalCenter: parent.verticalCenter; spacing: 1; width: parent.width - 56
              Text { text: String(modelData.primary || ""); color: Color.foreground; font.family: Style.font.family; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight; width: parent.width }
              Text { text: (String(modelData.secondary || "") + (modelData.meta ? "  ·  " + modelData.meta : "")).slice(0, 140); color: Util.alpha(Color.foreground, 0.55); font.family: Style.font.family; font.pixelSize: 10; elide: Text.ElideRight; width: parent.width }
            }
            Text { text: modelData.ago || ""; color: Util.alpha(Color.foreground, 0.4); font.family: Style.font.family; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: bg.border.color = Util.alpha(Color.accent, 0.35)
            onExited: bg.border.color = Util.alpha(Color.foreground, 0.07)
            onClicked: {
              if (isFinite(modelData.lat) && isFinite(modelData.lon)) {
                // Pan map to this location and show in overview
                map.panLat = modelData.lat
                map.panLon = modelData.lon
                map.panZoom = Math.max(map.panZoom, 14)
                console.log("yerrr: detail click pan to " + modelData.lat + "," + modelData.lon)
              } else {
                console.log("yerrr: detail click " + modelData.primary)
              }
            }
          }
        }
      }
      Text {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.detailRows(root.dashKey).length === 0
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        text: root.ready ? (root.detailQuery !== "" ? "No matches for “" + root.detailQuery + "” in " + root.detailTitle(root.dashKey) : root.detailTitle(root.dashKey) + " is still loading — refresh (⭮) or wait for the next update cycle") : "Connectivity loading…"
        color: Util.alpha(Color.foreground, 0.5); font.family: Style.font.family; font.pixelSize: 11
      }
      Text {
        Layout.fillWidth: true
        text: root.detailQuery !== "" ? "\"" + root.detailQuery + "\" — clear with ✕ or Esc. Full filters: header pills + “❯” terminal e.g. \"queens subway\", \"11249 disp\"" : "Search filters in the box in real time — or use “❯” terminal e.g. \"queens subway\", \"11249 disp\""
        color: Util.alpha(Color.foreground, 0.4); font.family: Style.font.family; font.pixelSize: 9
      }
    }
  }
}