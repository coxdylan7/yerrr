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
"""Secure MTA subway fetch — best-effort, byte capped, atomic nofollow."""
import sys, os, json, pathlib, urllib.request, stat, secrets, re, time
MAX_BYTES = 256*1024
MAX_FEED = 5*1024*1024
TIMEOUT = 8
def fail(msg):
    print(f"fetch-mta: {msg}", file=sys.stderr)
    sys.exit(1)
def validate_cache_path(p):
    home=os.environ.get("HOME") or str(pathlib.Path.home())
    exp=os.path.join(home, ".cache","omarchy","yerrr")+os.sep
    if not p.startswith(exp): fail(f"cache must be under {exp}")
    if ".." in pathlib.Path(p).parts or "\n" in p or "\r" in p: fail("invalid path")
    return p
def ensure_parent_secure_pinned(parent_fd, parent_path):
    try: st=os.fstat(parent_fd)
    except Exception as e: fail(f"fstat failed {e}")
    if not stat.S_ISDIR(st.st_mode): fail("not dir")
    if stat.S_ISLNK(st.st_mode): fail("symlink")
    if st.st_uid!=os.getuid(): fail("not owned")
    if st.st_mode & (stat.S_IWGRP|stat.S_IWOTH): fail("writable")
    uid=os.getuid(); home=os.environ.get("HOME") or str(pathlib.Path.home())
    p=pathlib.Path(parent_path)
    for cur in [p]+list(p.parents):
        cs=str(cur)
        if cs==home or cs.startswith(os.path.join(home,".cache")):
            try:
                st2=os.lstat(cs)
                if stat.S_ISLNK(st2.st_mode): fail(f"symlink {cs}")
                if not stat.S_ISDIR(st2.st_mode): fail(f"not dir {cs}")
                if st2.st_uid!=uid: fail(f"not owned {cs}")
                if st2.st_mode & (stat.S_IWGRP|stat.S_IWOTH): fail(f"writable {cs}")
            except FileNotFoundError: continue
            except SystemExit: raise
            except Exception as e: fail(f"parent check {e}")
        if cs==home: break
