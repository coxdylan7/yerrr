#!/usr/bin/python3
"""Secure write-config — set/clear locationOverride keys for a plugin entry in shell.json.
Usage: write-config.py <shellJsonPath> <pluginId> <latOrCLEAR> <lonOrCLEAR>
argv-only, descriptor-relative, capped reads, atomic nofollow writes. JSON printed to stdout.
"""
import sys, os, json, pathlib, stat, secrets

MAX_BYTES = 5242880
CONFIG_PREFIX = ".config" + os.sep + "omarchy" + os.sep

def fail(msg):
    print(f"write-config: {msg}", file=sys.stderr)
    sys.exit(1)

def open_trusted_base(home_path):
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
    if not parent_path.startswith(home_path + os.sep):
        fail(f"parent not under HOME: {parent_path}")
    rel = os.path.relpath(parent_path, home_path)
    parts = rel.split(os.sep)
    cur_fd = os.dup(home_fd)
    cur_path = home_path
    for comp in parts:
        if not comp or comp == ".":
            continue
        if comp == ".." or "/" in comp or "\n" in comp or "\0" in comp:
            try: os.close(cur_fd)
            except: pass
            fail(f"invalid component: {comp}")
        try:
            next_fd = os.open(comp, os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=cur_fd)
            st = os.fstat(next_fd)
            if not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode):
                try: os.close(next_fd)
                except: pass
                try: os.close(cur_fd)
                except: pass
                fail(f"component invalid: {os.path.join(cur_path, comp)}")
            if st.st_uid != os.getuid() or st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
                try: os.close(next_fd)
                except: pass
                try: os.close(cur_fd)
                except: pass
                fail(f"component not owned/writable: {os.path.join(cur_path, comp)}")
            try: os.close(cur_fd)
            except: pass
            cur_fd = next_fd
            cur_path = os.path.join(cur_path, comp)
        except OSError as e:
            try: os.close(cur_fd)
            except: pass
            fail(f"open component failed {os.path.join(cur_path, comp)}: {e}")
    return cur_fd

def validate_shell_path(p):
    home = os.environ.get("HOME") or str(pathlib.Path.home())
    exp = os.path.join(home, ".config", "omarchy") + os.sep
    if not p.startswith(exp):
        fail(f"shell.json must be under {exp}")
    if ".." in pathlib.Path(p).parts or "\n" in p or "\r" in p or "\x00" in p:
        fail("invalid shell path")
    return p

def read_json_descriptor_relative(home_fd, home_path, parent_dir, base):
    dir_fd = ensure_parent_descriptor_relative(home_fd, home_path, parent_dir)
    try:
        try:
            fd = os.open(base, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd)
        except FileNotFoundError:
            return None
        try:
            data = os.read(fd, MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                fail("shell.json exceeds cap")
            return json.loads(data.decode('utf-8'))
        finally:
            os.close(fd)
    finally:
        try: os.close(dir_fd)
        except: pass

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
        try:
            st = os.fstat(dir_fd)
            if st.st_uid != os.getuid() or st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
                fail("parent not owned/writable")
        except Exception as e:
            fail(f"fstat parent failed: {e}")
        uid = os.getuid()
        tmp = f".yerrr-tmp-{secrets.token_hex(8)}"
        try: fd = os.open(tmp, os.O_CREAT|os.O_EXCL|os.O_RDWR|os.O_NOFOLLOW, 0o600, dir_fd=dir_fd)
        except Exception as e: fail(f"create tmp failed: {e}")
        try:
            n = os.write(fd, data_bytes)
            if n != len(data_bytes): fail("short write")
            os.fsync(fd); os.close(fd); fd = -1
            try: os.rename(tmp, base, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
            except Exception as e: fail(f"rename failed: {e}")
            tmp = None
            try: os.chmod(base, 0o600, dir_fd=dir_fd)
            except Exception as e: fail(f"chmod final failed: {e}")
        finally:
            if fd >= 0:
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

def main():
    if len(sys.argv) != 5:
        fail(f"usage: {sys.argv[0]} <shellJsonPath> <pluginId> <latOrCLEAR> <lonOrCLEAR>")
    shell = sys.argv[1]
    plugin = sys.argv[2]
    lat = sys.argv[3]
    lon = sys.argv[4]
    validate_shell_path(shell)
    if not plugin or len(plugin) > 64 or any(c in plugin for c in ["\n","\r","\0","/","\\"]):
        fail("invalid plugin id")

    def parse_num(s, name):
        if s == "CLEAR": return "CLEAR"
        try:
            n = float(s)
        except Exception:
            fail(f"{name} not numeric: {s}")
        if not (-90 <= n <= 90 if name == "lat" else -180 <= n <= 180):
            fail(f"{name} out of range: {s}")
        return n

    pl = parse_num(lat, "lat")
    plon = parse_num(lon, "lon")

    home = os.environ.get("HOME") or str(pathlib.Path.home())
    home_fd = open_trusted_base(home)
    try:
        cfg = read_json_descriptor_relative(home_fd, home, os.path.dirname(shell), os.path.basename(shell))
    finally:
        try: os.close(home_fd)
        except: pass

    if cfg is None:
        cfg = {"version": 1, "plugins": []}
    if not isinstance(cfg, dict):
        fail("shell.json root not object")
    if cfg.get("plugins") is None:
        cfg["plugins"] = []
    plugins = cfg["plugins"]
    if not isinstance(plugins, list):
        fail("plugins not list")
    entry = None
    for p_ in plugins:
        if isinstance(p_, dict) and str(p_.get("id") or "") == plugin:
            entry = p_
            break
    if entry is None:
        entry = {"id": plugin}
        plugins.append(entry)
    if pl == "CLEAR" or plon == "CLEAR":
        entry.pop("locationOverrideLat", None)
        entry.pop("locationOverrideLon", None)
    else:
        entry["locationOverrideLat"] = str(pl)
        entry["locationOverrideLon"] = str(plon)
    try:
        out = json.dumps(cfg, indent=2).encode('utf-8')
    except Exception as e:
        fail(f"serialize failed: {e}")
    if len(out) > MAX_BYTES:
        fail("shell.json exceeds cap")
    atomic_write(shell, out)
    print(json.dumps({"plugin": plugin, "lat": "CLEAR" if pl == "CLEAR" else str(pl), "lon": "CLEAR" if plon == "CLEAR" else str(plon)}))

if __name__ == "__main__":
    main()