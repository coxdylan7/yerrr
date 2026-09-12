#!/usr/bin/python3
"""Secure fetch-air fetch — timeout/byte caps, atomic nofollow cache."""
import sys, os, json, pathlib, urllib.request, urllib.parse, urllib.error, stat, re, secrets

MAX_BYTES = 524288
TIMEOUT = 10
APP_TOKEN_MAX = 256

def fail(msg):
    print(f"fetch-air: {msg}", file=sys.stderr)
    sys.exit(1)

def validate_cache_path(p):
    home = os.environ.get("HOME") or str(pathlib.Path.home())
    exp = os.path.join(home, ".cache", "omarchy", "yerrr") + os.sep
    if not (p.startswith(exp) or p == os.path.join(home, ".cache", "omarchy", "yerrr", "air.json")):
        # allow any file under yerrr for flexibility
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
    uid = os.getuid(); home = os.environ.get("HOME") or str(pathlib.Path.home())
    p = pathlib.Path(parent_path)
    for cur in [p] + list(p.parents):
        cs = str(cur)
        if cs == home or cs.startswith(os.path.join(home, ".cache")):
            try:
                st2 = os.lstat(cs)
                if stat.S_ISLNK(st2.st_mode): fail(f"parent symlink: {cs}")
                if not stat.S_ISDIR(st2.st_mode): fail(f"parent not dir: {cs}")
                if st2.st_uid != uid: fail(f"parent not owned: {cs}")
                if st2.st_mode & (stat.S_IWGRP | stat.S_IWOTH): fail(f"parent writable: {cs}")
            except FileNotFoundError: continue
            except SystemExit: raise
            except Exception as e: fail(f"parent check {cur}: {e}")
        if cs == home: break

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
        try:
            st = os.stat(base, dir_fd=dir_fd, follow_symlinks=False)
            if stat.S_ISLNK(st.st_mode): fail(f"dest symlink: {path}")
            if not stat.S_ISREG(st.st_mode): fail(f"dest not regular: {path}")
            if st.st_uid != uid: fail(f"dest not owned: {path}")
            if st.st_mode & (stat.S_IWGRP | stat.S_IWOTH): fail(f"dest writable: {path}")
        except FileNotFoundError: pass
        tmp = f".yerrr-tmp-{secrets.token_hex(8)}"
        try: fd = os.open(tmp, os.O_CREAT|os.O_EXCL|os.O_RDWR|os.O_NOFOLLOW, 0o600, dir_fd=dir_fd)
        except Exception as e: fail(f"create tmp failed: {e}")
        try:
            n = os.write(fd, data_bytes)
            if n != len(data_bytes): fail("short write")
            os.fsync(fd); os.close(fd); fd=-1
            try:
                st2 = os.stat(tmp, dir_fd=dir_fd, follow_symlinks=False)
                if not stat.S_ISREG(st2.st_mode) or stat.S_ISLNK(st2.st_mode): fail("tmp not regular")
                if st2.st_uid != uid: fail("tmp not owned")
                if st2.st_mode & (stat.S_IWGRP | stat.S_IWOTH): fail("tmp writable")
            except Exception as e: fail(f"tmp check: {e}")
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
        fail(f"fetch failed {url}: {e}")

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
    url = "https://data.cityofnewyork.us/resource/c3uy-2p5r.json?$limit=" + str(lim) + "&$order=sample_date%20DESC"
    # Add app token as query if needed? Socrata uses header, not query
    try:
        raw = fetch_url(url, token)
        try:
            j = json.loads(raw.decode('utf-8'))
            if not isinstance(j, list): fail("not list")
        except Exception as e:
            fail(f"json parse failed: {e}")
        atomic_write(cache, raw)
        print(f"wrote {cache} {len(j)} records")
        return
    except SystemExit:
        raise
    except Exception as e:
        print(f"fetch failed {e}, writing mock", file=sys.stderr)
        mock = [{"site_id":"1","borough":"Brooklyn","aqi":42}]
        atomic_write(cache, __import__('json').dumps(mock).encode())
        print(f"wrote {cache} {len(mock)} mock")

if __name__ == "__main__":
    main()
