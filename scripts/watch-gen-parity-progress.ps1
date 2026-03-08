param(
    [string]$RepoRoot = "",
    [string]$SnapshotDir = "",
    [int]$IntervalSeconds = 60,
    [int]$Iterations = 0,
    [switch]$SkipTests,
    [switch]$AlwaysRunTests,
    [switch]$AutoCommentIssue,
    [string]$IssueRepo = "",
    [int]$IssueNumber = 0
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

if (-not $SnapshotDir) {
    $SnapshotDir = Join-Path $env:TEMP "win-zig-bindgen-gen-parity-watch"
}

$watchPaths = @(
    "emit.zig",
    "main.zig",
    "tests/generation_parity.zig"
)

$classifyScript = Join-Path $PSScriptRoot "classify-gen-parity-failures.ps1"
$compareScript = Join-Path $PSScriptRoot "compare-gen-parity-failure-reports.ps1"
$postScript = Join-Path $PSScriptRoot "post-gen-parity-watch-update.ps1"

if (-not (Test-Path -LiteralPath $classifyScript)) {
    throw "Missing classifier script: $classifyScript"
}
if (-not (Test-Path -LiteralPath $compareScript)) {
    throw "Missing compare script: $compareScript"
}
if ($AutoCommentIssue -and -not (Test-Path -LiteralPath $postScript)) {
    throw "Missing issue-post script: $postScript"
}

if (-not (Test-Path -LiteralPath $SnapshotDir)) {
    New-Item -ItemType Directory -Path $SnapshotDir | Out-Null
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-Sha256([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-WorktreeState {
    param(
        [string]$RepoRoot,
        [string[]]$WatchPaths
    )

    Push-Location $RepoRoot
    try {
        $branchName = @(git rev-parse --abbrev-ref HEAD)
        $statusLines = @(git status --short -- @WatchPaths)
        $diffStatLines = @(git diff --stat -- @WatchPaths)
        $cachedDiffStatLines = @(git diff --cached --stat -- @WatchPaths)
        $changedFiles = @((@(
            git diff --name-only -- @WatchPaths
        ) + @(
            git diff --cached --name-only -- @WatchPaths
        )) | Sort-Object -Unique)
    } finally {
        Pop-Location
    }

    $fingerprintText = (@($branchName) + @("---") + @($statusLines) + @("---") + @($diffStatLines) + @("---") + @($cachedDiffStatLines) + @("---") + @($changedFiles)) -join "`n"
    [pscustomobject]@{
        branch_name = $branchName
        status_lines = $statusLines
        diff_stat_lines = $diffStatLines
        cached_diff_stat_lines = $cachedDiffStatLines
        changed_files = $changedFiles
        fingerprint = Get-Sha256 -Text $fingerprintText
    }
}

function Write-TextFile {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Lines -Encoding UTF8
}

function Write-Heartbeat {
    param(
        [string]$SnapshotDir,
        [string]$Phase,
        [int]$Iteration,
        [bool]$Changed,
        [bool]$ShouldRunTests,
        [object]$State,
        [string]$LatestJsonPath,
        [string]$LatestMarkdownPath,
        [string]$LatestDiffPath
    )

    $payload = [ordered]@{
        updated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
        pid = $PID
        phase = $Phase
        iteration = $Iteration
        repo_root = $RepoRoot
        snapshot_dir = $SnapshotDir
        changed = $Changed
        should_run_tests = $ShouldRunTests
        watched_changed_files = @($State.changed_files)
        latest_report_json = $LatestJsonPath
        latest_report_markdown = $LatestMarkdownPath
        latest_diff_markdown = $LatestDiffPath
    }

    Write-JsonFile -Path (Join-Path $SnapshotDir "watch-heartbeat.json") -Value $payload
}

$iteration = 0
$lastFingerprint = ""
$lastJsonPath = ""
$lastMarkdownPath = ""
$lastDiffPath = ""

Write-Host ("watch-gen-parity-progress: START snapshot_dir={0}" -f $SnapshotDir)
Write-Host ("watch-gen-parity-progress: interval={0}s iterations={1}" -f $IntervalSeconds, $Iterations)

while ($true) {
    if ($Iterations -gt 0 -and $iteration -ge $Iterations) {
        break
    }

    $iteration += 1
    $state = Get-WorktreeState -RepoRoot $RepoRoot -WatchPaths $watchPaths
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $changed = $state.fingerprint -ne $lastFingerprint
    $shouldRunTests = (-not $SkipTests) -and ($AlwaysRunTests -or $changed)

    Write-Host ("[{0}] iteration={1} changed={2} watched_files={3}" -f $timestamp, $iteration, $changed, $state.changed_files.Count)
    Write-Heartbeat `
        -SnapshotDir $SnapshotDir `
        -Phase "watching" `
        -Iteration $iteration `
        -Changed $changed `
        -ShouldRunTests $shouldRunTests `
        -State $state `
        -LatestJsonPath $lastJsonPath `
        -LatestMarkdownPath $lastMarkdownPath `
        -LatestDiffPath $lastDiffPath

    if ($changed) {
        Write-TextFile -Path (Join-Path $SnapshotDir "$timestamp-status.txt") -Lines $state.status_lines
        Write-TextFile -Path (Join-Path $SnapshotDir "$timestamp-diffstat.txt") -Lines $state.diff_stat_lines
        Write-TextFile -Path (Join-Path $SnapshotDir "$timestamp-cached-diffstat.txt") -Lines $state.cached_diff_stat_lines
        Write-TextFile -Path (Join-Path $SnapshotDir "$timestamp-changed-files.txt") -Lines $state.changed_files
    }

    if ($shouldRunTests) {
        $jsonPath = Join-Path $SnapshotDir "$timestamp-gen-parity.json"
        $mdPath = Join-Path $SnapshotDir "$timestamp-gen-parity.md"
        & $classifyScript -RepoRoot $RepoRoot -RunTest -JsonOutPath $jsonPath -MarkdownOutPath $mdPath
        Copy-Item -LiteralPath $jsonPath -Destination (Join-Path $SnapshotDir "latest-gen-parity.json") -Force
        Copy-Item -LiteralPath $mdPath -Destination (Join-Path $SnapshotDir "latest-gen-parity.md") -Force

        if ($lastJsonPath -and (Test-Path -LiteralPath $lastJsonPath)) {
            $diffPath = Join-Path $SnapshotDir "$timestamp-gen-parity-diff.md"
            & $compareScript -BeforePath $lastJsonPath -AfterPath $jsonPath -MarkdownOutPath $diffPath
            Copy-Item -LiteralPath $diffPath -Destination (Join-Path $SnapshotDir "latest-gen-parity-diff.md") -Force
            $lastDiffPath = $diffPath
        }

        $lastJsonPath = $jsonPath
        $lastMarkdownPath = $mdPath
        Write-Heartbeat `
            -SnapshotDir $SnapshotDir `
            -Phase "tested" `
            -Iteration $iteration `
            -Changed $changed `
            -ShouldRunTests $shouldRunTests `
            -State $state `
            -LatestJsonPath $lastJsonPath `
            -LatestMarkdownPath $lastMarkdownPath `
            -LatestDiffPath $lastDiffPath

        if ($AutoCommentIssue -and $IssueNumber -gt 0) {
            $postArgs = @(
                "-NoProfile"
                "-File"
                $postScript
                "-RepoRoot"
                $RepoRoot
                "-SnapshotDir"
                $SnapshotDir
                "-IssueNumber"
                $IssueNumber
            )
            if ($IssueRepo) {
                $postArgs += @("-IssueRepo", $IssueRepo)
            }
            & pwsh @postArgs
        }
    }

    $lastFingerprint = $state.fingerprint

    if ($Iterations -gt 0 -and $iteration -ge $Iterations) {
        break
    }

    Start-Sleep -Seconds $IntervalSeconds
}

Write-Heartbeat `
    -SnapshotDir $SnapshotDir `
    -Phase "stopped" `
    -Iteration $iteration `
    -Changed $false `
    -ShouldRunTests $false `
    -State ([pscustomobject]@{ changed_files = @() }) `
    -LatestJsonPath $lastJsonPath `
    -LatestMarkdownPath $lastMarkdownPath `
    -LatestDiffPath $lastDiffPath

Write-Host "watch-gen-parity-progress: DONE"
