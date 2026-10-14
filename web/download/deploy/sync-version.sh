#!/bin/sh
# 把 honghong-releases 的公开 version.json 和对应 APK 同步到分发页目录。只读公开地址，不需要任何密钥。
#   data/version.json           : 原样加上 channels.<渠道>.localApkUrl（本站 APK 校验通过才写）
#   files/<渠道>/<apkName>      : 本站 APK，每个渠道保留最近 KEEP 个
# 用法（nc_am 宿主机 root crontab）：
#   */5 * * * * /opt/honghong-download/sync-version.sh >> /opt/honghong-download/sync.log 2>&1
# 可用环境变量覆盖：HH_DL_ROOT（默认站点下的 download 目录）、HH_SRC、HH_KEEP（默认 3）、HH_MIN_FREE_MB（默认 2048）
set -eu
export HH_DL_ROOT="${HH_DL_ROOT:-/opt/1panel/www/sites/honghong.hczhw.com/download}"
export HH_SRC="${HH_SRC:-https://raw.githubusercontent.com/JiHe021499/honghong-releases/main/version.json}"
export HH_KEEP="${HH_KEEP:-3}"
export HH_MIN_FREE_MB="${HH_MIN_FREE_MB:-2048}"
exec python3 - <<'PY'
import fcntl, hashlib, json, os, re, shutil, sys, tempfile, time, urllib.request

ROOT = os.environ["HH_DL_ROOT"]; SRC = os.environ["HH_SRC"]
KEEP = max(1, int(os.environ["HH_KEEP"])); MIN_FREE = int(os.environ["HH_MIN_FREE_MB"]) * 1048576
APK_PREFIX = "https://github.com/JiHe021499/honghong-releases/releases/download/"
NAME_RE = re.compile(r"^honghong-[0-9A-Za-z.\-]+\.apk$")
CH_RE = re.compile(r"^[a-z]+$")
DATA = os.path.join(ROOT, "data"); FILES = os.path.join(ROOT, "files")

def log(*a): print(time.strftime("%F %T"), *a, flush=True)

def fetch(url, dst, timeout):
    req = urllib.request.Request(url, headers={"User-Agent": "honghong-download-sync"})
    with urllib.request.urlopen(req, timeout=timeout) as r, open(dst, "wb") as f:
        shutil.copyfileobj(r, f, 1 << 20)

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
    return h.hexdigest()

def write_atomic(path, data):
    d = os.path.dirname(path); os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=d)
    try:
        with os.fdopen(fd, "wb") as f: f.write(data)
        os.chmod(tmp, 0o644); os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp): os.unlink(tmp)
        raise

def ensure_apk(ch, e):
    """本站已有且校验过就直接用；否则下载到同目录临时文件，校验大小和 sha256 后原子替换。返回本站路径或 None。"""
    name, url, size, sha = e.get("apkName"), e.get("apkUrl"), e.get("size"), str(e.get("sha256", "")).lower()
    if not (isinstance(name, str) and NAME_RE.match(name) and isinstance(url, str) and url.startswith(APK_PREFIX)
            and isinstance(size, int) and size > 0 and re.fullmatch(r"[0-9a-f]{64}", sha)):
        log(f"[{ch}] 元数据不完整，跳过本站同步"); return None
    d = os.path.join(FILES, ch); os.makedirs(d, exist_ok=True)
    dst, mark = os.path.join(d, name), os.path.join(d, name + ".sha256")
    if os.path.isfile(dst) and os.path.getsize(dst) == size:
        try:
            if open(mark).read().strip() == sha: return dst
        except OSError: pass
        if sha256(dst) == sha:
            write_atomic(mark, (sha + "\n").encode()); return dst
    if shutil.disk_usage(d).free < size + MIN_FREE:
        log(f"[{ch}] 磁盘剩余不足，跳过下载 {name}"); return None
    fd, tmp = tempfile.mkstemp(prefix=".dl-", suffix=".part", dir=d); os.close(fd)
    try:
        fetch(url, tmp, 300)
        got_size, got_sha = os.path.getsize(tmp), sha256(tmp)
        if got_size != size or got_sha != sha:
            log(f"[{ch}] 校验失败 {name}：size {got_size}/{size} sha {got_sha[:12]}/{sha[:12]}"); return None
        os.chmod(tmp, 0o644); os.replace(tmp, dst)
        write_atomic(mark, (sha + "\n").encode())
        log(f"[{ch}] 已下载 {name}（{size} 字节，sha256 校验通过）"); return dst
    except Exception as ex:
        log(f"[{ch}] 下载失败 {name}：{ex}"); return None
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def prune(ch, current):
    d = os.path.join(FILES, ch)
    apks = sorted((p for p in (os.path.join(d, n) for n in os.listdir(d)) if p.endswith(".apk") and os.path.isfile(p)),
                  key=os.path.getmtime, reverse=True)
    keep = set(apks[:KEEP]); keep.add(current) if current else None
    for p in apks:
        if p not in keep:
            for q in (p, p + ".sha256"):
                if os.path.exists(q): os.unlink(q)
            log(f"[{ch}] 清理旧版本 {os.path.basename(p)}")
    for n in os.listdir(d):  # 清掉中断留下的临时文件（超过 1 小时）
        if n.startswith((".dl-", ".tmp-")) and time.time() - os.path.getmtime(os.path.join(d, n)) > 3600:
            os.unlink(os.path.join(d, n))

os.makedirs(DATA, exist_ok=True)
lock = open(os.path.join(DATA, ".sync.lock"), "w")
try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError: log("上一次同步还在进行，跳过"); sys.exit(0)

fd, tmp = tempfile.mkstemp(prefix=".src-", dir=DATA); os.close(fd)
try:
    fetch(SRC, tmp, 20)
    with open(tmp, "rb") as f: src = json.load(f)
finally:
    os.unlink(tmp)
if not isinstance(src.get("channels"), dict):
    log("version.json 缺少 channels，保留旧文件"); sys.exit(1)

out = json.loads(json.dumps(src))
out.pop("localApkUrl", None)
for e in out["channels"].values():
    if isinstance(e, dict): e.pop("localApkUrl", None)  # 只信本次校验结果
for ch, e in out["channels"].items():
    if not (CH_RE.match(ch) and isinstance(e, dict)): continue
    path = ensure_apk(ch, e)
    if path:
        e["localApkUrl"] = "/download/files/%s/%s" % (ch, os.path.basename(path))
        os.utime(path)  # 当前版本刷新 mtime，保证不会被清理
    prune(ch, path)
    if e.get("apkName") and e.get("apkName") == out.get("apkName") and e.get("channel") == out.get("channel") and path:
        out["localApkUrl"] = e["localApkUrl"]

data = (json.dumps(out, ensure_ascii=False, indent=2) + "\n").encode()
dst = os.path.join(DATA, "version.json")
try: old = open(dst, "rb").read()
except OSError: old = b""
if old != data:
    write_atomic(dst, data); log("version.json 已更新")
PY
