# Yerrr

Jarvis-like NYC dashboard for Omarchy. **Bar icon that expands** to a full **Jarvis dash** — wavy `YERRR` sprite, voice (`voxtype`), and terminal — fusing **8 NYC Open Data families** into one cross-referenced UI by **ZIP / borough / time**.

![preview](preview.png)

## Datasets (all Socrata / MTA / GBFS, cross-referenced)

| Feed | Source | Poll | Notes |
|---|---|---|---|
| **311** | `data.cityofnewyork.us/resource/erm2-nwe9.json` | 5m | `complaint_type`/`borough`/`incident_zip` |
| **MTA Subway** | `api.mta.info` GTFS-RT + status | 30s | `trip_update` delays |
| **Citi Bike** | `gbfs.citibikenyc.com/gbfs/en/station_status.json` | 2m | GBFS `num_bikes_available` |
| **NYPD** | `data.cityofnewyork.us/resource/5uac-w243.json` | 15m | `law_cat_cd`/`boro_nm` |
| **Air Quality** | `data.cityofnewyork.us/resource/c3uy-2p5r.json` | 15m | `aqi`/`pm2_5` |
| **DOB Permits** | `data.cityofnewyork.us/resource/ipu4-2q9a.json` | 60m | `job_type`/`borough` |
| **Parking Violations** | `data.cityofnewyork.us/resource/nc67-uf89.json` | 1×/day | `violation_code`/`zip` |
| **Lottery** | `data.ny.gov/resource/d6yy-54nr.json` + `5xaw-6ayf.json` | 60m | Powerball/Take5 winners |
| **Location** | `GeoClue2` → `nmcli` → `ipinfo` → `weather.json` | 5m | Reused hardened `fetch-yerrr-location.py` |

All 8 write to `~/.cache/omarchy/yerrr/*.json` via **pinned `O_DIRECTORY|O_NOFOLLOW` FD**, `S_IWGRP|S_IWOTH` rejection, `secrets.token_hex` tmp, `renameat(src_dir_fd,dst_dir_fd)` — same hardening as `tomb-stone` `b2acb44`/`pot-head` `d68ed6b`.

## Features

- **Bar icon:** `YERRR` wavy sprite (`components/WavySprite.qml` — sine-displaced `screensaver.txt` style). `○` idle / `● STOP` `Color.urgent` pulse when `voxtype` recording. Click → expand dash; `Esc` / `Super+Y` collapses.
- **Dash overlay:** `Dash.qml` `PanelWindow` `Overlay` 90vw × 86vh glass card: header pills (`All`/`MN`/`BK`/`QN`/`BX`/`SI` + ZIP + `24h`/`7d`), cross-summary (`Yerrr.js:crossRef311VsSubway`), map placeholder (OSM), 7 cards (311 top types, subway lines, Citi/NYPD/Air/DOB/Parking/Lottery counts), all filtered together.
- **Terminal strip:** `❯` monospace input at bottom — `bk 311 24h`, `queens subway`, `11211 citi`, `clear`, `refresh`. Parses via `Yerrr.js:terminalParse`.
- **Voice:** `voxtype` toggle `"/usr/bin/voxtype" "record" "toggle"` via `"/usr/bin/systemctl" "--user" "start" "voxtype.service"` + `FileView` on `XDG_RUNTIME_DIR/voxtype/state` — same as `tomb-stone`.
- **Location:** Automatic via `helpers/fetch-yerrr-location.py` (`/usr/bin/busctl`/`/usr/bin/gdbus`/`/usr/bin/nmcli` absolute, `PATH=/usr/bin:/bin` closed) or `locationOverrideLat/Lon` in `shell.json`.

## Installation

```sh
omarchy plugin add https://github.com/coxdylan7/yerrr --enable
# or manual:
mkdir -p ~/.config/omarchy/plugins
cp -r djc.yerrr ~/.config/omarchy/plugins/
omarchy restart shell
```

Add to `~/.config/omarchy/shell.json`:

```json
{
  "bar": {
    "layout": {
      "right": [{ "id": "djc.yerrr" }, { "id": "omarchy.tray" }]
    }
  },
  "plugins": [
    {
      "id": "djc.yerrr",
      "locationOverrideLat": "40.7580",
      "locationOverrideLon": "-73.9855",
      "appToken": ""
    }
  ]
}
```

Press the `YERRR` bar pill → Jarvis dash appears. Type in terminal or say “yo yerrr show Brooklyn 311”.

## Security

- No `bash -c` string concatenation; all `Process.command = ["/usr/bin/python3", helper, …]` with absolute trusted binaries, `PATH=/usr/bin:/bin` closed for shell pipelines.
- Helpers `#!/usr/bin/python3`, timeout 5–10s, byte caps 256KiB–5MiB before JSON parse, `json.dumps` argv passing, atomic `600` cache via pinned FD.

## License

MIT
