def open_trusted_base(home_path):
    # Open HOME with O_DIRECTORY|O_NOFOLLOW and validate
    try:
        fd = os.open(home_path, os.O_DIRECTORY | os.O_NOFOLLOW)
    except Exception as e:
        fail(f"open HOME failed: {e}")
    try:
        st = os.fstat(fd)
    except Exception as e:
        try: os.close(fd)
        except: pass
        fail(f"fstat HOME failed: {e}")
    if not stat.S_ISDIR(st.st_mode):
        try: os.close(fd)
        except: pass
        fail(f"HOME not directory: {home_path}")
    if stat.S_ISLNK(st.st_mode):
        try: os.close(fd)
        except: pass
        fail(f"HOME is symlink: {home_path}")
    if st.st_uid != os.getuid():
        try: os.close(fd)
        except: pass
        fail(f"HOME not owned: {home_path}")
    if st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        try: os.close(fd)
        except: pass
        fail(f"HOME writable by group/other: {home_path} mode {oct(st.st_mode)}")
    return fd

def ensure_parent_descriptor_relative(home_fd, home_path, parent_path):
    # parent_path is absolute, must be under home_path
    if not parent_path.startswith(home_path + os.sep):
        fail(f"parent not under HOME: {parent_path}")
    rel = os.path.relpath(parent_path, home_path)  # e.g. .config/hypr
    parts = rel.split(os.sep)
    cur_fd = home_fd
    cur_path = home_path
    # We will walk components, opening each descriptor-relatively, creating if needed via mkdirat
    # To avoid leaking fds, we keep current fd and open next, then close previous when moving deeper
    # But we need to keep home_fd open for caller? We'll duplicate.
    # Instead, we will use home_fd as base and walk with new fds, closing intermediate.
    # For simplicity, we dup home_fd to start
    try:
        cur_fd_dup = os.dup(home_fd)
    except Exception as e:
        fail(f"dup HOME fd failed: {e}")
    cur_fd = cur_fd_dup
    cur_path = home_path
    for comp in parts:
        if not comp or comp == ".":
            continue
        if comp == ".." or "/" in comp or "\n" in comp or "\0" in comp:
            try: os.close(cur_fd)
            except: pass
            fail(f"invalid component: {comp}")
        # Try to open next component with O_NOFOLLOW
        next_path = os.path.join(cur_path, comp)
        try:
            next_fd = os.open(comp, os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=cur_fd)
            # Validate opened dir
            try:
                st = os.fstat(next_fd)
            except Exception as e:
                try: os.close(next_fd)
                except: pass
                try: os.close(cur_fd)
                except: pass
                fail(f"fstat component failed {next_path}: {e}")
            if not stat.S_ISDIR(st.st_mode):
                try: os.close(next_fd)
                except: pass
                try: os.close(cur_fd)
                except: pass
                fail(f"component not directory: {next_path}")
            if stat.S_ISLNK(st.st_mode):
                try: os.close(next_fd)
                except: pass
                try: os.close(cur_fd)
                except: pass
                fail(f"component is symlink: {next_path}")
            if st.st_uid != os.getuid():
                try: os.close(next_fd)
                except: pass
                try: os.close(cur_fd)
                except: pass
                fail(f"component not owned: {next_path}")
            if st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
                try: os.close(next_fd)
                except: pass
                try: os.close(cur_fd)
                except: pass
                fail(f"component writable by group/other: {next_path} mode {oct(st.st_mode)}")
            # Success, move to next
            try: os.close(cur_fd)
            except: pass
            cur_fd = next_fd
            cur_path = next_path
        except FileNotFoundError:
            # Need to create directory descriptor-relatively via mkdirat
            try:
                os.mkdir(comp, 0o700, dir_fd=cur_fd)
            except FileExistsError:
                # Raced, try open again
                try:
                    next_fd = os.open(comp, os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=cur_fd)
                    st = os.fstat(next_fd)
                    if st.st_uid != os.getuid() or st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
                        try: os.close(next_fd)
                        except: pass
                        try: os.close(cur_fd)
                        except: pass
                        fail(f"raced component not owned/writable: {next_path}")
                    try: os.close(cur_fd)
                    except: pass
                    cur_fd = next_fd
                    cur_path = next_path
                    continue
                except Exception as e:
                    try: os.close(cur_fd)
                    except: pass
                    fail(f"mkdir raced open failed {next_path}: {e}")
            except Exception as e:
                try: os.close(cur_fd)
                except: pass
                fail(f"mkdir component failed {next_path}: {e}")
            # After mkdir, open it
            try:
                next_fd = os.open(comp, os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=cur_fd)
            except Exception as e:
                try: os.close(cur_fd)
                except: pass
                fail(f"open after mkdir failed {next_path}: {e}")
            # Validate and chmod via fd (fchmod) to 0o700
            try:
                st = os.fstat(next_fd)
                if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
                    try: os.close(next_fd)
                    except: pass
                    try: os.close(cur_fd)
                    except: pass
                    fail(f"new component not owned/dir: {next_path}")
                # Ensure perms 0o700 via fchmod
                try:
                    os.fchmod(next_fd, 0o700)
                except Exception as e:
                    try: os.close(next_fd)
                    except: pass
                    try: os.close(cur_fd)
                    except: pass
                    fail(f"fchmod failed {next_path}: {e}")
            except Exception as e:
                try: os.close(next_fd)
                except: pass
                try: os.close(cur_fd)
                except: pass
                fail(f"fstat new component failed {next_path}: {e}")
            try: os.close(cur_fd)
            except: pass
            cur_fd = next_fd
            cur_path = next_path
        except OSError as e:
            # Any other error (e.g., symlink encountered, ELOOP)
            try: os.close(cur_fd)
            except: pass
            fail(f"open component failed {next_path}: {e}")
    # cur_fd is now the parent directory fd, pinned
    return cur_fd


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
            except TypeError as e: fail(f"rename with dir_fd not supported, failing closed: {e}")
            except Exception as e: fail(f"rename failed: {e}")
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
    # Secure mkdir via descriptor-relative
    _home = os.environ.get("HOME") or str(pathlib.Path.home())
    _home_fd = open_trusted_base(_home)
    try:
        _tdir_fd = ensure_parent_descriptor_relative(_home_fd, _home, tdir)
        try: os.fchmod(_tdir_fd, 0o700)
        except: pass
        os.close(_tdir_fd)
    finally:
        try: os.close(_home_fd)
        except: pass
    dfd = os.open(tdir, os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        tx, ty = tile_xy(lat, lon, zoom)
        index = []
        half = TILES // 2
        for dx in range(-half, half+1):
            for dy in range(-half, half+1):
                nx, ny = tx+dx, ty+dy
                zdir = os.path.join(tdir, str(zoom))
                _home2 = os.environ.get("HOME") or str(pathlib.Path.home())
                _home_fd2 = open_trusted_base(_home2)
                try:
                    _zdir_fd = ensure_parent_descriptor_relative(_home_fd2, _home2, zdir)
                    try: os.fchmod(_zdir_fd, 0o700)
                    except: pass
                    os.close(_zdir_fd)
                finally:
                    try: os.close(_home_fd2)
                    except: pass
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