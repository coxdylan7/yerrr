#!/usr/bin/python3
"""Secure Citi Bike GBFS fetch."""
import sys, os, json, pathlib, urllib.request, stat, secrets
MAX_BYTES = 512*1024
TIMEOUT = 10
def fail(msg):
    print(f"fetch-citi: {msg}", file=sys.stderr)
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
    try: pathlib.Path(parent).mkdir(parents=True, exist_ok=True); os.chmod(parent,0o700)
    except Exception as e: fail(f"mkdir {e}")
    try: dir_fd=os.open(parent, os.O_DIRECTORY|os.O_NOFOLLOW)
    except Exception as e: fail(f"open parent {e}")
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
            except TypeError: os.rename(os.path.join(parent,tmp), path)
            tmp=None
            try: os.chmod(base,0o600, dir_fd=dir_fd)
            except: os.chmod(path,0o600)
        finally:
            if fd>=0:
                try: os.close(fd)
                except: pass
            if tmp is not None:
                try: os.unlink(tmp, dir_fd=dir_fd)
                except: pass
                try: os.unlink(os.path.join(parent,tmp))
                except: pass
    finally:
        try: os.close(dir_fd)
        except: pass
def main():
    if len(sys.argv)!=2: fail(f"usage: {sys.argv[0]} <cache>")
    cache=sys.argv[1]
    validate_cache_path(cache)
    url="https://gbfs.citibikenyc.com/gbfs/en/station_status.json"
    req=urllib.request.Request(url, headers={"User-Agent":"yerrr/0.1.0"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        raw=resp.read(MAX_BYTES+1)
        if len(raw)>MAX_BYTES: fail("exceeds cap")
        j=json.loads(raw.decode())
        stations=j.get("data",{}).get("stations",[])
        # Keep only needed fields and truncate
        out=[]
        for s in stations[:800]:
            out.append({"station_id":s.get("station_id"),"num_bikes_available":s.get("num_bikes_available"),"num_docks_available":s.get("num_docks_available"),"is_installed":s.get("is_installed"),"is_renting":s.get("is_renting")})
        data=json.dumps(out).encode()
        atomic_write(cache, data)
        print(f"wrote {cache} {len(out)}")
if __name__=="__main__": main()
