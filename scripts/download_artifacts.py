#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import sys
import json
import io
import zipfile
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

class NoAuthRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new_req = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new_req and ('blob.core.windows.net' in newurl or 'actionsusercontent' in newurl):
            new_req.headers.pop('Authorization', None)
            new_req.headers.pop('authorization', None)
        return new_req

opener = urllib.request.build_opener(NoAuthRedirect)

RUN_ID = 39890515048
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

url = f"https://api.github.com/repos/{REPO}/actions/runs/{RUN_ID}/artifacts"
req = urllib.request.Request(url, headers=HEADERS)
with opener.open(req) as resp:
    data = json.loads(resp.read().decode('utf-8'))

for art in data.get("artifacts", []):
    name = art["name"]
    dl_url = art["archive_download_url"]
    size_mb = round(art.get("size_in_bytes", 0) / (1024 * 1024), 2)
    print(f"[*] Downloading {name} ({size_mb} MB)...")
    
    dl_req = urllib.request.Request(dl_url, headers=HEADERS)
    with opener.open(dl_req, timeout=300) as r:
        zip_bytes = r.read()
    
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as z:
        target = DIST_MAC if name == "TianheNetwork_v3.0.8_macOS" else AUDIT_MAC
        z.extractall(target)
        print(f"    ✅ Extracted {name} to {target}")

print("\n🎉 ALL ARTIFACTS DOWNLOADED AND EXTRACTED SUCCESSFULLY!")
