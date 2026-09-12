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
    try:
        pathlib.Path(parent).mkdir(parents=True, exist_ok=True)
        os.chmod(parent, 0o700)
    except Exception as e: fail(f"mkdir failed: {e}")
    try: dir_fd = os.open(parent, os.O_DIRECTORY | os.O_NOFOLLOW)
    except Exception as e: fail(f"open parent failed: {e}")
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
            except TypeError: os.rename(os.path.join(parent, tmp), path)
            tmp = None
            try: os.chmod(base, 0o600, dir_fd=dir_fd)
            except: os.chmod(path, 0o600)
        finally:
            if fd>=0:
                try: os.close(fd)
                except: pass
            if tmp is not None:
                try: os.unlink(tmp, dir_fd=dir_fd)
                except: pass
                try: os.unlink(os.path.join(parent, tmp))
                except: pass
    finally:
        try: os.close(dir_fd)
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
            with open(cache, "rb") as fh:
                last_known = json.loads(fh.read())
            print(json.dumps(last_known, separators=(',',':')))
            return
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