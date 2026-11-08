import json
import sys
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

TOKEN = "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"
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "User-Agent": "TianheCI",
    "Accept": "application/vnd.github+json"
}

url = "https://api.github.com/repos/passerby7890/MyClashClient/actions/runs?per_page=1"
req = urllib.request.Request(url, headers=HEADERS)
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode('utf-8'))

latest_run = data.get("workflow_runs", [])[0]
run_id = latest_run['id']
print(f"Run ID: {run_id} | Status: {latest_run['status']} | Conclusion: {latest_run.get('conclusion')}")

jobs_url = f"https://api.github.com/repos/passerby7890/MyClashClient/actions/runs/{run_id}/jobs"
req_jobs = urllib.request.Request(jobs_url, headers=HEADERS)
with urllib.request.urlopen(req_jobs) as resp:
    jobs_data = json.loads(resp.read().decode('utf-8'))

if jobs_data.get('jobs'):
    job = jobs_data['jobs'][0]
    print(f"Job: {job['name']} | Status: {job['status']}")
    for s in job.get('steps', []):
        conc = f" ({s.get('conclusion')})" if s.get('conclusion') else ""
        print(f"  [{s['status']}] {s['name']}{conc}")
