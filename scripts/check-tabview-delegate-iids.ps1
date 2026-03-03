param(
    [string]$RepoRoot = "",
    [string]$WinmdPath = ""
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path -LiteralPath $RepoRoot)) { throw "RepoRoot not found: $RepoRoot" }

function Find-Winmd {
    $base = Join-Path $env:USERPROFILE ".nuget\packages\microsoft.windowsappsdk"
    if (-not (Test-Path -LiteralPath $base)) { throw "WindowsAppSDK package directory not found: $base" }

    $candidates = @(Get-ChildItem -LiteralPath $base -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "lib\uap10.0\Microsoft.UI.Xaml.winmd" } |
        Where-Object { Test-Path -LiteralPath $_ })

    if ($candidates.Count -eq 0) { throw "Microsoft.UI.Xaml.winmd not found under $base" }
    return ($candidates | Select-Object -First 1)
}

if (-not $WinmdPath) { $WinmdPath = Find-Winmd }
if (-not (Test-Path -LiteralPath $WinmdPath)) { throw "WinMD not found: $WinmdPath" }

$expectedPath = Join-Path $RepoRoot "tests\expected-tabview-delegate-iids.zig.txt"
if (-not (Test-Path -LiteralPath $expectedPath)) { throw "Expected file not found: $expectedPath" }
$expected = (Get-Content -LiteralPath $expectedPath -Raw).Trim()

$generated = $null
Push-Location $RepoRoot
try {
    $generated = & zig build run -- --emit-tabview-delegate-zig $WinmdPath
    if ($LASTEXITCODE -ne 0) { throw "winmd2zig emit failed" }
}
finally {
    Pop-Location
}

$actualLines = @($generated | Where-Object {
    $_ -match '^pub const IID_TypedEventHandler_AddTabButtonClick' -or
    $_ -match '^pub const IID_SelectionChangedEventHandler' -or
    $_ -match '^pub const IID_TypedEventHandler_TabCloseRequested'
})
$actual = ($actualLines -join "`n").Trim()

if ($actual -ne $expected) {
    Write-Host "check-tabview-delegate-iids: FAIL"
    Write-Host "--- expected ---"
    Write-Host $expected
    Write-Host "--- actual ---"
    Write-Host $actual
    exit 1
}

Write-Host "check-tabview-delegate-iids: PASS"
exit 0
