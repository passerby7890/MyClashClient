# tools/inspect_geoip_strings.ps1
$soPath = "D:\flclash_client\android\app\src\main\jniLibs\arm64-v8a\libclash.so"
$bytes = [System.IO.File]::ReadAllBytes($soPath)
$str = [System.Text.Encoding]::ASCII.GetString($bytes)
$pattern = "(Country\.mmdb|geoip\.metadb|geodata-mode|geo-auto-update|geox-url|geoip\.dat|geosite\.dat|GeoIP|GeoSite)"
$regex = [regex]$pattern
$matches = $regex.Matches($str)
$unique = $matches | ForEach-Object { $_.Value } | Select-Object -Unique
Write-Host "Unique strings found in libclash.so:"
$unique | ForEach-Object { Write-Host " - $_" }
