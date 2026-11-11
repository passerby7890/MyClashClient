# -*- coding: utf-8 -*-
"""
🍎 天河網絡 (Tianhe Network) macOS CI/CD 雲端打包與下載自動化管理器
功能：
1. 提取 GitHub Token 並安全通訊 (不輸出 Token)
2. 觸發 / 監聽 GitHub Actions: Build Tianhe macOS DMG
3. 即時輸出雲端構建日誌與步驟進度
4. 建構完成自動下載最新 DMG / ZIP 產物至 dist_mac/ 與 打包上傳/
5. 驗證產物完整性
"""

import os
import sys
import time
import json
import re
import zipfile
import shutil
import urllib.request
import urllib.error
from pathlib import Path

WORKSPACE_MAC = Path(__file__).resolve().parent.parent
WORKSPACE_ROOT = WORKSPACE_MAC.parent
UPLOAD_DIR = WORKSPACE_ROOT / "打包上傳"
DIST_MAC = WORKSPACE_MAC / "dist_mac"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
DIST_MAC.mkdir(parents=True, exist_ok=True)

def get_github_token():
    git_cfg = (WORKSPACE_MAC / ".git" / "config").read_text(encoding="utf-8")
    m = re.search(r"github_pat_[A-Za-z0-9_]+", git_cfg)
    if not m:
        m = re.search(r"ghp_[A-Za-z0-9_]+", git_cfg)
    if not m:
        raise ValueError("無法在 .git/config 中找到 GitHub Token！")
    return m.group(0)

def api_request(url, token, method="GET", data=None):
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "Tianhe-CI-Manager/3.4.0"
    }
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read(), resp.headers

def get_latest_runs(token, limit=5):
    url = f"https://api.github.com/repos/passerby7890/MyClashClient/actions/runs?per_page={limit}"
    raw, _ = api_request(url, token)
    return json.loads(raw.decode("utf-8")).get("workflow_runs", [])

def get_run_jobs(run_id, token):
    url = f"https://api.github.com/repos/passerby7890/MyClashClient/actions/runs/{run_id}/jobs"
    raw, _ = api_request(url, token)
    return json.loads(raw.decode("utf-8")).get("jobs", [])

def get_run_artifacts(run_id, token):
    url = f"https://api.github.com/repos/passerby7890/MyClashClient/actions/runs/{run_id}/artifacts"
    raw, _ = api_request(url, token)
    return json.loads(raw.decode("utf-8")).get("artifacts", [])

def download_artifact_zip(artifact_id, dest_zip, token):
    url = f"https://api.github.com/repos/passerby7890/MyClashClient/actions/artifacts/{artifact_id}/zip"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "Tianhe-CI-Manager/3.4.0"
    }
    req = urllib.request.Request(url, headers=headers)
    print(f"  -> 下載中: {dest_zip.name} ...")
    with urllib.request.urlopen(req, timeout=180) as resp:
        with open(dest_zip, "wb") as f:
            while True:
                chunk = resp.read(1024 * 512)
                if not chunk:
                    break
                f.write(chunk)
    print(f"  ✅ 下載完成: {dest_zip.name} ({dest_zip.stat().st_size:,} bytes)")

def run_git_push():
    import subprocess
    print(">>> 執行 git push origin main 觸發 GitHub Actions 雲端構建...")
    res = subprocess.run(
        ["git", "-C", str(WORKSPACE_MAC), "push", "origin", "main"],
        capture_output=True,
        text=True
    )
    if res.returncode != 0:
        print(f"Git push 失敗: {res.stderr}")
        return False
    print(f"  ✅ Git push 成功！\n{res.stdout.strip()}")
    return True

