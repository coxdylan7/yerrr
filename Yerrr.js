function pluginEntry(shell, pluginId) {
  var cfg = shell ? shell.shellConfig : null
  var list = cfg && Array.isArray(cfg.plugins) ? cfg.plugins : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && String(list[i].id || "") === pluginId) return list[i]
  }
  return {}
}
function configStr(entry, key, fallback) {
  var v = entry[key]
  return typeof v === "string" && v.length > 0 ? v : fallback
}
function configInt(entry, key, fallback) {
  var v = entry[key]
  var n = Number(v)
  return isFinite(n) && n >= 0 ? Math.round(n) : fallback
}
function configFloat(entry, key, fallback) {
  var v = entry[key]
  var n = Number(v)
  return isFinite(n) ? n : fallback
}
function configBool(entry, key, fallback) {
  var v = entry[key]
  return v === undefined ? fallback : !!v
}
function configList(entry, key, fallback) {
  var v = entry[key]
  return Array.isArray(v) && v.length > 0 ? v.slice() : fallback.slice()
}
function haversineMiles(lat1, lon1, lat2, lon2) {
  var toRad = Math.PI/180
  var dLat = (lat2-lat1)*toRad
  var dLon = (lon2-lon1)*toRad
  var a = Math.sin(dLat/2)*Math.sin(dLat/2) + Math.cos(lat1*toRad)*Math.cos(lat2*toRad)*Math.sin(dLon/2)*Math.sin(dLon/2)
  var c = 2*Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
  return 3959*c
}
// Borough helpers
var BOROUGHS = ["Manhattan","Brooklyn","Queens","Bronx","Staten Island"]
function boroughFromZip(zip) {
  var z = String(zip||"").trim()
  if (!z) return ""
  var n = parseInt(z,10)
  if (n>=10001 && n<=10282) return "Manhattan"
  if (n>=10301 && n<=10314) return "Staten Island"
  if (n>=10451 && n<=10475) return "Bronx"
  if ((n>=11004 && n<=11005) || (n>=11101 && n<=11109) || (n>=11351 && n<=11697) || (n>=11354 && n<=11375)) return "Queens"
  if (n>=11201 && n<=11256) return "Brooklyn"
  // Additional Queens/Brooklyn edge cases
  if (n>=11354 && n<=11439) return "Queens"
  if (n>=11690 && n<=11697) return "Queens"
  return ""
}
function boroughAbbr(b) {
  if (!b) return ""
  var m = {"Manhattan":"MN","Brooklyn":"BK","Queens":"QN","Bronx":"BX","Staten Island":"SI"}
  return m[b] || String(b).slice(0,2).toUpperCase()
}
// Normalizers — all return {id, zip, borough, lat, lon, ts, kind, raw}
function normalize311(raw) {
  var zip = String(raw.incident_zip || raw.zip || "").trim()
  var borough = String(raw.borough || raw.borough_name || boroughFromZip(zip) || "").trim()
  var lat = raw.latitude ? Number(raw.latitude) : (raw.georeference && raw.georeference.coordinates ? Number(raw.georeference.coordinates[1]) : NaN)
  var lon = raw.longitude ? Number(raw.longitude) : (raw.georeference && raw.georeference.coordinates ? Number(raw.georeference.coordinates[0]) : NaN)
  var ts = raw.created_date ? Date.parse(raw.created_date) : (raw.createddate ? Date.parse(raw.createddate) : NaN)
  return {
    id: String(raw.unique_key || raw.incident_key || raw.complaint_number || Math.random().toString(36).slice(2)),
    zip: zip,
    borough: borough || boroughFromZip(zip),
    neighborhood: String(raw.city || raw.incident_address || ""),
    lat: lat, lon: lon,
    ts: isFinite(ts) ? ts : Date.now(),
    kind: "311",
    subtype: String(raw.complaint_type || raw.complaint || "311"),
    descriptor: String(raw.descriptor || ""),
    status: String(raw.status || ""),
    raw: raw
  }
}
function normalizeSubway(raw) {
  // raw from helpers: {line, status, delayMin, cause}
  return {
    id: String(raw.line || raw.route_id || Math.random().toString(36).slice(2)),
    zip: "",
    borough: String(raw.borough || ""),
    lat: NaN, lon: NaN,
    ts: raw.updated ? Date.parse(raw.updated) : Date.now(),
    kind: "subway",
    subtype: String(raw.line || raw.route || "MTA"),
    status: String(raw.status || raw.delay || ""),
    delayMin: Number(raw.delayMin || 0),
    raw: raw
  }
}
function normalizeCiti(raw) {
  var lat = Number(raw.lat || raw.latitude || raw.latInternal || NaN)
  var lon = Number(raw.lon || raw.longitude || raw.lonInternal || NaN)
  // station_information join for lat/lon/region is done in helper, fallback to 0,0 if missing
  var zip = String(raw.zip || raw.postalCode || "").trim()
  return {
    id: String(raw.station_id || raw.legacy_id || raw.external_id || ""),
    zip: zip,
    borough: boroughFromZip(zip),
    lat: isFinite(lat) ? lat : NaN, lon: isFinite(lon) ? lon : NaN,
    ts: Date.now(),
    kind: "citi",
    subtype: String(raw.name || "CitiBike"),
    bikes: Number(raw.num_bikes_available || raw.bikes || 0),
    docks: Number(raw.num_docks_available || raw.docks || 0),
    raw: raw
  }
}
function normalizeNYPD(raw) {
  var zip = String(raw.zip_code || raw.jurisdiction_code || "").trim()
  // Try geocoded column or lat/lon fields
  var lat = raw.latitude ? Number(raw.latitude) : (raw.geocoded_column && raw.geocoded_column.coordinates ? Number(raw.geocoded_column.coordinates[1]) : (raw.lat ? Number(raw.lat) : NaN))
  var lon = raw.longitude ? Number(raw.longitude) : (raw.geocoded_column && raw.geocoded_column.coordinates ? Number(raw.geocoded_column.coordinates[0]) : (raw.lon ? Number(raw.lon) : NaN))
  var tsRaw = raw.cmplnt_fr_dt || raw.cmplnt_fr_date || raw.created_date
  var ts = tsRaw ? Date.parse(tsRaw) : NaN
  if (!isFinite(ts) && raw.cmplnt_fr_tm) {
    // try combined date+time
    var dt = String(raw.cmplnt_fr_dt || "") + "T" + String(raw.cmplnt_fr_tm || "")
    ts = Date.parse(dt)
  }
  return {
    id: String(raw.cmplnt_num || raw.complaint_report_number || raw.incident_key || Math.random().toString(36).slice(2)),
    zip: zip,
    borough: String(raw.boro_nm || raw.borough || boroughFromZip(zip) || "").trim() || boroughFromZip(zip),
    lat: lat, lon: lon,
    ts: isFinite(ts) ? ts : Date.now(),
    kind: "nypd",
    subtype: String(raw.ofns_desc || raw.law_cat_cd || "NYPD"),
    raw: raw
  }
}
function normalizeAir(raw) {
  return {
    id: String(raw.site_id || raw.unique_id || ""),
    zip: String(raw.zip_code || ""),
    borough: String(raw.borough || ""),
    lat: raw.latitude ? Number(raw.latitude) : NaN,
    lon: raw.longitude ? Number(raw.longitude) : NaN,
    ts: raw.sample_date ? Date.parse(raw.sample_date) : Date.now(),
    kind: "air",
    subtype: "Air",
    aqi: Number(raw.aqi || raw.pm2_5 || 0),
    raw: raw
  }
}
function normalizeDOB(raw) {
  return {
    id: String(raw.job__ || raw.job_number || ""),
    zip: String(raw.zip_code || ""),
    borough: String(raw.borough || ""),
    lat: raw.latitude ? Number(raw.latitude) : NaN,
    lon: raw.longitude ? Number(raw.longitude) : NaN,
    ts: raw.pre_filing_date ? Date.parse(raw.pre_filing_date) : Date.now(),
    kind: "dob",
    subtype: String(raw.job_type || "DOB"),
    raw: raw
  }
}
function normalizeParking(raw) {
  return {
    id: String(raw.summons_number || ""),
    zip: String(raw.zip_code || ""),
    borough: boroughFromZip(raw.zip_code),
    lat: NaN, lon: NaN,
    ts: raw.issue_date ? Date.parse(raw.issue_date) : Date.now(),
    kind: "parking",
    subtype: String(raw.violation_code || "Parking"),
    raw: raw
  }
}
function normalizeLottery(raw) {
  return {
    id: String(raw.draw_date || raw.transaction_id || ""),
    zip: String(raw.winning_zip_code || raw.retailer_zip || raw.zip || ""),
    borough: boroughFromZip(String(raw.winning_zip_code || "")),
    lat: NaN, lon: NaN,
    ts: raw.draw_date ? Date.parse(raw.draw_date) : Date.now(),
    kind: "lottery",
    subtype: String(raw.game || "Lottery"),
    amount: String(raw.winning_amount || raw.prize || ""),
    raw: raw
  }
}
// Cross-ref helpers
function groupByZip(records) {
  var m = {}
  for (var i=0;i<records.length;i++) {
    var r = records[i]
    var z = String(r.zip||"").trim()
    if (!z) continue
    m[z] = (m[z]||0)+1
  }
  return m
}
function groupByBorough(records) {
  var m = {}
  for (var i=0;i<records.length;i++) {
    var b = String(records[i].borough||"").trim()
    if (!b) continue
    m[b] = (m[b]||0)+1
  }
  return m
}
function filterByTime(records, hours) {
  var cutoff = Date.now() - hours*3600*1000
  var out = []
  for (var i=0;i<records.length;i++) if (records[i].ts >= cutoff) out.push(records[i])
  return out
}
function filterByBorough(records, borough) {
  if (!borough || borough==="All") return records.slice()
  var target = String(borough).trim().toUpperCase()
  var out=[]
  for (var i=0;i<records.length;i++) if (String(records[i].borough||"").trim().toUpperCase()===target) out.push(records[i])
  return out
}
function filterByZip(records, zip) {
  if (!zip) return records.slice()
  var out=[]
  for (var i=0;i<records.length;i++) if (String(records[i].zip)===String(zip)) out.push(records[i])
  return out
}
function sortByTimeDesc(list) {
  return list.slice().sort(function(a,b){return b.ts-a.ts})
}
function topComplaintTypes(records, n) {
  n=n||5
  var m={}
  for (var i=0;i<records.length;i++) { var k=String(records[i].subtype||"Other"); m[k]=(m[k]||0)+1 }
  var arr=[]
  for (var k in m) arr.push({type:k, count:m[k]})
  arr.sort(function(a,b){return b.count-a.count})
  return arr.slice(0,n)
}
function crossRef311VsSubway(by311, bySubway, hours) {
  // by311: 311 records filtered, bySubway: subway status lines
  // returns string summary
  var cnt311 = by311.length
  var delayed = 0
  for (var i=0;i<bySubway.length;i++) if (Number(bySubway[i].delayMin||0) > 3) delayed++
  if (cnt311===0 && delayed===0) return "Quiet streets + trains on time"
  if (delayed>0) return delayed + " line"+(delayed>1?"s":"")+" delayed · " + cnt311 + " 311 in " + hours + "h"
  return cnt311 + " 311 reports in " + hours + "h"
}
function terminalParse(input) {
  var s = String(input||"").toLowerCase().trim()
  var out = { borough: "All", zip: "", hours: null, kinds: [] }
  if (!s) return out
  for (var i=0;i<BOROUGHS.length;i++) if (s.indexOf(BOROUGHS[i].toLowerCase())!==-1) { out.borough = BOROUGHS[i]; break }
  var m = s.match(/\b(\d{5})\b/)
  if (m) out.zip = m[1]
  var hm = s.match(/(\d+)\s*h/)
  if (hm) out.hours = Math.max(1, Math.min(168, parseInt(hm[1],10)))
  else if (s.indexOf("7d")!==-1 || s.indexOf("week")!==-1) out.hours = 168
  else if (s.indexOf("today")!==-1) out.hours = 24
  else if (s.indexOf("24h")!==-1) out.hours = 24
  var kinds = ["311","subway","citi","nypd","air","dob","parking","lottery","disp","dispensary"]
  for (var k=0;k<kinds.length;k++) if (s.indexOf(kinds[k])!==-1) {
    var kk = kinds[k]==="dispensary"?"disp":kinds[k]
    if (out.kinds.indexOf(kk)===-1) out.kinds.push(kk)
  }
  if (s.indexOf("all")!==-1) out.kinds = ["311","subway","citi","nypd","air","dob","parking","lottery","disp"]
  return out
}
function normalizeDispensaries(raw) {
  var out = []
  for (var i=0;i<raw.length;i++) {
    var r = raw[i]
    var zip = String(r.zip || r.zip_code || "").trim()
    var lat = isFinite(Number(r.lat)) ? Number(r.lat) : (r.georeference && r.georeference.coordinates ? Number(r.georeference.coordinates[1]) : NaN)
    var lon = isFinite(Number(r.lon)) ? Number(r.lon) : (r.georeference && r.georeference.coordinates ? Number(r.georeference.coordinates[0]) : NaN)
    out.push({
      dba: String(r.dba || r.entity_name || r.dbA || "").trim(),
      name: String(r.dba || r.entity_name || r.dbA || "").trim(),
      license: String(r.license_number || "").trim(),
      licenseCode: String(r.license_type_code || "").trim(),
      licenseType: String(r.license_type || "").trim(),
      status: String(r.status || r.license_status || "").trim(),
      city: String(r.city || "").trim(),
      state: String(r.state || r.State || "").trim(),
      zip: zip,
      borough: boroughFromZip(zip),
      address: String(r.address || r.address_line_1 || "").trim(),
      county: String(r.county || "").trim(),
      website: String(r.business_website || "").trim(),
      hours: String(r.hours_of_operation || "").trim(),
      contact: String(r.primary_contact_name || "").trim(),
      issued: String(r.issued_date || "").slice(0,10),
      expires: String(r.expiration_date || "").slice(0,10),
      opened: String(r.retail_date_opened_to_public || "").slice(0,10),
      lat: lat, lon: lon,
      ts: Date.now(),
      kind: "disp",
      raw: r
    })
  }
  return out
}
function formatDistance(miles) {
  if (!isFinite(miles)) return "--"
  return miles < 10 ? miles.toFixed(1) : Math.round(miles).toString()
}
function estimateMinutes(miles) {
  if (!isFinite(miles)) return -1
  return Math.max(1, Math.round((miles / 25) * 60))
}
function buildAddress(d) {
  var parts = []
  if (d.address) parts.push(d.address)
  var line = (d.city ? d.city + (d.state ? ", " + d.state : "") + (d.zip ? " " + d.zip : "") : (d.state || "") + " " + (d.zip || "")).trim()
  if (line) parts.push(line)
  return parts.join(", ")
}
function parseHoursForToday(hoursStr) {
  if (!hoursStr || typeof hoursStr !== "string" || hoursStr.trim().length === 0) return { today: "", openNow: null, raw: "" }
  var raw = hoursStr.trim()
  var todayAbbrs = [["Sun","Sunday"],["Mon","Monday"],["Tues","Tue","Tuesday"],["Wed","Wednesday"],["Thurs","Thu","Thursday"],["Fri","Friday"],["Sat","Saturday"]]
  var todayIdx = new Date().getDay()
  var candidates = todayAbbrs[todayIdx]
  var lower = raw.toLowerCase()
  var todaySegment = ""
  var parts = raw.split(/;\s*|\|\s*/g)
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i]
    var pl = p.toLowerCase()
    var hit = false
    for (var j = 0; j < candidates.length; j++) if (pl.indexOf(candidates[j].toLowerCase()) !== -1) { hit = true; break }
    if (hit) { todaySegment = p.trim(); break }
  }
  if (!todaySegment) return { today: raw.length > 60 ? raw.slice(0,60) + "…" : raw, openNow: null, raw: raw }
  var m = todaySegment.match(/(\d{1,2}):?(\d{2})?\s*(AM|PM|A\.M\.|P\.M\.)\s*-\s*(\d{1,2}):?(\d{2})?\s*(AM|PM|A\.M\.|P\.M\.)/i)
  var openNow = null
  if (m) {
    try {
      var now = new Date()
      var nowMin = now.getHours()*60 + now.getMinutes()
      function toMin(hStr, mStr, ap) {
        var h = parseInt(hStr,10); var mm = mStr ? parseInt(mStr,10) : 0
        var apu = String(ap||"").toUpperCase().replace(/\./g,"")
        if (apu === "PM" && h < 12) h += 12
        if (apu === "AM" && h === 12) h = 0
        return h*60+mm
      }
      var openMin = toMin(m[1], m[2], m[3])
      var closeMin = toMin(m[4], m[5], m[6] || m[3])
      if (closeMin < openMin) closeMin += 24*60
      openNow = nowMin >= openMin && nowMin < closeMin
    } catch(e) { openNow = null }
  }
  var cleaned = todaySegment.replace(/^[A-Za-z]+\s*:?\s*/,"").trim()
  return { today: cleaned || todaySegment, openNow: openNow, raw: raw }
}
function parseWeeklyHours(hoursStr) {
  if (!hoursStr || typeof hoursStr !== "string" || hoursStr.trim().length === 0) return []
  var raw = hoursStr.trim()
  var parts = raw.split(/;\s*|\|\s*/g)
  var todayIdx = new Date().getDay()
  var dayMap = { sun:0, sunday:0, mon:1, monday:1, tues:2, tue:2, tuesday:2, wed:3, wednesday:3, thurs:4, thu:4, thursday:4, fri:5, friday:5, sat:6, saturday:6 }
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i].trim()
    if (!p) continue
    var m = p.match(/^\s*([A-Za-z]+)\s*:?\s*(.*)$/)
    var dayLabel = ""
    var hoursPart = p
    if (m) {
      dayLabel = m[1]
      hoursPart = m[2].trim() || "Closed"
      var dl = dayLabel.toLowerCase()
      if (dl.indexOf("tues") === 0) dayLabel = "Tue"
      else if (dl.indexOf("thurs") === 0) dayLabel = "Thu"
      else dayLabel = dayLabel.slice(0,3)
      dayLabel = dayLabel.charAt(0).toUpperCase() + dayLabel.slice(1).toLowerCase()
      if (dayLabel.toLowerCase() === "tues") dayLabel = "Tue"
      if (dayLabel.toLowerCase() === "thurs") dayLabel = "Thu"
    }
    var isToday = dayMap[dayLabel.toLowerCase()] !== undefined && dayMap[dayLabel.toLowerCase()] === todayIdx
    if (isToday) isToday = true
    out.push({ day: dayLabel || "Day", hours: hoursPart, isToday: isToday, raw: p })
  }
  if (out.length === 0 && raw) out.push({ day: "", hours: raw, isToday: false, raw: raw })
  return out
}
function nearestDispensaries(recs, lat, lon, n) {
  var out = []
  for (var i=0;i<recs.length;i++) {
    var r = recs[i]
    if (!isFinite(r.lat) || !isFinite(r.lon)) continue
    var miles = haversineMiles(lat, lon, r.lat, r.lon)
    out.push({rec: r, miles: miles})
  }
  out.sort(function(a,b){ return a.miles - b.miles })
  var res = []
  for (var k=0;k<out.length && k<(n||3);k++) res.push(out[k])
  return res
}
function tileXY(lat, lon, zoom) {
  var n = Math.pow(2, zoom)
  var x = (lon + 180) / 360 * n
  var latrad = lat * Math.PI / 180
  var y = (1 - Math.log(Math.tan(latrad) + 1/Math.cos(latrad)) / Math.PI) / 2 * n
  return { tx: Math.floor(x), ty: Math.floor(y), fx: (x - Math.floor(x)), fy: (y - Math.floor(y)) }
}
function timeAgo(iso) {
  if (!iso) return ""
  var t = (new Date(iso)).getTime()
  if (!isFinite(t)) return ""
  var d = Math.floor((Date.now() - t) / 1000)
  if (d < 60) return d + "s"
  if (d < 3600) return Math.floor(d/60) + "m"
  if (d < 86400) return Math.floor(d/3600) + "h"
  return Math.floor(d/86400) + "d"
}
if (typeof module !== "undefined") {
  module.exports = {
    pluginEntry: pluginEntry, configStr: configStr, configInt: configInt, configFloat: configFloat, configBool: configBool, configList: configList,
    haversineMiles: haversineMiles, boroughFromZip: boroughFromZip, boroughAbbr: boroughAbbr,
    normalize311: normalize311, normalizeSubway: normalizeSubway, normalizeCiti: normalizeCiti, normalizeNYPD: normalizeNYPD, normalizeAir: normalizeAir, normalizeDOB: normalizeDOB, normalizeParking: normalizeParking, normalizeLottery: normalizeLottery, normalizeDispensaries: normalizeDispensaries,
    groupByZip: groupByZip, groupByBorough: groupByBorough, filterByTime: filterByTime, filterByBorough: filterByBorough, filterByZip: filterByZip, sortByTimeDesc: sortByTimeDesc, topComplaintTypes: topComplaintTypes, crossRef311VsSubway: crossRef311VsSubway, terminalParse: terminalParse,
    nearestDispensaries: nearestDispensaries, tileXY: tileXY, timeAgo: timeAgo, BOROUGHS: BOROUGHS,
    formatDistance: formatDistance, estimateMinutes: estimateMinutes, buildAddress: buildAddress,
    parseHoursForToday: parseHoursForToday, parseWeeklyHours: parseWeeklyHours
  }
}
