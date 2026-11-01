#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
監控 GitHub Actions macOS CI 運行狀態，並在完成後自動下載產物 (TianheNetwork macOS DMG & 驗收日誌)
"""

import os
import sys
import time
import json
import zipfile
import io
import urllib.request
import urllib.error
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

REPO = "passerby7890/MyClashClient"
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

class NoAuthRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new_req = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new_req and ('blob.core.windows.net' in newurl or 'actionsusercontent' in newurl):
            new_req.headers.pop('Authorization', None)
            new_req.headers.pop('authorization', None)
        return new_req

opener = urllib.request.build_opener(NoAuthRedirect)

def api_get(endpoint):
    url = f"https://api.github.com/repos/{REPO}/{endpoint}" if not endpoint.startswith("http") else endpoint
    req = urllib.request.Request(url, headers=HEADERS)
    with opener.open(req, timeout=30) as resp:
        return json.loads(resp.read().decode('utf-8'))

def get_latest_run_id():
    runs_data = api_get("actions/runs?per_page=5")
    runs = runs_data.get("workflow_runs", [])
    if runs:
        return runs[0]["id"]
    return None

run_id = None
if len(sys.argv) > 1 and sys.argv[1].isdigit():
    run_id = int(sys.argv[1])
else:
    print("[*] 正在查詢 GitHub Actions 最新觸發的 Run ID...")
    for _ in range(12):
        run_id = get_latest_run_id()
        if run_id:
            break
        time.sleep(5)

if not run_id:
    print("[!] 無法獲取 Run ID，請確認 GitHub Actions 是否已被觸發")
    sys.exit(1)

print(f"[*] 開始監控 GitHub Actions Run ID: {run_id}")
last_step_name = ""

while True:
    try:
        run_data = api_get(f"actions/runs/{run_id}")
        status = run_data.get("status")
        conclusion = run_data.get("conclusion")
        html_url = run_data.get("html_url", "")
        
        # 查詢目前執行中之 step
        try:
            jobs_data = api_get(f"actions/runs/{run_id}/jobs")
            for j in jobs_data.get("jobs", []):
                for s in j.get("steps", []):
                    if s.get("status") == "in_progress":
                        curr_step = s.get("name")
                        if curr_step != last_step_name:
                            print(f"  [RUNNING] 目前步驟 -> {curr_step}")
                            last_step_name = curr_step
        except Exception:
            pass

        if status == "completed":
            print(f"\n[+] GitHub Actions 構建與全套驗收完成！總判定: {conclusion}")
            print(f"    URL: {html_url}")
            if conclusion == "success":
                print("[*] 正在查詢並下載構建產物 Artifacts...")
                arts_data = api_get(f"actions/runs/{run_id}/artifacts")
                for art in arts_data.get("artifacts", []):
                    name = art.get("name")
                    dl_url = art.get("archive_download_url")
                    size_mb = round(art.get("size_in_bytes", 0) / (1024 * 1024), 2)
                    print(f"  -> 下載產物: {name} ({size_mb} MB)...")
                    
                    zip_bytes_stream = io.BytesIO()
                    req = urllib.request.Request(dl_url, headers=HEADERS)
                    with opener.open(req, timeout=300) as resp:
                        zip_bytes_stream.write(resp.read())
                    
                    zip_bytes_stream.seek(0)
                    with zipfile.ZipFile(zip_bytes_stream) as zf:
                        if "macOS" in name or name.startswith("TianheNetwork"):
                            zf.extractall(DIST_MAC)
                            print(f"     ✅ 解壓至: {DIST_MAC}")
                        elif name == "mac-acceptance-evidence":
                            zf.extractall(AUDIT_MAC)
                            print(f"     ✅ 解壓至: {AUDIT_MAC}")
                        else:
                            zf.extractall(AUDIT_MAC / name)
                            print(f"     ✅ 解壓至: {AUDIT_MAC / name}")
                
                print("\n[SUCCESS] 全部 macOS 實機產物已下載歸檔完畢！")
                sys.exit(0)
            else:
                print(f"\n[ERROR] 構建失敗 (conclusion: {conclusion})，請檢查失敗日誌！")
                sys.exit(1)

    except Exception as e:
        print(f"  [WARN] 輪詢異常: {e}")

    time.sleep(25)