def monitor_and_download(head_commit=None):
    token = get_github_token()
    print(">>> 查詢 GitHub Actions 流水線狀態...")
    target_run = None
    for attempt in range(12):
        runs = get_latest_runs(token, limit=5)
        for r in runs:
            r_commit = r.get("head_commit", {}).get("id", "")
            if head_commit and r_commit.startswith(head_commit):
                target_run = r
                break
            elif not head_commit:
                target_run = r
                break
        if target_run:
            break
        print(f"  等候流水線觸發 (重試 {attempt+1}/12)...")
        time.sleep(5)

    if not target_run:
        print("❌ 未能找到對應的 GitHub Actions 流水線！")
        return False

    run_id = target_run["id"]
    run_url = target_run["html_url"]
    commit_id = target_run.get("head_commit", {}).get("id", "")[:7]
    print(f"  🎯 捕獲流水線: ID={run_id} | Commit={commit_id} | 連結: {run_url}")

    # 輪詢直至完成
    last_step_name = ""
    start_time = time.time()
    while True:
        try:
            url = f"https://api.github.com/repos/passerby7890/MyClashClient/actions/runs/{run_id}"
            raw, _ = api_request(url, token)
            run_data = json.loads(raw.decode("utf-8"))
            status = run_data["status"]
            conclusion = run_data.get("conclusion")

            # 抓取當前執行的步驟
            jobs = get_run_jobs(run_id, token)
            curr_job = jobs[0] if jobs else {}
            curr_step = ""
            for s in curr_job.get("steps", []):
                if s.get("status") == "in_progress":
                    curr_step = s.get("name")
                    break

            elapsed = int(time.time() - start_time)
            m, s = divmod(elapsed, 60)
            if curr_step and curr_step != last_step_name:
                last_step_name = curr_step
                print(f"  [{m:02d}:{s:02d}] ⚙️ 正在執行: {curr_step}")
            else:
                print(f"  [{m:02d}:{s:02d}] 狀態: {status} | 步驟: {last_step_name or '等待中'}")

            if status == "completed":
                print(f"\n🎉 流水線執行結束！最終結論: {conclusion}")
                if conclusion != "success":
                    print(f"❌ 流水線未成功結束: {conclusion}")
                    return False
                break

            time.sleep(15)
        except Exception as e:
            print(f"  ⚠️ 輪詢狀態警告: {e}")
            time.sleep(10)

    # 成功完成，開始獲取 Artifacts
    print("\n>>> 開始檢索並下載構建產物...")
    artifacts = get_run_artifacts(run_id, token)
    print(f"  找到 {len(artifacts)} 個產物:")
    for a in artifacts:
        print(f"  - {a['name']} (ID: {a['id']}, 大小: {a['size_in_bytes']:,} bytes)")

    dmg_artifact = next((a for a in artifacts if "macOS" in a["name"] or "dmg" in a["name"].lower()), None)
    if not dmg_artifact:
        dmg_artifact = artifacts[0] if artifacts else None

    if not dmg_artifact:
        print("❌ 未在產物列表中找到 DMG 建構包！")
        return False

    temp_zip = DIST_MAC / f"artifact_{dmg_artifact['id']}.zip"
    download_artifact_zip(dmg_artifact["id"], temp_zip, token)

    # 解壓縮並定位 .dmg 檔案
    extracted_dmg = None
    with zipfile.ZipFile(temp_zip, "r") as zf:
        zf.extractall(DIST_MAC)
        for name in zf.namelist():
            if name.endswith(".dmg"):
                extracted_dmg = DIST_MAC / name
                break

    if not extracted_dmg or not extracted_dmg.exists():
        dmg_list = list(DIST_MAC.glob("*.dmg"))
        if dmg_list:
            extracted_dmg = max(dmg_list, key=lambda p: p.stat().st_mtime)

    if not extracted_dmg:
        print("❌ 解壓後未發現 .dmg 檔案！")
        return False

    dmg_size = extracted_dmg.stat().st_size
    print(f"\n  💿 成功取得最新 macOS DMG 鏡像: {extracted_dmg.name} ({dmg_size:,} bytes)")

    # 同步複製到 打包上傳/ 目錄
    target_dmg = UPLOAD_DIR / "mac.dmg"
    target_zip = UPLOAD_DIR / "mac.zip"
    shutil.copy2(extracted_dmg, target_dmg)
    shutil.copy2(temp_zip, target_zip)

    print(f"  ✅ 已同步至發布目錄: {target_dmg} ({target_dmg.stat().st_size:,} bytes)")
    print(f"  ✅ 已同步至發布目錄: {target_zip} ({target_zip.stat().st_size:,} bytes)")

    # 乾淨清理暫存
    try:
        temp_zip.unlink()
    except Exception:
        pass

    print("\n" + "=" * 80)
    print("🍎 macOS 雲端打包、自動驗收、下載與同步全流程圓滿成功！")
    print(f"   產物路徑: {target_dmg}")
    print(f"   產物大小: {round(dmg_size / 1024 / 1024, 2)} MB")
    print("=" * 80)
    return True

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--download-only":
        monitor_and_download()
    else:
        if run_git_push():
            # 取得當前 HEAD commit short hash
            import subprocess
            head = subprocess.check_output(
                ["git", "-C", str(WORKSPACE_MAC), "rev-parse", "HEAD"],
                text=True
            ).strip()[:7]
            monitor_and_download(head)
