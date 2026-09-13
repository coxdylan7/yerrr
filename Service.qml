import QtQuick
import Quickshell
import Quickshell.Io
import "Yerrr.js" as Y

Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "djc.yerrr"
  readonly property var pluginEntry: Y.pluginEntry(shell && shell.shellConfig ? shell : (fileConfig ? { shellConfig: fileConfig } : null), pluginId)

  // Config
  readonly property string locationOverrideLat: Y.configStr(pluginEntry, "locationOverrideLat", "")
  readonly property string locationOverrideLon: Y.configStr(pluginEntry, "locationOverrideLon", "")
  readonly property string appToken: Y.configStr(pluginEntry, "appToken", "")
  readonly property int max311: Y.configInt(pluginEntry, "max311", 200)
  readonly property int maxNYPD: Y.configInt(pluginEntry, "maxNYPD", 200)

  readonly property string homeDir: Quickshell.env("HOME") || "~"
  readonly property string cacheDir: homeDir + "/.cache/omarchy/yerrr"
  readonly property string cache311: cacheDir + "/311.json"
  readonly property string cacheSubway: cacheDir + "/subway.json"
  readonly property string cacheCiti: cacheDir + "/citi.json"
  readonly property string cacheNYPD: cacheDir + "/nypd.json"
  readonly property string cacheAir: cacheDir + "/air.json"
  readonly property string cacheDOB: cacheDir + "/dob.json"
  readonly property string cacheParking: cacheDir + "/parking.json"
  readonly property string cacheLottery: cacheDir + "/lottery.json"
  readonly property string cacheDisp: cacheDir + "/dispensaries.json"
  readonly property string mapTileDir: cacheDir + "/tiles"
  readonly property string locationCache: cacheDir + "/location.json"
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string voxtypeStateFile: runtimeDir + "/voxtype/state"

  // Helper paths — argv-based, no shell
  readonly property string helperLocation: { var u=Qt.resolvedUrl("./helpers/fetch-yerrr-location.py"); var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helper311:     { var u=Qt.resolvedUrl("./helpers/fetch-311.py");           var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helperSubway:  { var u=Qt.resolvedUrl("./helpers/fetch-mta.py");            var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helperCiti:    { var u=Qt.resolvedUrl("./helpers/fetch-citi.py");           var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helperNYPD:    { var u=Qt.resolvedUrl("./helpers/fetch-nypd.py");           var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helperAir:     { var u=Qt.resolvedUrl("./helpers/fetch-air.py");            var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helperDOB:     { var u=Qt.resolvedUrl("./helpers/fetch-dob.py");            var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helperParking: { var u=Qt.resolvedUrl("./helpers/fetch-parking.py");        var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helperLottery: { var u=Qt.resolvedUrl("./helpers/fetch-lottery.py");        var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helperDisp:  { var u=Qt.resolvedUrl("./helpers/fetch-dispensaries.py"); var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }
  readonly property string helperTiles: { var u=Qt.resolvedUrl("./helpers/fetch-map-tiles.py");      var s=String(u); if(s.indexOf("file://")===0) s=s.slice(7); return s }

  FileView {
    id: shellConfigFile
    path: homeDir + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
  }
  property var fileConfig: {
    try { var t=shellConfigFile.text(); return t ? JSON.parse(t) : null } catch(e){ return null }
  }
  readonly property var effectiveShell: shell && shell.shellConfig ? shell : (fileConfig ? { shellConfig: fileConfig } : null)

  // Location state (reuse pot-head logic)
  property double lat: NaN
  property double lon: NaN
  property double accuracy: NaN
  property string locationSource: "none"
  property string locationError: ""
  property string borough: "All"
  property string zip: ""

  function effectiveLat() {
    var ov = Y.configFloat(pluginEntry, "locationOverrideLat", NaN)
    if (isFinite(ov)) return ov
    var s = Y.configStr(pluginEntry, "locationOverrideLat", "")
    var n = Number(s)
    if (s!=="" && isFinite(n)) return n
    if (!isFinite(lat) || !isFinite(lon)) return 40.7128
    // Clamp Hawthorne/outside NYC to NYC bbox so map/data correlate
    if (lat < 40.49 || lat > 40.92 || lon < -74.26 || lon > -73.68) return 40.7128
    return lat
  }
  function effectiveLon() {
    var ov = Y.configFloat(pluginEntry, "locationOverrideLon", NaN)
    if (isFinite(ov)) return ov
    var s = Y.configStr(pluginEntry, "locationOverrideLon", "")
    var n = Number(s)
    if (s!=="" && isFinite(n)) return n
    if (!isFinite(lat) || !isFinite(lon)) return -74.0060
    if (lat < 40.49 || lat > 40.92 || lon < -74.26 || lon > -73.68) return -74.0060
    return lon
  }

  // Dataset state
  property var data311: []
  property var dataSubway: []
  property var dataCiti: []
  property var dataNYPD: []
  property var dataAir: []
  property var dataDOB: []
  property var dataParking: []
  property var dataLottery: []
  property var dataDisp: []
  property string lastError: ""
  property string lastUpdate: ""

  // Dash / voice / terminal
  property bool dashVisible: false
  property string dashRequest: ""
  property string terminalText: ""
  property string terminalOutput: "yerrr ready — type \"bk 311\" or \"yerrr show subway\" — location: locating..."
  property var filters: ({ borough: "All", zip: "", hours: 24, kinds: [] })
  property string voxtypeState: "stopped"
  property bool voxtypeInstalled: false
  property bool voiceBusy: false
  property bool capturing: voxtypeState === "recording" || voxtypeState === "transcribing"

  // Derived cross-ref for QML
  readonly property string boroughFromLocation: {
    var z = String(zip||"").trim()
    if (z) return Y.boroughFromZip(z)
    return String(borough||"All")
  }
  readonly property string crossSummary: {
    // Cheap cross-ref for header: 311 vs subway
    var h = Number(filters.hours||24)
    var f311 = Y.filterByTime(data311, h)
    if (filters.borough!=="All") f311 = Y.filterByBorough(f311, filters.borough)
    if (filters.zip) f311 = Y.filterByZip(f311, filters.zip)
    return Y.crossRef311VsSubway(f311, dataSubway, h)
  }

  function toggleDash() {
    root.dashVisible = !root.dashVisible
    console.log("yerrr: dash " + (root.dashVisible?"open":"close"))
  }
  function setFiltersFromTerminal(txt) {
    var p = Y.terminalParse(txt)
    var cur = root.filters
    var nb = (p.borough !== "All" ? p.borough : cur.borough)
    var nz = (p.zip ? p.zip : cur.zip)
    var nh = (p.hours !== null && p.hours !== undefined ? p.hours : cur.hours)
    var nk = (p.kinds.length ? p.kinds : cur.kinds)
    // If input was "all", kinds already set to all
    root.filters = { borough: nb, zip: nz, hours: nh, kinds: nk }
    root.terminalOutput = "filter → " + JSON.stringify(root.filters) + " — " + root.crossSummary
    console.log("yerrr: terminal parse " + txt + " -> " + JSON.stringify(root.filters))
  }
  function handleTerminalSubmit(txt) {
    root.terminalText = ""
    if (!txt || String(txt).trim().length===0) return
    root.setFiltersFromTerminal(txt)
    // also allow "clear" "refresh"
    var low = String(txt).toLowerCase()
    if (low.indexOf("refresh")!==-1 || low.indexOf("reload")!==-1) {
      root.refreshAll()
      root.terminalOutput += " — refreshing…"
    }
    if (low.indexOf("clear")!==-1) {
      root.filters = ({ borough: "All", zip: "", hours: 24, kinds: [] })
      root.terminalOutput = "filters cleared"
    }
  }

  // Cache dir ensure (absolute)
  function ensureCacheDir() {
    cacheProc.command = ["/usr/bin/mkdir", "-p", cacheDir]
    cacheProc.running = true
  }

  // Location
  function fetchLocation() {
    locationProc.collected = ""
    locationProc.command = ["/usr/bin/python3", helperLocation, locationCache]
    locationProc.running = true
  }
  function handleLocation() {
    var txt = locationProc.collected
    locationProc.collected = ""
    try {
      var m = txt.match(/\{[^}]*"lat"[^}]*\}/)
      if (!m) m = txt.match(/\{[\s\S]*\}/)
      var j = m ? JSON.parse(m[0]) : JSON.parse(txt.trim().split("\n").pop())
      if (j && isFinite(j.lat) && isFinite(j.lon)) {
        lat = Number(j.lat); lon = Number(j.lon); accuracy = Number(j.accuracy||NaN); locationSource = String(j.source||"unknown")
        // Derive zip/borough via simple boroughFromZip if location helper later adds zip; for now keep filters
        // Try reverse zip via helper: if j.zip present, use it
        if (j.zip) { zip = String(j.zip); borough = Y.boroughFromZip(zip) || "All" }
        locationError = ""
        root.terminalOutput = "location " + lat.toFixed(4)+","+lon.toFixed(4) + " via " + locationSource + " — " + root.crossSummary
        console.log("yerrr: location " + lat+","+lon + " via " + locationSource)
      } else {
        locationError = "No fix"
      }
    } catch(e) {
      locationError = String(e).slice(0,80)
    }
  }

  // Generic fetchers — each helper validates args, enforces timeout/byte cap, atomic nofollow write
  function fetch311()    { proc311.collected=""; proc311.command=["/usr/bin/python3", helper311, cache311, String(max311), appToken]; proc311.running=true }
  function fetchSubway() { procSubway.collected=""; procSubway.command=["/usr/bin/python3", helperSubway, cacheSubway]; procSubway.running=true }
  function fetchCiti()   { procCiti.collected=""; procCiti.command=["/usr/bin/python3", helperCiti, cacheCiti]; procCiti.running=true }
  function fetchNYPD()   { procNYPD.collected=""; procNYPD.command=["/usr/bin/python3", helperNYPD, cacheNYPD, String(maxNYPD), appToken]; procNYPD.running=true }
  function fetchAir()    { procAir.collected=""; procAir.command=["/usr/bin/python3", helperAir, cacheAir, "100", appToken]; procAir.running=true }
  function fetchDOB()    { procDOB.collected=""; procDOB.command=["/usr/bin/python3", helperDOB, cacheDOB, "100", appToken]; procDOB.running=true }
  function fetchParking(){ procParking.collected=""; procParking.command=["/usr/bin/python3", helperParking, cacheParking, "100", appToken]; procParking.running=true }
  function fetchLottery(){ procLottery.collected=""; procLottery.command=["/usr/bin/python3", helperLottery, cacheLottery]; procLottery.running=true }
  function fetchDisp()  { procDisp.collected=""; procDisp.command=["/usr/bin/python3", helperDisp, cacheDisp, "300", appToken]; procDisp.running=true }
  function fetchMapTiles() { var lat = isFinite(root.effectiveLat()) ? root.effectiveLat() : 40.7128; var lon = isFinite(root.effectiveLon()) ? root.effectiveLon() : -74.0060; procTiles.collected=""; procTiles.command=["/usr/bin/python3", helperTiles, cacheDir, String(lat), String(lon), "13"]; procTiles.running=true }

  function handleCache(proc, setter, kind) {
    var txt = proc.collected; proc.collected=""
    try {
      var arr = JSON.parse(txt)
      if (!Array.isArray(arr)) arr = [arr]
      if (arr.length > 2000) arr = arr.slice(0,2000)
      var norm = arr
      try {
        if (kind === "311") norm = arr.map(function(r){ return Y.normalize311(r) })
        else if (kind === "subway") norm = arr.map(function(r){ return Y.normalizeSubway(r) })
        else if (kind === "citi") norm = arr.map(function(r){ return Y.normalizeCiti(r) })
        else if (kind === "nypd") norm = arr.map(function(r){ return Y.normalizeNYPD(r) })
        else if (kind === "air") norm = arr.map(function(r){ return Y.normalizeAir(r) })
        else if (kind === "dob") norm = arr.map(function(r){ return Y.normalizeDOB(r) })
        else if (kind === "parking") norm = arr.map(function(r){ return Y.normalizeParking(r) })
        else if (kind === "lottery") norm = arr.map(function(r){ return Y.normalizeLottery(r) })
        else if (kind === "disp") norm = Y.normalizeDispensaries(arr)
      } catch(ne){ console.log("yerrr: normalize " + kind + " err " + ne); norm = arr }
      setter(norm)
      console.log("yerrr: loaded " + kind + " " + norm.length + (norm.length !== arr.length ? " normalized" : ""))
      lastUpdate = new Date().toISOString()
    } catch(e) { console.log("yerrr: " + kind + " parse err " + e) }
  }

  function refreshAll() {
    root.ensureCacheDir()
    root.fetchLocation()
    root.fetch311(); root.fetchSubway(); root.fetchCiti(); root.fetchNYPD(); root.fetchAir(); root.fetchDOB(); root.fetchParking(); root.fetchLottery(); root.fetchDisp(); Qt.callLater(function(){ root.fetchMapTiles() })
  }

  // Voice (reuse tomb-stone pattern, absolute)
  function toggleVoice() {
    if (root.voiceBusy) return
    if (!root.voxtypeInstalled) {
      root.terminalOutput = "Voxtype not installed — run: omarchy voxtype install"
      return
    }
    root.voiceBusy = true
    startDaemonProc.command = ["/usr/bin/systemctl","--user","start","voxtype.service"]
    startDaemonProc.running = true
  }
  function refreshVoxtypeState() {
    var s = String(voxtypeStateView.text()||"").trim()
    if (s.length>0) root.voxtypeState = s
  }

  // Processes — each helper writes cache atomically AND prints JSON to stdout; handleCache parses it
  Process { id: cacheProc }
  Process {
    id: proc311
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ proc311.collected += data + "\n" } }
    onExited: function(code, status){ root.handleCache(proc311, function(v){ root.data311 = v }, "311") }
  }
  Process {
    id: procSubway
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ procSubway.collected += data + "\n" } }
    onExited: function(code, status){ root.handleCache(procSubway, function(v){ root.dataSubway = v }, "subway") }
  }
  Process {
    id: procCiti
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ procCiti.collected += data + "\n" } }
    onExited: function(code, status){ root.handleCache(procCiti, function(v){ root.dataCiti = v }, "citi") }
  }
  Process {
    id: procNYPD
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ procNYPD.collected += data + "\n" } }
    onExited: function(code, status){ root.handleCache(procNYPD, function(v){ root.dataNYPD = v }, "nypd") }
  }
  Process {
    id: procAir
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ procAir.collected += data + "\n" } }
    onExited: function(code, status){ root.handleCache(procAir, function(v){ root.dataAir = v }, "air") }
  }
  Process {
    id: procDOB
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ procDOB.collected += data + "\n" } }
    onExited: function(code, status){ root.handleCache(procDOB, function(v){ root.dataDOB = v }, "dob") }
  }
  Process {
    id: procParking
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ procParking.collected += data + "\n" } }
    onExited: function(code, status){ root.handleCache(procParking, function(v){ root.dataParking = v }, "parking") }
  }
  Process {
    id: procLottery
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ procLottery.collected += data + "\n" } }
    onExited: function(code, status){ root.handleCache(procLottery, function(v){ root.dataLottery = v }, "lottery") }
  }
  Process {
    id: procDisp
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ procDisp.collected += data + "\n" } }
    onExited: function(code, status){ root.handleCache(procDisp, function(v){ root.dataDisp = v }, "disp") }
  }
  Process {
    id: procTiles
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ procTiles.collected += data + "\n" } }
    onExited: function(code, status){ root.handleCache(procTiles, function(v){ console.log("yerrr: tiles updated"); }, "tiles") }
  }
  Process {
    id: locationProc
    property string collected: ""
    stdout: SplitParser { onRead: function(data){ locationProc.collected += data + "\n" } }
    stderr: SplitParser { onRead: function(data){ locationProc.collected += data + "\n" } }
    onExited: function(code, status){ root.handleLocation() }
  }
  Process {
    id: startDaemonProc
    onExited: function(code, status){ if(code!==0){ root.voiceBusy=false; root.terminalOutput="Voxtype daemon failed"; return } voiceDelayTimer.restart() }
  }
  Process {
    id: toggleProc
    onExited: function(code, status){ root.voiceBusy=false; if(code!==0) root.terminalOutput="Voxtype not available" }
  }
  Process { id: notifyProc }
  FileView { id: voxtypeStateView; path: root.voxtypeStateFile; watchChanges: true; printErrors: false; onFileChanged: root.refreshVoxtypeState() }
  Process {
    id: voxtypeCheck
    command: ["/usr/bin/sh","-c","PATH=/usr/bin:/bin; test -x /usr/bin/voxtype && echo yes || echo no"]
    running: true
    stdout: SplitParser { onRead: function(data){ if(String(data).trim()==="yes") root.voxtypeInstalled=true } }
  }

  Timer { id: voiceDelayTimer; interval: 600; onTriggered: { toggleProc.command=["/usr/bin/voxtype","record","toggle"]; toggleProc.running=true } }

  // Polling per dataset volatility
  Timer { id: timerLocation; interval: 300000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.fetchLocation() }
  Timer { id: timer311;     interval: 300000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.fetch311() }      // 5m
  Timer { id: timerSubway;  interval: 30000;  running: true; repeat: true; triggeredOnStart: false; onTriggered: root.fetchSubway() }    // 30s
  Timer { id: timerCiti;    interval: 120000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.fetchCiti() }       // 2m
  Timer { id: timerNYPD;    interval: 900000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.fetchNYPD() }       // 15m
  Timer { id: timerAir;     interval: 900000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.fetchAir() }        // 15m
  Timer { id: timerDOB;     interval: 3600000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.fetchDOB() }        // 60m
  Timer { id: timerParking; interval: 86400000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.fetchParking() }  // daily
  Timer { id: timerLottery; interval: 3600000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.fetchLottery() }   // 60m
  Timer { id: timerDisp;    interval: 3600000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.fetchDisp() }      // 60m
  Timer { id: timerTiles;   interval: 1800000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.fetchMapTiles() }     // 30m

  Component.onCompleted: {
    console.log("yerrr: starting — cacheDir " + cacheDir)
    root.ensureCacheDir()
    root.fetchLocation()
    // Stagger initial fetches to avoid burst — all 8 datasets populate as their helpers print JSON
    Qt.callLater(function(){ root.fetch311() })
    Qt.callLater(function(){ root.fetchSubway() })
    Qt.callLater(function(){ root.fetchCiti() })
    Qt.callLater(function(){ root.fetchNYPD() })
    Qt.callLater(function(){ root.fetchAir() })
    Qt.callLater(function(){ root.fetchDOB() })
    Qt.callLater(function(){ root.fetchParking() })
    Qt.callLater(function(){ root.fetchLottery() })
    Qt.callLater(function(){ root.fetchDisp() })
    Qt.callLater(function(){ root.fetchMapTiles() })
  }
}
