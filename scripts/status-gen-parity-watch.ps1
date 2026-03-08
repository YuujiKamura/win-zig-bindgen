param(
    [string]$SnapshotDir = "",
    [string]$MarkdownOutPath = ""
)

$ErrorActionPreference = "Stop"

if (-not $SnapshotDir) {
    $SnapshotDir = Join-Path $env:TEMP "win-zig-bindgen-gen-parity-watch"
}

$processFile = Join-Path $SnapshotDir "watch-process.json"
$heartbeatFile = Join-Path $SnapshotDir "watch-heartbeat.json"
$latestJsonFile = Join-Path $SnapshotDir "latest-gen-parity.json"
$latestDiffFile = Join-Path $SnapshotDir "latest-gen-parity-diff.md"

$processInfo = $null
$heartbeat = $null
$latestReport = $null
$isRunning = $false

if (Test-Path -LiteralPath $processFile) {
    $processInfo = Get-Content -LiteralPath $processFile | ConvertFrom-Json
    if ($processInfo.pid) {
        $isRunning = $null -ne (Get-Process -Id $processInfo.pid -ErrorAction SilentlyContinue)
    }
}

if (Test-Path -LiteralPath $heartbeatFile) {
    $heartbeat = Get-Content -LiteralPath $heartbeatFile | ConvertFrom-Json
}

if (Test-Path -LiteralPath $latestJsonFile) {
    $latestReport = Get-Content -LiteralPath $latestJsonFile | ConvertFrom-Json
}

$lines = New-Object System.Collections.Generic.List[string]
$runningText = if ($isRunning) { "yes" } else { "no" }
$lines.Add("# Gen Parity Watch Status")
$lines.Add("")
$lines.Add("- snapshot dir: `"$SnapshotDir`"")
$lines.Add("- running: $runningText")

if ($processInfo) {
    $lines.Add("- pid: $($processInfo.pid)")
    $lines.Add("- started_at: $($processInfo.started_at)")
    $lines.Add("- interval_seconds: $($processInfo.interval_seconds)")
    $lines.Add("- stdout_log: `"$($processInfo.stdout_log)`"")
    $lines.Add("- stderr_log: `"$($processInfo.stderr_log)`"")
}

if ($heartbeat) {
    $lines.Add("- heartbeat: $($heartbeat.updated_at)")
    $lines.Add("- phase: $($heartbeat.phase)")
    $lines.Add("- iteration: $($heartbeat.iteration)")
    $lines.Add("- changed: $($heartbeat.changed)")
    $lines.Add("- should_run_tests: $($heartbeat.should_run_tests)")
    if ($heartbeat.watched_changed_files.Count -gt 0) {
        $lines.Add("- watched changed files: $((($heartbeat.watched_changed_files) -join ', '))")
    }
}

if ($latestReport) {
    $lines.Add("")
    $lines.Add("## Latest Report")
    $lines.Add("")
    if ($null -ne $latestReport.command_ok) {
        $lines.Add("- command_ok: $($latestReport.command_ok)")
        $lines.Add("- exit_code: $($latestReport.command_exit_code)")
        $lines.Add("- failure_kind: $($latestReport.command_failure_kind)")
    }
    $lines.Add("- failing cases: $($latestReport.case_count)")
    $lines.Add("- failure messages: $($latestReport.message_count)")
    foreach ($bucket in $latestReport.buckets) {
        if ($bucket.case_count -eq 0) { continue }
        $lines.Add("- $($bucket.bucket_id): cases=$($bucket.case_count) messages=$($bucket.message_count) issue=#$($bucket.issue)")
    }
}

if (Test-Path -LiteralPath $latestDiffFile) {
    $lines.Add("")
    $lines.Add("## Latest Diff")
    $lines.Add("")
    $lines.Add("- markdown: `"$latestDiffFile`"")
}

if ($MarkdownOutPath) {
    $dir = Split-Path -Parent $MarkdownOutPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $MarkdownOutPath -Value $lines -Encoding UTF8
}

$lines | ForEach-Object { Write-Host $_ }
