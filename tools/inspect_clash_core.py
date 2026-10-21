import hashlib
import zipfile
import re
import os
import sys

def sha256_of_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def sha256_of_file(filepath: str) -> str:
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def find_go_buildinfo(data: bytes):
    magic = b"\xff Go buildinf:"
    idx = data.find(magic)
    info = {"found": False, "offset": -1, "go_version": None, "mod_info": None}
    if idx != -1:
        info["found"] = True
        info["offset"] = idx
        # Parse nearby strings
        # Scan forward for 'go1.' string
        go_ver_match = re.search(rb"go1\.[0-9]+(\.[0-9]+)?", data[idx:idx+4096])
        if go_ver_match:
            info["go_version"] = go_ver_match.group(0).decode('utf-8', errors='ignore')
    return info

def inspect():
    so_path = "android/app/src/main/jniLibs/arm64-v8a/libclash.so"
    apk_path = "dist_android/tianhe-v3.0.4-arm64-v8a.apk"

    print("==================================================")
    print("1. FILE SIZES & SHA-256 CHECKSUM")
    print("==================================================")
    if os.path.exists(so_path):
        so_size = os.path.getsize(so_path)
        so_sha = sha256_of_file(so_path)
        print(f"Local libclash.so Path: {so_path}")
        print(f"Size: {so_size:,} bytes ({so_size / (1024*1024):.2f} MB)")
        print(f"SHA-256: {so_sha}")
    else:
        print(f"Error: {so_path} not found!")
        return

    apk_so_size = None
    apk_so_sha = None
    if os.path.exists(apk_path):
        with zipfile.ZipFile(apk_path, 'r') as z:
            apk_files = [f for f in z.namelist() if "libclash.so" in f]
            print(f"\nAPK Path: {apk_path}")
            print(f"Matched SO files in APK: {apk_files}")
            for name in apk_files:
                info = z.getinfo(name)
                content = z.read(name)
                apk_so_size = len(content)
                apk_so_sha = sha256_of_bytes(content)
                print(f"  Entry: {name}")
                print(f"  Size: {apk_so_size:,} bytes")
                print(f"  SHA-256: {apk_so_sha}")
                print(f"  Matches local jniLibs: {apk_so_sha == so_sha}")
    else:
        print(f"Warning: {apk_path} not found!")

    print("\n==================================================")
    print("2. LOADING AND SCANNING LIBCLASH.SO BINARY")
    print("==================================================")
    with open(so_path, 'rb') as f:
        data = f.read()

    print(f"Total binary bytes in memory: {len(data):,}")

    # Go version search
    go_matches = re.findall(rb"go1\.[0-9]+(\.[0-9]+)?", data)
    unique_go = sorted(list(set([m[0].decode('ascii') if isinstance(m, tuple) else m.decode('ascii') for m in go_matches])))
    # Better regex for go version
    go_ver_full = sorted(list(set(re.findall(rb"go1\.[0-9]+(\.[0-9]+)?(\w+)?", data))))
    all_go_strs = set(re.findall(rb"go1\.[0-9]+(\.[0-9]+)?", data))
    
    # Search for specific compiler version string
    ver_scan = re.findall(rb"go1\.[0-9]+\.[0-9]+", data)
    ver_counts = {}
    for v in ver_scan:
        ver_counts[v.decode('ascii')] = ver_counts.get(v.decode('ascii'), 0) + 1
    print("Go compiler versions detected in binary:")
    for v, c in sorted(ver_counts.items(), key=lambda x: x[1], reverse=True)[:10]:
        print(f"  {v}: count={c}")

    # Build info and tags
    buildinfo = find_go_buildinfo(data)
    print(f"\nGo buildinfo magic offset: {buildinfo}")

    # Search for Mihomo / Clash.Meta / FlClash package references
    print("\nPackage & Repository references:")
    repo_patterns = [
        rb"github\.com/[a-zA-Z0-9_\-]+/mihomo[a-zA-Z0-9_/\.\-]*",
        rb"github\.com/[a-zA-Z0-9_\-]+/clash[a-zA-Z0-9_/\.\-]*",
        rb"github\.com/[a-zA-Z0-9_\-]+/FlClash[a-zA-Z0-9_/\.\-]*",
        rb"github\.com/metacubex/[a-zA-Z0-9_/\.\-]+",
    ]
    for pat in repo_patterns:
        matches = set(re.findall(pat, data[:10000000])) # scan first 10MB
        shortened = sorted(list(set(['/'.join(m.decode('utf-8', errors='ignore').split('/')[0:3]) for m in matches])))
        sample = sorted(list(set([m.decode('utf-8', errors='ignore') for m in matches])))[:5]
        print(f"  Pattern {pat.decode('ascii')}: Sample matches -> {sample}")

    # Version / Commit hash search
    print("\n==================================================")
    print("3. VERSION TAGS & GIT COMMIT HASHES")
    print("==================================================")
    # Search for Version: or v1.
    version_regexes = [
        rb"Mihomo [a-zA-Z0-9\.\-\_]+",
        rb"Clash\.Meta [a-zA-Z0-9\.\-\_]+",
        rb"Meta [a-zA-Z0-9\.\-\_]+",
        rb"v1\.[0-9]+\.[0-9]+[a-zA-Z0-9\.\-\_]*",
        rb"version\s*=\s*[\"']?[a-zA-Z0-9\.\-\_]+",
    ]
    for rx in version_regexes:
        matches = set(re.findall(rx, data))
        found = [m.decode('utf-8', errors='ignore') for m in matches if len(m) < 40]
        print(f"  Regex {rx.decode('ascii')}: {found[:10]}")

    # Search for git revision (40 hex chars)
    # In Go build settings: vcs.revision=... or commit=...
    vcs_matches = re.findall(rb"vcs\.revision=([0-9a-fA-F]{7,40})", data)
    if vcs_matches:
        print(f"  VCS Revision (Git Commit): {[m.decode('ascii') for m in set(vcs_matches)]}")
    
    vcs_time = re.findall(rb"vcs\.time=([^\x00\r\n\t ]+)", data)
    if vcs_time:
        print(f"  VCS Commit Time: {[m.decode('ascii', errors='ignore') for m in set(vcs_time)]}")

    vcs_modified = re.findall(rb"vcs\.modified=([^\x00\r\n\t ]+)", data)
    if vcs_modified:
        print(f"  VCS Modified: {[m.decode('ascii', errors='ignore') for m in set(vcs_modified)]}")

    # Build tags search (e.g. -tags=...)
    build_tags = re.findall(rb"-tags=([^\x00\r\n\t \"]+)", data)
    if build_tags:
        print(f"  Build Tags: {[m.decode('ascii', errors='ignore') for m in set(build_tags)]}")
    
    # Search for with_gvisor
    with_gvisor = b"with_gvisor" in data
    print(f"  Contains 'with_gvisor': {with_gvisor}")

    # Search for CGO
    cgo_enabled = re.findall(rb"CGO_ENABLED=([01])", data)
    if cgo_enabled:
        print(f"  CGO_ENABLED: {[m.decode('ascii') for m in set(cgo_enabled)]}")

    print("\n==================================================")
    print("4. ADAPTER & OUTBOUND PROTOCOLS INSPECTION")
    print("==================================================")
    # Check outbound types
    protocols_to_check = [
        "vless", "vmess", "trojan", "shadowsocks", "shadowsocksr",
        "hysteria", "hysteria2", "tuic", "wireguard", "snell",
        "ssh", "http", "socks5", "direct", "reject", "relay",
        "selector", "url-test", "fallback", "load-balance",
        "anytls", "any-tls", "any_tls", "AnyTLS"
    ]
    
    # Search for adapter/outbound strings
    outbound_paths = set(re.findall(rb"adapter/outbound/([a-zA-Z0-9_\-]+)", data))
    print(f"Direct outbound adapter packages in binary:")
    for op in sorted(list(outbound_paths)):
        print(f"  - {op.decode('ascii', errors='ignore')}")

    print("\nProtocol keyword appearance in binary:")
    for proto in protocols_to_check:
        cnt = data.count(proto.encode('ascii'))
        print(f"  Protocol '{proto}': occurrences = {cnt}")

    # Specific investigation for AnyTLS
    print("\n==================================================")
    print("5. DEEP DIVE: ANYTLS INVESTIGATION")
    print("==================================================")
    anytls_variations = [b"anytls", b"AnyTLS", b"ANYTLS", b"any-tls", b"any_tls"]
    for v in anytls_variations:
        offsets = []
        pos = 0
        while len(offsets) < 5:
            pos = data.find(v, pos)
            if pos == -1:
                break
            offsets.append(pos)
            pos += len(v)
        print(f"Variation {v.decode('ascii')}: count={data.count(v)}, sample offsets={offsets}")
        for off in offsets:
            context = data[max(0, off-40):min(len(data), off+len(v)+40)]
            print(f"    Context @ {off}: {context!r}")

if __name__ == "__main__":
    inspect()
