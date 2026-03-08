$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot/..").Path
$rootsPath = Join-Path $repoRoot 'winui_roots.json'
$exceptionsPath = Join-Path $repoRoot 'winui_native_exceptions.json'
$outputPath = Join-Path $repoRoot 'winui_covered_set.json'

# --- Parse input JSON files ---
$roots = Get-Content -Raw $rootsPath | ConvertFrom-Json
$exceptions = Get-Content -Raw $exceptionsPath | ConvertFrom-Json

$exceptionNames = @{}
foreach ($t in $exceptions.types) {
    $exceptionNames[$t.name] = $true
}

# --- Find WinMD path (latest version) ---
$nugetBase = Join-Path $env:USERPROFILE '.nuget/packages/microsoft.windowsappsdk'
if (-not (Test-Path $nugetBase)) {
    Write-Error "WindowsAppSDK NuGet package not found at $nugetBase"
    exit 1
}

$versionDirs = Get-ChildItem -Directory $nugetBase | Sort-Object { [version]($_.Name -replace '[^0-9.]', '') } -ErrorAction SilentlyContinue
if ($versionDirs.Count -eq 0) {
    Write-Error "No version directories found under $nugetBase"
    exit 1
}

$latestVersion = $versionDirs[-1]
$winmdPath = Join-Path $latestVersion.FullName 'lib/uap10.0/Microsoft.UI.Xaml.winmd'
if (-not (Test-Path $winmdPath)) {
    # Try uap10.0.* variants
    $winmdCandidates = Get-ChildItem (Join-Path $latestVersion.FullName 'lib') -Directory | ForEach-Object {
        Join-Path $_.FullName 'Microsoft.UI.Xaml.winmd'
    } | Where-Object { Test-Path $_ }
    if ($winmdCandidates.Count -eq 0) {
        Write-Error "WinMD not found under $($latestVersion.FullName)"
        exit 1
    }
    $winmdPath = $winmdCandidates[0]
}

$winmdVersion = $latestVersion.Name
Write-Host "WinMD: $winmdPath (version $winmdVersion)"

# --- Build the project first ---
Write-Host "`nBuilding zig project..."
Push-Location $repoRoot
try {
    & zig build 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "zig build failed with exit code $LASTEXITCODE"
        exit 1
    }
} finally {
    Pop-Location
}
Write-Host "Build OK`n"

# --- Prepare temp directory ---
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "winui-coverage-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# --- Collect types to check ---
$typesToCheck = @()

foreach ($iface in $roots.roots.interfaces) {
    $typesToCheck += @{ full = $iface; kind = 'interface' }
}
foreach ($del in $roots.roots.delegates) {
    $typesToCheck += @{ full = $del; kind = 'delegate' }
}

# Enums and structs: mark OK by default (no vtable)
$enumStructResults = @()
foreach ($e in $roots.roots.enums) {
    $shortName = ($e -split '\.')[-1]
    $enumStructResults += @{
        type                  = $e
        short_name            = $shortName
        anyopaque_count       = 0
        placeholder_count     = 0
        not_implemented_count = 0
        status                = 'OK'
    }
}
foreach ($s in $roots.roots.structs) {
    $shortName = ($s -split '\.')[-1]
    $enumStructResults += @{
        type                  = $s
        short_name            = $shortName
        anyopaque_count       = 0
        placeholder_count     = 0
        not_implemented_count = 0
        status                = 'OK'
    }
}

# --- Run bindgen for each interface/delegate ---
$results = @()
$hasFailure = $false
$okCount = 0
$degradedCount = 0

