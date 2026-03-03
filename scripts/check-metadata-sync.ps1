param(
    [string]$BindgenRoot = "",
    [string]$MetadataRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $BindgenRoot) { $BindgenRoot = Split-Path -Parent $PSScriptRoot }
if (-not $MetadataRoot) { $MetadataRoot = Join-Path (Split-Path -Parent $BindgenRoot) "win-zig-metadata" }
if (-not (Test-Path -LiteralPath $MetadataRoot)) {
    Write-Host "check-metadata-sync: SKIP (metadata repo not found at $MetadataRoot)"
    exit 0
}

$files = @("coded_index.zig", "pe.zig", "streams.zig", "tables.zig", "metadata.zig")

foreach ($f in $files) {
    $a = Join-Path $BindgenRoot $f
    $b = Join-Path $MetadataRoot $f
    if (-not (Test-Path -LiteralPath $a)) { throw "Missing bindgen file: $a" }
    if (-not (Test-Path -LiteralPath $b)) { throw "Missing metadata file: $b" }

    $ca = Get-Content -LiteralPath $a -Raw
    $cb = Get-Content -LiteralPath $b -Raw
    if ($ca -ne $cb) {
        Write-Host "check-metadata-sync: FAIL ($f differs)"
        exit 1
    }
}

Write-Host "check-metadata-sync: PASS"
exit 0
