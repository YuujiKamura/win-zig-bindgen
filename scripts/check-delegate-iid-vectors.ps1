param(
    [string]$RepoRoot = "",
    [string]$WinmdPath = "",
    [string]$CasesPath = ""
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

if (-not $CasesPath) { $CasesPath = Join-Path $RepoRoot "tests\expected-delegate-iid-vectors.json" }
if (-not (Test-Path -LiteralPath $CasesPath)) { throw "Cases file not found: $CasesPath" }

$cases = Get-Content -LiteralPath $CasesPath -Raw | ConvertFrom-Json
if ($null -eq $cases -or @($cases).Count -eq 0) {
    throw "No cases in: $CasesPath"
}

$failed = @()

Push-Location $RepoRoot
try {
    foreach ($c in $cases) {
        $out = & zig build run -- --delegate-iid $WinmdPath $c.sender_class $c.result_type
        if ($LASTEXITCODE -ne 0) {
            $failed += "FAIL[$($c.name)]: command failed"
            continue
        }
        $line = ($out | Select-String "TypedEventHandler IID:").Line
        if (-not $line) {
            $failed += "FAIL[$($c.name)]: IID line missing"
            continue
        }
        $actual = ($line -replace '^TypedEventHandler IID:\s*', '').Trim().ToLowerInvariant()
        $expected = [string]$c.expected_iid
        $expected = $expected.ToLowerInvariant()
        if ($actual -ne $expected) {
            $failed += "FAIL[$($c.name)]: expected=$expected actual=$actual"
        } else {
            Write-Host "PASS[$($c.name)]: $actual"
        }
    }
}
finally {
    Pop-Location
}

if ($failed.Count -gt 0) {
    Write-Host "check-delegate-iid-vectors: FAIL"
    $failed | ForEach-Object { Write-Host $_ }
    exit 1
}

Write-Host "check-delegate-iid-vectors: PASS"
exit 0
