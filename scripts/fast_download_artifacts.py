#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import sys
import time
import zipfile
import requests
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

TOKEN = "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"
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "User-Agent": "TianheCI",
    "Accept": "application/vnd.github+json"
}

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DIST_MAC = PROJECT_ROOT / "dist_mac"
AUDIT_MAC = PROJECT_ROOT / "docs" / "audit_mac"
DIST_MAC.mkdir(parents=True, exist_ok=True)
AUDIT_MAC.mkdir(parents=True, exist_ok=True)

artifacts = [
    ("mac-acceptance-evidence", "https://api.github.com/repos/passerby7890/MyClashClient/actions/artifacts/13491948242/zip", AUDIT_MAC),
    ("TianheNetwork_v3.1.0_macOS", "https://api.github.com/repos/passerby7890/MyClashClient/actions/artifacts/13491973100/zip", DIST_MAC)
]

def download_resumable(name, api_url, target_dir):
    zip_path = PROJECT_ROOT / f"{name}.zip"
    
    # 步驟 1: 取得 Blob URL
    print(f"\n[*] 正在解析 {name} 下載位置...")
    blob_url = None
    r_init = requests.get(api_url, headers=HEADERS, allow_redirects=False, timeout=30)
    if r_init.status_code in (301, 302):
        blob_url = r_init.headers.get('Location')
    else:
        # requests 自動重定向後的 url
        r_full = requests.get(api_url, headers=HEADERS, stream=True, timeout=30)
        blob_url = r_full.url
        r_full.close()
    
    if not blob_url:
        raise RuntimeError(f"無法取得 {name} 之下載 URL")

    # 步驟 2: 取得總長度
    h_resp = requests.head(blob_url, timeout=30)
    total_len = int(h_resp.headers.get('content-length', 0))
    total_mb = round(total_len / (1024 * 1024), 2)
    print(f"[*] 開始斷點續傳下載: {name} (總大小: {total_mb} MB)...")

    max_retries = 20
    retry = 0

    while retry < max_retries:
        downloaded = zip_path.stat().st_size if zip_path.exists() else 0
        if total_len > 0 and downloaded >= total_len:
            print(f"\n    ✅ 下載完成 (已達 {downloaded} bytes)")
            break

        headers = {}
        if downloaded > 0:
            headers['Range'] = f"bytes={downloaded}-"
            print(f"\n    ⚡ 觸發斷點續傳：從 {round(downloaded/(1024*1024),2)} MB 開始繼續下載...")

        try:
            with requests.get(blob_url, headers=headers, stream=True, timeout=(15, 60)) as resp:
                if resp.status_code not in (200, 206):
                    print(f"\n    [WARN] HTTP {resp.status_code}，重置下載連結並重試...")
                    # 重新從 GitHub 獲取新的 Blob 簽名 URL (防止過期)
                    r_ref = requests.get(api_url, headers=HEADERS, allow_redirects=False, timeout=30)
                    if r_ref.status_code in (301, 302):
                        blob_url = r_ref.headers.get('Location')
                    retry += 1
                    time.sleep(2)
                    continue

                with open(zip_path, 'ab' if downloaded > 0 else 'wb') as f:
                    for chunk in resp.iter_content(chunk_size=1024 * 64):
                        if chunk:
                            f.write(chunk)
                            downloaded += len(chunk)
                            pct = round(downloaded / total_len * 100, 1) if total_len else 0
                            mb = round(downloaded / (1024 * 1024), 2)
                            print(f"\r    -> 已下載: {mb} / {total_mb} MB ({pct}%)", end='', flush=True)

            if total_len > 0 and downloaded >= total_len:
                print(f"\n    ✅ {name} 下載完畢！")
                break

        except (requests.exceptions.RequestException, Exception) as e:
            retry += 1
            print(f"\n    [WARN] 連線波動 ({e})，進行第 {retry}/{max_retries} 次自動重試...")
            time.sleep(2)

    # 步驟 3: 解壓縮至目標目錄
    print(f"    📦 解壓 {name}.zip 至 {target_dir}...")
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(target_dir)
    print(f"    ✅ 完成解壓: {name}")
    try:
        zip_path.unlink()
    except Exception:
        pass

for name, url, target_dir in artifacts:
    download_resumable(name, url, target_dir)

print("\n🎉 全部 macOS 實機產物已成功下載並歸檔！")

# 自動同步至 [打包上傳]
sync_script = PROJECT_ROOT.parent / "scripts" / "sync_release_to_upload.py"
if sync_script.exists():
    print("\n[SYNC] 正在自動同步至 [打包上傳] 資料夾...")
    import subprocess
    subprocess.run([sys.executable, str(sync_script)])
