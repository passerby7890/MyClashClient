#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
快速下載 GitHub Actions v3.0.9 macOS DMG 產物與驗收日誌
"""

import os
import sys
import io
import json
import zipfile
import urllib.request
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

ARTIFACTS = [
    ("TianheNetwork_v3.0.9_macOS", "13027280699", DIST_MAC),
    ("mac-acceptance-evidence", "13027260771", AUDIT_MAC)
]

for name, art_id, target_dir in ARTIFACTS:
    url = f"https://api.github.com/repos/passerby7890/MyClashClient/actions/artifacts/{art_id}/zip"
    print(f"[*] 正在下載 {name} (ID: {art_id})...", flush=True)
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=180) as resp:
        content = resp.read()
    print(f"    下載完成 ({len(content)/(1024*1024):.2f} MB)，正在解壓縮至 {target_dir}...", flush=True)
    with zipfile.ZipFile(io.BytesIO(content)) as zf:
        zf.extractall(target_dir)
    print(f"    ✅ {name} 部署完成！", flush=True)

print("\n🎉 全部 macOS 產物已成功下載並解壓！")
for f in DIST_MAC.glob("*.dmg"):
    size_mb = os.path.getsize(f) / (1024 * 1024)
    print(f"  - DMG: {f.name} ({size_mb:.2f} MB)")

