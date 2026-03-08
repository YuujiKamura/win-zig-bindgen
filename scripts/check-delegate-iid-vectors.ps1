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
$generatedPath = Join-Path ([System.IO.Path]::GetTempPath()) ("bindgen-delegate-vectors-" + [System.Guid]::NewGuid().ToString("N") + ".zig")

Push-Location $RepoRoot
try {
    & zig build run -- --winmd $WinmdPath --deploy $generatedPath --iface ITabView
    if ($LASTEXITCODE -ne 0) { throw "winmd2zig emit failed" }
}
finally {
    Pop-Location
}
if (-not (Test-Path -LiteralPath $generatedPath)) { throw "Generated file not found: $generatedPath" }
$generated = Get-Content -LiteralPath $generatedPath -Raw
Remove-Item -LiteralPath $generatedPath -ErrorAction SilentlyContinue

$guidMap = @{
    "AddTabButtonClick uses IInspectable result" = "IID_TypedEventHandler_AddTabButtonClick"
    "TabCloseRequested uses TabViewTabCloseRequestedEventArgs" = "IID_TypedEventHandler_TabCloseRequested"
}

foreach ($c in $cases) {
    $constName = $guidMap[[string]$c.name]
    if (-not $constName) {
        $failed += "FAIL[$($c.name)]: no constant mapping"
        continue
    }
    $m = [regex]::Match($generated, "pub const $([regex]::Escape($constName)) = GUID\{ \.data1 = 0x([0-9a-f]+), \.data2 = 0x([0-9a-f]+), \.data3 = 0x([0-9a-f]+), \.data4 = \.\{ ([^}]+) \} \};", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $m.Success) {
        $failed += "FAIL[$($c.name)]: IID line missing"
        continue
    }
    $data4 = ($m.Groups[4].Value -split ',') | ForEach-Object { $_.Trim() -replace '^0x', '' }
    $actual = ("{0}-{1}-{2}-{3}{4}-{5}{6}{7}{8}{9}{10}" -f
        $m.Groups[1].Value.ToLowerInvariant().PadLeft(8, '0'),
        $m.Groups[2].Value.ToLowerInvariant().PadLeft(4, '0'),
        $m.Groups[3].Value.ToLowerInvariant().PadLeft(4, '0'),
        $data4[0].PadLeft(2, '0').ToLowerInvariant(),
        $data4[1].PadLeft(2, '0').ToLowerInvariant(),
        $data4[2].PadLeft(2, '0').ToLowerInvariant(),
        $data4[3].PadLeft(2, '0').ToLowerInvariant(),
        $data4[4].PadLeft(2, '0').ToLowerInvariant(),
        $data4[5].PadLeft(2, '0').ToLowerInvariant(),
        $data4[6].PadLeft(2, '0').ToLowerInvariant(),
        $data4[7].PadLeft(2, '0').ToLowerInvariant())
    $expected = ([string]$c.expected_iid).ToLowerInvariant()
    if ($actual -ne $expected) {
        $failed += "FAIL[$($c.name)]: expected=$expected actual=$actual"
    } else {
        Write-Host "PASS[$($c.name)]: $actual"
    }
}

if ($failed.Count -gt 0) {
    Write-Host "check-delegate-iid-vectors: FAIL"
    $failed | ForEach-Object { Write-Host $_ }
    exit 1
}

Write-Host "check-delegate-iid-vectors: PASS"
exit 0
