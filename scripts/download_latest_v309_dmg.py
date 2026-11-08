import os
import sys
import io
import json
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
    ("TianheNetwork_v3.0.9_macOS", "13106007600", DIST_MAC),
    ("mac-acceptance-evidence", "13106032503", AUDIT_MAC)
]

for name, art_id, target_dir in ARTIFACTS:
    url = f"https://api.github.com/repos/passerby7890/MyClashClient/actions/artifacts/{art_id}/zip"
    print(f"[*] 正在下載 {name} (ID: {art_id})...", flush=True)
    req = urllib.request.Request(url, headers=HEADERS)
    with opener.open(req, timeout=300) as resp:
        content = resp.read()
    print(f"    下載完成 ({len(content)/(1024*1024):.2f} MB)，正在解壓縮到 {target_dir}...", flush=True)
    with zipfile.ZipFile(io.BytesIO(content)) as zf:
        zf.extractall(target_dir)
    print(f"    ✅ {name} 提取完成！", flush=True)

print("\n🎉 全部 macOS 產物已成功下載並解壓：")
for f in DIST_MAC.glob("*.dmg"):
    size_mb = os.path.getsize(f) / (1024 * 1024)
    print(f"  - DMG: {f.name} ({size_mb:.2f} MB)")

