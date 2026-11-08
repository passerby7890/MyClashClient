import sys
import json
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

TOKEN = "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"
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "User-Agent": "TianheCI",
    "Accept": "application/vnd.github+json"
}

url = "https://api.github.com/repos/passerby7890/MyClashClient/actions/runs/41362431554/jobs"
req = urllib.request.Request(url, headers=HEADERS)
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode('utf-8'))

job = data['jobs'][0]
print(f"Job: {job['name']} | Status: {job['status']} | Runner: {job.get('runner_name')}")
for s in job.get('steps', []):
    print(f"  - [{s['status']}] {s['name']} (conclusion: {s.get('conclusion')})")

