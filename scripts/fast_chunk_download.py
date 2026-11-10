import os
import sys
import time
import requests
import zipfile
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.stdout.reconfigure(encoding='utf-8')

TOKEN = "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"
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "User-Agent": "TianheCI",
    "Accept": "application/vnd.github+json"
}

API_URL = "https://api.github.com/repos/passerby7890/MyClashClient/actions/artifacts/13681386089/zip"
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DIST_MAC = PROJECT_ROOT / "dist_mac"
DIST_MAC.mkdir(parents=True, exist_ok=True)
OUT_ZIP = PROJECT_ROOT / "TianheNetwork_v3.3.1_macOS.zip"

session = requests.Session()
session.trust_env = False

print("[1/4] Resolving Azure Blob URL from GitHub API...")
r = session.get(API_URL, headers=HEADERS, allow_redirects=False, timeout=30)
if r.status_code in (301, 302, 303):
    blob_url = r.headers.get("Location")
else:
    r_full = session.get(API_URL, headers=HEADERS, stream=True, timeout=30)
    blob_url = r_full.url
    r_full.close()

print(f"Blob URL resolved: {blob_url[:80]}...")

head_resp = session.head(blob_url, timeout=30)
total_bytes = int(head_resp.headers.get("Content-Length", 0))
total_mb = round(total_bytes / (1024 * 1024), 2)
print(f"[2/4] File size: {total_bytes} bytes ({total_mb} MB). Preparing 16 parallel chunks...")

NUM_THREADS = 16
chunk_size = total_bytes // NUM_THREADS
chunks = []
for i in range(NUM_THREADS):
    start = i * chunk_size
    end = total_bytes - 1 if i == NUM_THREADS - 1 else (i + 1) * chunk_size - 1
    chunks.append((i, start, end))

temp_part_files = [PROJECT_ROOT / f"part_{i}.bin" for i in range(NUM_THREADS)]

def download_chunk(item):
    idx, start, end = item
    part_path = temp_part_files[idx]
    chunk_headers = {"Range": f"bytes={start}-{end}"}
    s = requests.Session()
    s.trust_env = False
    for attempt in range(5):
        try:
            with s.get(blob_url, headers=chunk_headers, stream=True, timeout=60) as resp:
                resp.raise_for_status()
                with open(part_path, "wb") as pf:
                    for c in resp.iter_content(chunk_size=64 * 1024):
                        if c:
                            pf.write(c)
            return idx, True
        except Exception as e:
            time.sleep(1 + attempt)
    return idx, False

print("[3/4] Downloading chunks concurrently...")
t0 = time.time()
with ThreadPoolExecutor(max_workers=NUM_THREADS) as executor:
    futures = [executor.submit(download_chunk, c) for c in chunks]
    completed = 0
    for f in as_completed(futures):
        idx, ok = f.result()
        completed += 1
        pct = round(completed / NUM_THREADS * 100, 1)
        elapsed = round(time.time() - t0, 1)
        print(f"\r  -> Progress: {completed}/{NUM_THREADS} chunks ({pct}%) in {elapsed}s", end="", flush=True)

print(f"\n[4/4] Assembling parts into {OUT_ZIP}...")
with open(OUT_ZIP, "wb") as out_f:
    for p in temp_part_files:
        if p.exists():
            with open(p, "rb") as pf:
                while True:
                    buf = pf.read(1024 * 1024)
                    if not buf:
                        break
                    out_f.write(buf)
            p.unlink(missing_ok=True)

print(f"Extraction to {DIST_MAC}...")
with zipfile.ZipFile(OUT_ZIP) as zf:
    zf.extractall(DIST_MAC)

OUT_ZIP.unlink(missing_ok=True)
print("DMG download and extraction successfully completed!")

sync_script = PROJECT_ROOT.parent / "scripts" / "sync_release_to_upload.py"
if sync_script.exists():
    import subprocess
    print("Running sync_release_to_upload.py...")
    subprocess.run([sys.executable, str(sync_script)])
