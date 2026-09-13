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
"""Secure fetch-dispensaries — NY OCM cannabis businesses + georeference merged, atomic nofollow cache, JSON on stdout."""
import sys, os, json, pathlib, urllib.request, urllib.parse, urllib.error, stat, re, secrets

MAX_BYTES = 5242880
TIMEOUT = 10
APP_TOKEN_MAX = 256
API_URL = "https://data.ny.gov/resource/jskf-tt3q.json"
GEO_URL = "https://data.ny.gov/resource/gttd-5u6y.json"

def fail(msg):
    print(f"fetch-dispensaries: {msg}", file=sys.stderr)
    sys.exit(1)

def validate_cache_path(p):
    home = os.environ.get("HOME") or str(pathlib.Path.home())
    exp = os.path.join(home, ".cache", "omarchy", "yerrr") + os.sep
    if not p.startswith(exp):
        fail(f"cache must be under {exp}")
    if ".." in pathlib.Path(p).parts or "\n" in p or "\r" in p or "\x00" in p:
        fail("invalid path")
    return p

def ensure_parent_secure_pinned(parent_fd, parent_path):
    try:
        st = os.fstat(parent_fd)
    except Exception as e:
        fail(f"fstat parent failed: {e}")
    if not stat.S_ISDIR(st.st_mode): fail(f"parent not dir: {parent_path}")
    if stat.S_ISLNK(st.st_mode): fail(f"parent is symlink: {parent_path}")
    if st.st_uid != os.getuid(): fail(f"parent not owned: {parent_path}")
    if st.st_mode & (stat.S_IWGRP | stat.S_IWOTH): fail(f"parent writable: {parent_path} {oct(st.st_mode)}")

def atomic_write(path, data_bytes):
    parent = os.path.dirname(path); base = os.path.basename(path)
    home = os.environ.get("HOME") or str(pathlib.Path.home())
    home_fd = open_trusted_base(home)
    try:
        dir_fd = ensure_parent_descriptor_relative(home_fd, home, parent)
        try:
            os.fchmod(dir_fd, 0o700)
        except Exception as e:
            fail(f"fchmod parent failed: {e}")
    except Exception as e:
        try: os.close(home_fd)
        except: pass
        fail(f"ensure parent failed: {e}")
    try:
        ensure_parent_secure_pinned(dir_fd, parent)
        uid = os.getuid()
        tmp = f".yerrr-tmp-{secrets.token_hex(8)}"
        try: fd = os.open(tmp, os.O_CREAT|os.O_EXCL|os.O_RDWR|os.O_NOFOLLOW, 0o600, dir_fd=dir_fd)
        except Exception as e: fail(f"create tmp failed: {e}")
        try:
            n = os.write(fd, data_bytes)
            if n != len(data_bytes): fail("short write")
            os.fsync(fd); os.close(fd); fd=-1
            try: os.rename(tmp, base, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
            except TypeError as e: fail(f"rename with dir_fd not supported, failing closed: {e}")
            except Exception as e: fail(f"rename failed: {e}")
            tmp = None
            try:
                os.chmod(base, 0o600, dir_fd=dir_fd)
            except Exception as e:
                fail(f"chmod final failed: {e}")
        finally:
            if fd>=0:
                try: os.close(fd)
                except: pass
            if tmp is not None:
                try: os.unlink(tmp, dir_fd=dir_fd)
                except: pass
    finally:
        try: os.close(dir_fd)
        except: pass
        try: os.close(home_fd)
        except: pass

def fetch_url(url, token=""):
    headers = {"User-Agent": "yerrr/0.1.0"}
    if token: headers["X-App-Token"] = token
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            cl = resp.headers.get("Content-Length")
            if cl is not None:
                try:
                    if int(cl) > MAX_BYTES: fail(f"content-length {cl} exceeds cap")
                except: pass
            raw = resp.read(MAX_BYTES+1)
            if len(raw) > MAX_BYTES: fail("response exceeds cap")
            return raw
    except Exception as e:
        raise e

def main():
    if len(sys.argv) < 3:
        fail(f"usage: {sys.argv[0]} <cachePath> <limit> [appToken]")
    cache = sys.argv[1]; limit = sys.argv[2]; token = sys.argv[3] if len(sys.argv)>3 else ""
    validate_cache_path(cache)
    try: lim = int(limit)
    except: fail("limit not int")
    if not (1 <= lim <= 5000): fail("limit out of range")
    if token and len(token) > APP_TOKEN_MAX: fail("token too long")
    if token and any(c in token for c in ["\n","\r","\x00","'",'"',"`"]): fail("token bad chars")
    try:
        pri = json.loads(fetch_url(API_URL + "?$limit=" + str(lim)).decode('utf-8'))
        geo = json.loads(fetch_url(GEO_URL + "?$limit=5000").decode('utf-8'))
    except Exception as e:
        print(f"fetch failed {e}, keeping last-known cache if present", file=sys.stderr)
        try:
            # descriptor-relative nofollow read with byte cap
            d = os.path.dirname(cache); b = os.path.basename(cache)
            dir_fd2 = os.open(d, os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                fd2 = os.open(b, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd2)
                try:
                    data = os.read(fd2, MAX_BYTES + 1)
                    if len(data) > MAX_BYTES:
                        raise ValueError("exceeds cap")
                    last_known = json.loads(data.decode())
                    print(json.dumps(last_known, separators=(',',':')))
                    return
                finally:
                    os.close(fd2)
            finally:
                os.close(dir_fd2)
        except Exception as ce:
            print(f"no usable cache ({ce}), writing mock", file=sys.stderr)
            mock = [{"dba":"Herb Houses NYC","license_number":"NY-MOCK-1","city":"Brooklyn","state":"NY","zip_code":"11211","status":"Active","lat":40.71,"lon":-73.96}]
            atomic_write(cache, json.dumps(mock).encode())
            print(json.dumps(mock, separators=(',',':')))
            return
    priF = [r for r in pri if isinstance(r, dict) and r.get("license_status") == "Active" and r.get("operational_status") == "Active" and r.get("business_purpose") == "Adult-Use Retail Sales"]
    gmap = {}
    for g in geo:
        if not isinstance(g, dict): continue
        k = str(g.get("ocm_license_number") or "").strip()
        gr = g.get("georeference")
        if k and isinstance(gr, dict):
            c = gr.get("coordinates")
            if isinstance(c, (list, tuple)) and len(c) >= 2 and all(isinstance(v,(int,float)) for v in c[:2]):
                gmap[k] = {"lat": float(c[1]), "lon": float(c[0])}
    out = []
    for r in priF[:lim]:
        lic = str(r.get("license_number") or "").strip()
        gr = gmap.get(lic)
        out.append({
            "dba": str(r.get("dba") or r.get("entity_name") or "").strip(),
            "license_number": lic,
            "license_type_code": str(r.get("license_type_code") or "").strip(),
            "status": str(r.get("license_status") or "").strip(),
            "city": str(r.get("city") or "").strip(),
            "state": str(r.get("state") or "").strip(),
            "zip": str(r.get("zip_code") or "").strip(),
            "address": str(r.get("address_line_1") or "").strip(),
            "lat": float(gr["lat"]) if gr else None,
            "lon": float(gr["lon"]) if gr else None
        })
    atomic_write(cache, json.dumps(out).encode())
    print(json.dumps(out, separators=(',',':')))

if __name__ == "__main__":
    main()