foreach ($entry in $typesToCheck) {
    $fullName = $entry.full
    $shortName = ($fullName -split '\.')[-1]

    # Skip exceptions
    if ($exceptionNames.ContainsKey($shortName)) {
        Write-Host "[SKIP] $shortName (in exceptions)"
        continue
    }

    # Deploy path is a file, not a directory
    $deployFile = Join-Path $tempDir "com_$shortName.zig"
    if (Test-Path $deployFile) { Remove-Item $deployFile -Force }

    # Run bindgen
    $runArgs = @('build', 'run', '--', '--winmd', $winmdPath, '--deploy', $deployFile, '--iface', $shortName)
    Push-Location $repoRoot
    $output = & zig @runArgs 2>&1
    $exitCode = $LASTEXITCODE
    Pop-Location

    if ($exitCode -ne 0) {
        Write-Host "[FAIL] $shortName - bindgen exited with code $exitCode"
        $results += @{
            type                  = $fullName
            short_name            = $shortName
            anyopaque_count       = -1
            placeholder_count     = -1
            not_implemented_count = -1
            status                = 'DEGRADED'
        }
        $hasFailure = $true
        $degradedCount++
        continue
    }

    if (-not (Test-Path $deployFile)) {
        Write-Host "[FAIL] $shortName - no .zig file generated"
        $results += @{
            type                  = $fullName
            short_name            = $shortName
            anyopaque_count       = -1
            placeholder_count     = -1
            not_implemented_count = -1
            status                = 'DEGRADED'
        }
        $hasFailure = $true
        $degradedCount++
        continue
    }

    $content = Get-Content -Raw $deployFile

    # Count quality issues
    $anyopaqueCount = ([regex]::Matches($content, '\?\*anyopaque')).Count
    $placeholderCount = ([regex]::Matches($content, 'VtblPlaceholder')).Count
    $notImplCount = ([regex]::Matches($content, 'NotImplemented')).Count

    if ($anyopaqueCount -eq 0 -and $placeholderCount -eq 0) {
        $status = 'OK'
        $label = 'PASS'
        $okCount++
    } else {
        $status = 'DEGRADED'
        $label = 'FAIL'
        $hasFailure = $true
        $degradedCount++
    }

    $detail = "anyopaque=$anyopaqueCount placeholder=$placeholderCount not_impl=$notImplCount"
    Write-Host "[$label] $shortName ($detail)"

    $results += @{
        type                  = $fullName
        short_name            = $shortName
        anyopaque_count       = $anyopaqueCount
        placeholder_count     = $placeholderCount
        not_implemented_count = $notImplCount
        status                = $status
    }
}

# Add enum/struct results (all OK)
$results += $enumStructResults
$okCount += $enumStructResults.Count
$totalCount = $okCount + $degradedCount

# --- Clean up temp directory ---
Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue

# --- Build output JSON ---
$timestamp = (Get-Date).ToUniversalTime().ToString('o')

# Build JSON manually for stable key ordering
$resultsJson = @()
foreach ($r in $results) {
    $resultsJson += "    {`n" +
        "      `"type`": `"$($r.type)`",`n" +
        "      `"short_name`": `"$($r.short_name)`",`n" +
        "      `"anyopaque_count`": $($r.anyopaque_count),`n" +
        "      `"placeholder_count`": $($r.placeholder_count),`n" +
        "      `"not_implemented_count`": $($r.not_implemented_count),`n" +
        "      `"status`": `"$($r.status)`"`n" +
        "    }"
}

$json = @"
{
  "generated_at": "$timestamp",
  "winmd_version": "$winmdVersion",
  "results": [
$($resultsJson -join ",`n")
  ],
  "summary": {
    "total": $totalCount,
    "ok": $okCount,
    "degraded": $degradedCount
  }
}
"@

$json | Out-File -FilePath $outputPath -Encoding utf8

# --- Summary ---
Write-Host "`n===== Coverage Summary ====="
Write-Host "Total: $totalCount  OK: $okCount  Degraded: $degradedCount"
Write-Host "Output: $outputPath"

if ($hasFailure) {
    Write-Host "`n[FAIL] Some types have quality issues." -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n[PASS] All types OK." -ForegroundColor Green
    exit 0
}
