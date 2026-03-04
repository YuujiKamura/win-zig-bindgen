param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }

$metaSync = Join-Path $RepoRoot "scripts\check-metadata-sync.ps1"
$iidCheck = Join-Path $RepoRoot "scripts\check-tabview-delegate-iids.ps1"
$caseMapCheck = Join-Path $RepoRoot "scripts\check-rust-case-map.ps1"

if (-not (Test-Path -LiteralPath $metaSync)) { throw "Missing script: $metaSync" }
if (-not (Test-Path -LiteralPath $iidCheck)) { throw "Missing script: $iidCheck" }
if (-not (Test-Path -LiteralPath $caseMapCheck)) { throw "Missing script: $caseMapCheck" }

# Guard 1: no stderr suppression in delegate IID check path.
$iidText = Get-Content -LiteralPath $iidCheck -Raw
if ($iidText -match '2>\$null') {
    throw "stderr suppression found in check-tabview-delegate-iids.ps1"
}

# Guard 2: metadata sync must treat EOL-only differences as equal.
$tmp = Join-Path $RepoRoot "tmp\script-guard"
if (Test-Path -LiteralPath $tmp) {
    Remove-Item -LiteralPath $tmp -Recurse -Force
}
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $a = Join-Path $tmp "a"
    $b = Join-Path $tmp "b"
    New-Item -ItemType Directory -Path $a | Out-Null
    New-Item -ItemType Directory -Path $b | Out-Null

    $files = @("coded_index.zig", "pe.zig", "streams.zig", "tables.zig", "metadata.zig")
    foreach ($f in $files) {
        Set-Content -LiteralPath (Join-Path $a $f) -Value "line1`nline2`n" -NoNewline
        Set-Content -LiteralPath (Join-Path $b $f) -Value "line1`r`nline2`r`n" -NoNewline
    }

    & pwsh -NoProfile -File $metaSync -BindgenRoot $a -MetadataRoot $b
    if ($LASTEXITCODE -ne 0) {
        throw "EOL-normalized metadata sync check failed unexpectedly"
    }

    # Now confirm real content differences still fail.
    Set-Content -LiteralPath (Join-Path $b "metadata.zig") -Value "DIFFERENT`r`n" -NoNewline
    $failOut = & pwsh -NoProfile -File $metaSync -BindgenRoot $a -MetadataRoot $b 2>&1
    if ($LASTEXITCODE -eq 0) {
        throw "metadata sync did not fail on real content difference"
    }
    if (($failOut | Out-String) -notmatch "FAIL \(metadata\.zig differs\)") {
        throw "metadata sync failed but not with expected file-level diff signal"
    }
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "test-script-guards: PASS"
exit 0
