# tools/inspect_geoip_context.ps1
$soPath = "D:\flclash_client\android\app\src\main\jniLibs\arm64-v8a\libclash.so"
$bytes = [System.IO.File]::ReadAllBytes($soPath)
$str = [System.Text.Encoding]::ASCII.GetString($bytes)

function Show-Context($keyword) {
    Write-Host "=== Context for $keyword ==="
    $idx = 0
    $count = 0
    while (($idx = $str.IndexOf($keyword, $idx)) -ge 0 -and $count -lt 5) {
        $start = [Math]::Max(0, $idx - 80)
        $len = [Math]::Min($str.Length - $start, 180)
        $snippet = $str.Substring($start, $len) -replace "[\r\n\t\x00-\x1f]", " "
        Write-Host "[$count] ... $snippet ..."
        $idx += $keyword.Length
        $count++
    }
}

Show-Context "Country.mmdb"
Show-Context "geoip.metadb"
Show-Context "geo-auto-update"
