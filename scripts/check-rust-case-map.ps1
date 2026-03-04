param(
    [string]$RepoRoot = "",
    [string]$MapPath = "",
    [int]$MinMapped = 9
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
if (-not $MapPath) {
    $MapPath = Join-Path $RepoRoot "docs\rust-parity-case-map.json"
}

$casesPath = Join-Path $RepoRoot "shadow\windows-rs\bindgen-cases.json"
if (-not (Test-Path -LiteralPath $casesPath)) {
    throw "Missing bindgen cases file: $casesPath"
}
if (-not (Test-Path -LiteralPath $MapPath)) {
    throw "Missing parity map file: $MapPath"
}

$cases = Get-Content -LiteralPath $casesPath -Raw | ConvertFrom-Json
$map = Get-Content -LiteralPath $MapPath -Raw | ConvertFrom-Json

if (-not $map -or $map.Count -eq 0) {
    throw "Parity map is empty: $MapPath"
}

$validStatuses = @("mapped", "planned", "blocked")
$caseIdSet = @{}
foreach ($c in $cases) { $caseIdSet[[string]$c.id] = $true }

$seen = @{}
$mappedCount = 0
$plannedCount = 0
$blockedCount = 0

$testLines = rg -n '^test\s+"' $RepoRoot -g '*.zig' --glob '!shadow/**' --glob '!.zig-cache/**'
$zigTests = @{}
foreach ($line in $testLines) {
    if ($line -match '^.+?:\d+:test\s+"(.+)"\s*\{?$') {
        $zigTests[$matches[1]] = $true
    }
}

foreach ($entry in $map) {
    $id = [string]$entry.id
    $status = [string]$entry.status
    if (-not $id) { throw "map entry has empty id" }
    if ($seen.ContainsKey($id)) { throw "duplicate id in map: $id" }
    $seen[$id] = $true

    if (-not $caseIdSet.ContainsKey($id)) {
        throw "map id not found in bindgen-cases.json: $id"
    }
    if (-not ($validStatuses -contains $status)) {
        throw "invalid status for id=${id}: $status"
    }

    if ($status -eq "mapped") {
        $mappedCount += 1
        if (-not $entry.zig_tests -or $entry.zig_tests.Count -eq 0) {
            throw "mapped entry must include zig_tests: id=$id"
        }
        foreach ($t in $entry.zig_tests) {
            $title = [string]$t
            if (-not $zigTests.ContainsKey($title)) {
                throw "mapped test title not found in Zig tests: id=$id title='$title'"
            }
        }
    } elseif ($status -eq "planned") {
        $plannedCount += 1
        if (-not [string]$entry.reason) {
            throw "planned entry must include reason: id=$id"
        }
    } else {
        $blockedCount += 1
        if (-not [string]$entry.reason) {
            throw "blocked entry must include reason: id=$id"
        }
    }
}

if ($mappedCount -lt $MinMapped) {
    throw "mapped case count dropped below threshold: mapped=$mappedCount min=$MinMapped"
}

Write-Host ("rust-case-map: PASS (mapped={0}, planned={1}, blocked={2}, total_cases={3})" -f $mappedCount, $plannedCount, $blockedCount, $cases.Count)
exit 0
