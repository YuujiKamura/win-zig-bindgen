param(
    [string]$SnapshotDir = ""
)

$ErrorActionPreference = "Stop"

if (-not $SnapshotDir) {
    $SnapshotDir = Join-Path $env:TEMP "win-zig-bindgen-gen-parity-watch"
}

$processFile = Join-Path $SnapshotDir "watch-process.json"
if (-not (Test-Path -LiteralPath $processFile)) {
    Write-Host "gen-parity-watch: not running (missing process file)"
    exit 0
}

$processInfo = Get-Content -LiteralPath $processFile | ConvertFrom-Json
$running = $null
if ($processInfo.pid) {
    $running = Get-Process -Id $processInfo.pid -ErrorAction SilentlyContinue
}

if ($running) {
    Stop-Process -Id $processInfo.pid -Force
    Write-Host ("gen-parity-watch: STOPPED pid={0}" -f $processInfo.pid)
} else {
    Write-Host ("gen-parity-watch: stale pid={0}" -f $processInfo.pid)
}

Remove-Item -LiteralPath $processFile -Force -ErrorAction SilentlyContinue
