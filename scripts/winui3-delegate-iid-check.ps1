param(
    [string]$RepoRoot = "",
    [string]$WinmdPath = ""
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $selfRepoRoot = Split-Path -Parent $PSScriptRoot
    $siblingGhostty = Join-Path (Split-Path -Parent $selfRepoRoot) "ghostty-win"
    if (Test-Path -LiteralPath (Join-Path $siblingGhostty "scripts\winui3-sync-delegate-iids.ps1")) {
        $RepoRoot = $siblingGhostty
    } else {
        $RepoRoot = $selfRepoRoot
    }
}

$syncScript = Join-Path $RepoRoot "scripts\winui3-sync-delegate-iids.ps1"
if (-not (Test-Path -LiteralPath $syncScript)) {
    throw "Script not found: $syncScript"
}

$args = @("-RepoRoot", $RepoRoot, "-Check")
if ($WinmdPath) {
    $args += @("-WinmdPath", $WinmdPath)
}

pwsh -File $syncScript @args
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "winui3-delegate-iid-check: FAIL (com.zig delegate IID constants are out of sync)"
    exit $exitCode
}

Write-Host "winui3-delegate-iid-check: PASS"
exit 0
