param(
    [string]$RepoRoot = "",
    [string]$MapPath = "",
    [int]$MinMapped = 0,
    [switch]$AllowPlanned
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
$plannedIds = New-Object System.Collections.Generic.List[string]
$blockedIds = New-Object System.Collections.Generic.List[string]

$zigFiles = Get-ChildItem -Recurse -Filter '*.zig' -Path $RepoRoot |
    Where-Object { $_.FullName -notmatch '[\\/](shadow|\.zig-cache)[\\/]' }
$zigTests = @{}
foreach ($f in $zigFiles) {
    $lineNum = 0
    foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
        $lineNum++
        if ($line -match '^test\s+"([^"]+)"') {
            $zigTests[$matches[1]] = $true
        }
    }
}

function Resolve-TestTitle([string]$id, [string]$title) {
    if ($zigTests.ContainsKey($title)) {
        return $title
    }
    if ($title -match '^RED (\d{3}) (.+) generation parity$') {
        $candidate = "GEN $($matches[1]) $($matches[2])"
        if ($zigTests.ContainsKey($candidate)) {
            return $candidate
        }
    }
    $prefix = "GEN $id "
    foreach ($k in $zigTests.Keys) {
        if ($k.StartsWith($prefix)) {
            return $k
        }
    }
    return $null
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
            if (-not (Resolve-TestTitle $id $title)) {
                throw "mapped test title not found in Zig tests: id=$id title='$title'"
            }
        }
    } elseif ($status -eq "planned") {
        $plannedCount += 1
        $plannedIds.Add($id)
        if (-not [string]$entry.reason) {
            throw "planned entry must include reason: id=$id"
        }
    } else {
        $blockedCount += 1
        $blockedIds.Add($id)
        if (-not [string]$entry.reason) {
            throw "blocked entry must include reason: id=$id"
        }
    }
}

$missing = New-Object System.Collections.Generic.List[string]
foreach ($c in $cases) {
    $cid = [string]$c.id
    if (-not $seen.ContainsKey($cid)) {
        $missing.Add($cid)
    }
}

if ($missing.Count -gt 0) {
    $sample = ($missing | Select-Object -First 20) -join ","
    throw "map missing case ids: count=$($missing.Count) sample=[$sample]"
}

if ($mappedCount -lt $MinMapped) {
    throw "mapped case count dropped below threshold: mapped=$mappedCount min=$MinMapped"
}

if ((-not $AllowPlanned) -and ($plannedCount -gt 0 -or $blockedCount -gt 0)) {
    $plannedSample = ($plannedIds | Select-Object -First 20) -join ","
    $blockedSample = ($blockedIds | Select-Object -First 20) -join ","
    throw "non-mapped entries present: planned=$plannedCount blocked=$blockedCount planned_ids=[$plannedSample] blocked_ids=[$blockedSample]"
}

Write-Host ("rust-case-map: PASS (mapped={0}, planned={1}, blocked={2}, total_cases={3})" -f $mappedCount, $plannedCount, $blockedCount, $cases.Count)
exit 0
