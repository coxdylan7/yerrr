#!/usr/bin/python3
"""fetch-map-tiles — download a 3x3 OSM tile grid centered on lat/lon into the yerrr cache, JPEG/PNG to file, JSON index on stdout."""
import sys, os, json, pathlib, urllib.request, secrets, stat

TIMEOUT = 8
MAX_BYTES = 5242880
TILES = 3

def fail(msg):
    print(f"fetch-map-tiles: {msg}", file=sys.stderr)
    sys.exit(1)

def validate_cache_dir(p):
    home = os.environ.get("HOME") or str(pathlib.Path.home())
    exp = os.path.join(home, ".cache", "omarchy", "yerrr") + os.sep
    if not (p == exp[:-1] or p.startswith(exp)):
        fail(f"cache must be under {exp}")
    return p

def tile_xy(lat, lon, zoom):
    n = float(1 << zoom)
    x = (lon + 180.0) / 360.0 * n
    latrad = lat * 3.141592653589793 / 180.0
    y = (1.0 - (math_log_impl(latrad))) / 2.0 * n
    return int(x), int(y)

def math_log_impl(latrad):
    import math
    return math.log(math.tan(latrad) + 1.0 / math.cos(latrad)) / 3.141592653589793

def download(url, out_path, tile_dir_fd):
    raw = None
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "yerrr/0.1 (NYC dash; https://github.com/coxdylan7/yerrr)"})
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            cl = resp.headers.get("Content-Length")
            if cl is not None and int(cl) > MAX_BYTES: fail(f"tile too large {cl}")
            raw = resp.read(MAX_BYTES+1)
        if len(raw) > MAX_BYTES: fail("tile exceeds cap")
        base = os.path.basename(out_path)
        tmp = f".yerrr-tile-{secrets.token_hex(6)}"
        fd = os.open(tmp, os.O_CREAT|os.O_EXCL|os.O_RDWR|os.O_NOFOLLOW, 0o644, dir_fd=tile_dir_fd)
        try:
            os.write(fd, raw); os.fsync(fd); os.close(fd); fd = -1
            try: os.rename(tmp, base, src_dir_fd=tile_dir_fd, dst_dir_fd=tile_dir_fd)
            except TypeError: os.rename(os.path.join(os.path.dirname(out_path), tmp), out_path)
            try: os.chmod(base, 0o600, dir_fd=tile_dir_fd)
            except: pass
        finally:
            if fd >= 0:
                try: os.close(fd)
                except: pass
            try: os.unlink(tmp, dir_fd=tile_dir_fd)
            except: pass
        return True
    except Exception as e:
        print(f"tile failed {url}: {e}", file=sys.stderr)
        return False

def main():
    if len(sys.argv) < 5:
        fail(f"usage: {sys.argv[0]} <cacheDir> <lat> <lon> <zoom>")
    cache_dir = sys.argv[1]
    validate_cache_dir(cache_dir)
    try:
        lat = float(sys.argv[2]); lon = float(sys.argv[3]); zoom = int(sys.argv[4])
    except Exception:
        fail("lat/lon/zoom not numeric")
    if not (-90 <= lat <= 90 and -180 <= lon <= 180): fail("coords out of range")
    if not (1 <= zoom <= 19): fail("zoom out of range")

    tdir = os.path.join(cache_dir, "tiles")
    pathlib.Path(tdir).mkdir(parents=True, exist_ok=True)
    dfd = os.open(tdir, os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        tx, ty = tile_xy(lat, lon, zoom)
        index = []
        half = TILES // 2
        for dx in range(-half, half+1):
            for dy in range(-half, half+1):
                nx, ny = tx+dx, ty+dy
                zdir = os.path.join(tdir, str(zoom))
                pathlib.Path(zdir).mkdir(parents=True, exist_ok=True)
                zfd = os.open(zdir, os.O_DIRECTORY | os.O_NOFOLLOW)
                try:
                    p = os.path.join(zdir, f"{nx}_{ny}.png")
                    ok = download(f"https://tile.openstreetmap.org/{zoom}/{nx}/{ny}.png", p, zfd)
                finally:
                    os.close(zfd)
                index.append({"x": nx, "y": ny, "z": zoom, "ok": ok})
        print(json.dumps(index, separators=(',',':')))
    finally:
        os.close(dfd)

if __name__ == "__main__":
    main()