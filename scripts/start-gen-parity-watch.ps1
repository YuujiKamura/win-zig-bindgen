param(
    [string]$RepoRoot = "",
    [string]$SnapshotDir = "",
    [int]$IntervalSeconds = 60,
    [switch]$EnableIssueComment,
    [string]$IssueRepo = "",
    [int]$IssueNumber = 23
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

if (-not $SnapshotDir) {
    $SnapshotDir = Join-Path $env:TEMP "win-zig-bindgen-gen-parity-watch"
}

$watchScript = Join-Path $PSScriptRoot "watch-gen-parity-progress.ps1"
if (-not (Test-Path -LiteralPath $watchScript)) {
    throw "Missing watch script: $watchScript"
}

if (-not (Test-Path -LiteralPath $SnapshotDir)) {
    New-Item -ItemType Directory -Path $SnapshotDir | Out-Null
}

$processFile = Join-Path $SnapshotDir "watch-process.json"
$stdoutPath = Join-Path $SnapshotDir "watch-stdout.log"
$stderrPath = Join-Path $SnapshotDir "watch-stderr.log"

if (Test-Path -LiteralPath $processFile) {
    $existing = Get-Content -LiteralPath $processFile | ConvertFrom-Json
    if ($existing.pid) {
        $running = Get-Process -Id $existing.pid -ErrorAction SilentlyContinue
        if ($running) {
            Write-Host ("gen-parity-watch: already running pid={0}" -f $existing.pid)
            exit 0
        }
    }
}

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)
if (-not $pwsh) {
    $pwsh = (Get-Command powershell -ErrorAction Stop)
}

$argList = @(
    "-NoProfile"
    "-File"
    $watchScript
    "-RepoRoot"
    $RepoRoot
    "-SnapshotDir"
    $SnapshotDir
    "-IntervalSeconds"
    $IntervalSeconds
)

if ($EnableIssueComment) {
    $argList += "-AutoCommentIssue"
    $argList += "-IssueNumber"
    $argList += $IssueNumber
    if ($IssueRepo) {
        $argList += "-IssueRepo"
        $argList += $IssueRepo
    }
}

$proc = Start-Process `
    -FilePath $pwsh.Source `
    -ArgumentList $argList `
    -WorkingDirectory $RepoRoot `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -PassThru

$processInfo = [ordered]@{
    pid = $proc.Id
    started_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
    repo_root = $RepoRoot
    snapshot_dir = $SnapshotDir
    interval_seconds = $IntervalSeconds
    auto_comment_issue = [bool]$EnableIssueComment
    issue_repo = $IssueRepo
    issue_number = $IssueNumber
    stdout_log = $stdoutPath
    stderr_log = $stderrPath
}

$processInfo | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $processFile -Encoding UTF8

Write-Host "gen-parity-watch: STARTED"
Write-Host ("  pid={0}" -f $proc.Id)
Write-Host ("  snapshot_dir={0}" -f $SnapshotDir)
Write-Host ("  stdout_log={0}" -f $stdoutPath)
Write-Host ("  stderr_log={0}" -f $stderrPath)