def atomic_write(path, data_bytes):
    parent=os.path.dirname(path); base=os.path.basename(path)
    home=os.environ.get("HOME") or str(pathlib.Path.home())
    home_fd=open_trusted_base(home)
    try:
        dir_fd=ensure_parent_descriptor_relative(home_fd, home, parent)
        try: os.fchmod(dir_fd, 0o700)
        except Exception as e: fail(f"fchmod parent failed: {e}")
    except Exception as e:
        try: os.close(home_fd)
        except: pass
        fail(f"ensure parent failed: {e}")
    try:
        ensure_parent_secure_pinned(dir_fd, parent)
        uid=os.getuid()
        try:
            st=os.stat(base, dir_fd=dir_fd, follow_symlinks=False)
            if stat.S_ISLNK(st.st_mode): fail("dest symlink")
            if not stat.S_ISREG(st.st_mode): fail("not regular")
            if st.st_uid!=uid: fail("not owned")
            if st.st_mode & (stat.S_IWGRP|stat.S_IWOTH): fail("writable")
        except FileNotFoundError: pass
        tmp=f".yerrr-tmp-{secrets.token_hex(8)}"
        try: fd=os.open(tmp, os.O_CREAT|os.O_EXCL|os.O_RDWR|os.O_NOFOLLOW, 0o600, dir_fd=dir_fd)
        except Exception as e: fail(f"tmp create {e}")
        try:
            n=os.write(fd, data_bytes)
            if n!=len(data_bytes): fail("short write")
            os.fsync(fd); os.close(fd); fd=-1
            try:
                st2=os.stat(tmp, dir_fd=dir_fd, follow_symlinks=False)
                if not stat.S_ISREG(st2.st_mode) or stat.S_ISLNK(st2.st_mode): fail("tmp not regular")
                if st2.st_uid!=uid: fail("not owned")
                if st2.st_mode & (stat.S_IWGRP|stat.S_IWOTH): fail("writable")
            except Exception as e: fail(f"tmp check {e}")
            try: os.rename(tmp, base, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
            except TypeError as e: fail(f"rename with dir_fd not supported, failing closed: {e}")
            except Exception as e: fail(f"rename failed: {e}")
            tmp=None
            try: os.chmod(base,0o600, dir_fd=dir_fd)
            except Exception as e: fail(f"chmod final failed: {e}")
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

def load_cached(cache, mock):
    try:
        d = os.path.dirname(cache); b = os.path.basename(cache)
        dir_fd = os.open(d, os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            fd2 = os.open(b, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd)
            try:
                data = os.read(fd2, MAX_BYTES + 1)
                if len(data) > MAX_BYTES:
                    raise ValueError("exceeds cap")
                j = json.loads(data.decode("utf-8"))
                if isinstance(j, list) and len(j) > 0:
                    return j
            finally:
                os.close(fd2)
        finally:
            os.close(dir_fd)
    except Exception: pass
    return list(mock)

LINES = ["1","2","3","4","5","6","7","A","B","C","D","E","F","G","J","L","M","N","Q","R","S","W","Z","SIR","GS"]

def _read_varint(buf, off):
    result = 0
    shift = 0
    while off < len(buf):
        b = buf[off]; off += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            break
        shift += 7
    return result, off

def _walk(buf, off, end):
    while off < end:
        key, off = _read_varint(buf, off)
        f = key >> 3
        w = key & 7
        if w == 0:
            v, off = _read_varint(buf, off)
            yield f, w, v
        elif w == 2:
            ln, off = _read_varint(buf, off)
            yield f, w, (off, off + ln)
            off += ln
        elif w == 1:
            yield f, w, off
            off += 8
        elif w == 5:
            yield f, w, off
            off += 4
        else:
            return

def _translation_text(data, s, e):
    for f, w, v in _walk(data, s, e):
        if f == 1 and w == 2:
            ts, te = v
            for f2, w2, v2 in _walk(data, ts, te):
                if f2 == 1 and w2 == 2:
                    st, en = v2
                    return data[st:en].decode("utf-8", "replace")
    return ""

def _status_from_header(h):
    hl = h.lower()
    if "no late night" in hl or " no " in hl or "no service" in hl or " ends early" in hl: return "No service"
    if "delay" in hl: return "Significant delays"
    if "skip" in hl: return "Skip-stop"
    if "restored" in hl: return "Service restored"
    if "maintenance" in hl: return "Planned work"
    if "express" in hl: return "Express service"
    if "overnight" in hl or "late night" in hl or "every 10 minutes" in hl: return "Reduced service"
    return "Service change"

def parse_alerts(data):
    routes = {}
    for f, w, v in _walk(data, 0, len(data)):
        if f != 2 or w != 2:
            continue
        st, en = v
        for f2, w2, v2 in _walk(data, st, en):
            if f2 != 5 or w2 != 2:
                continue
            ast, aen = v2
            al_routes = []
            header = ""
            for f3, w3, v3 in _walk(data, ast, aen):
                if f3 == 5 and w3 == 2:
                    ies, iee = v3
                    for f4, w4, v4 in _walk(data, ies, iee):
                        if f4 == 2 and w4 == 2:
                            rs, re = v4
                            r = data[rs:re].decode("utf-8", "replace")
                            if r in LINES and r not in al_routes:
                                al_routes.append(r)
                elif f3 == 10 and w3 == 2 and not header:
                    header = _translation_text(data, v3[0], v3[1])
            if not header:
                continue
            for rline in al_routes:
                if rline not in routes:
                    routes[rline] = header
    return routes

def main():
    if len(sys.argv)!=2: fail(f"usage: {sys.argv[0]} <cache>")
    cache=sys.argv[1]
    validate_cache_path(cache)
    url = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/camsys%2Fsubway-alerts"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (yerrr)"})
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read(MAX_FEED + 1)
            if len(raw) > MAX_FEED:
                raise RuntimeError("feed too large")
        alerts = parse_alerts(raw)
        now = int(time.time())
        out = []
        for line in LINES:
            h = alerts.get(line, "")
            h = re.sub(r"<[^>]+>", " ", h)
            h = re.sub(r"\s+", " ", h).strip()
            if h:
                out.append({"line": line, "status": _status_from_header(h), "delayMin": 0, "cause": h[:220], "updated": now})
            else:
                out.append({"line": line, "status": "Good service", "delayMin": 0, "cause": "", "updated": now})
        data = json.dumps(out).encode()
        atomic_write(cache, data)
        print(json.dumps(out, separators=(',',':')))
        return
    except SystemExit:
        raise
    except Exception as e:
        print(f"fetch failed {e}, serving last-known cache", file=sys.stderr)
        fallback = load_cached(cache, [])
        if not fallback:
            fallback = [{"line": l, "status": "Good service", "delayMin": 0, "cause": "", "updated": 0} for l in LINES]
        atomic_write(cache, json.dumps(fallback, separators=(',',':')).encode())
        print(json.dumps(fallback, separators=(',',':')))
if __name__=="__main__": main()
