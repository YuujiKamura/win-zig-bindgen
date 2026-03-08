param(
    [string]$RepoRoot = "",
    [string]$SnapshotDir = "",
    [string]$IssueRepo = "",
    [int]$IssueNumber = 23,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

if (-not $SnapshotDir) {
    $SnapshotDir = Join-Path $env:TEMP "win-zig-bindgen-gen-parity-watch"
}

if (-not $IssueRepo) {
    Push-Location $RepoRoot
    try {
        $IssueRepo = gh repo view --json nameWithOwner --jq .nameWithOwner
    } finally {
        Pop-Location
    }
}

if ($IssueNumber -le 0) {
    throw "IssueNumber must be > 0"
}

$remoteUrl = git -C $RepoRoot remote get-url origin
if ($remoteUrl -notmatch "github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)") {
    throw "Unable to resolve origin repo from remote: $remoteUrl"
}
$originRepo = "$($Matches.owner)/$($Matches.repo)"
if ($IssueRepo -ne $originRepo) {
    throw "Issue repo mismatch. origin=$originRepo issue_repo=$IssueRepo"
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

function Read-JsonFile([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-StableReportFingerprint([object]$Report) {
    $stable = [ordered]@{
        command_ok = [bool]$Report.command_ok
        command_exit_code = [int]$Report.command_exit_code
        command_failure_kind = [string]$Report.command_failure_kind
        command_excerpt = @($Report.command_excerpt)
        case_count = [int]$Report.case_count
        message_count = [int]$Report.message_count
        buckets = @(
            foreach ($bucket in $Report.buckets) {
                [ordered]@{
                    bucket_id = [string]$bucket.bucket_id
                    case_count = [int]$bucket.case_count
                    message_count = [int]$bucket.message_count
                    case_ids = @($bucket.case_ids | Sort-Object)
                }
            }
        )
    }
    return Get-Sha256 -Text ($stable | ConvertTo-Json -Depth 8 -Compress)
}

function Get-DatedReportFiles([string]$SnapshotDir) {
    return @(
        Get-ChildItem -LiteralPath $SnapshotDir -Filter "*-gen-parity.json" |
            Where-Object { $_.Name -ne "latest-gen-parity.json" } |
            Sort-Object LastWriteTime, Name
    )
}

function Get-BucketMap([object]$Report) {
    $map = @{}
    foreach ($bucket in $Report.buckets) {
        $map[[string]$bucket.bucket_id] = $bucket
    }
    return $map
}

function Get-CaseMap([object]$Report) {
    $map = @{}
    foreach ($case in $Report.cases) {
        $map[[string]$case.case_id] = $case
    }
    return $map
}

function New-ListSection {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Title,
        [object[]]$Items,
        [scriptblock]$Formatter,
        [int]$Limit = 25
    )

    $Lines.Add("")
    $Lines.Add("### $Title")
    $Lines.Add("")
    if (-not $Items -or $Items.Count -eq 0) {
        $Lines.Add("- none")
        return
    }

    $count = 0
    foreach ($item in $Items) {
        if ($count -ge $Limit) { break }
        $Lines.Add((& $Formatter $item))
        $count += 1
    }
    if ($Items.Count -gt $Limit) {
        $Lines.Add("- ... and $($Items.Count - $Limit) more")
    }
}

$latestJson = Join-Path $SnapshotDir "latest-gen-parity.json"
$heartbeatJson = Join-Path $SnapshotDir "watch-heartbeat.json"
$commentStateJson = Join-Path $SnapshotDir "watch-comment-state.json"

if (-not (Test-Path -LiteralPath $latestJson)) {
    throw "Missing latest report: $latestJson"
}

$reports = Get-DatedReportFiles -SnapshotDir $SnapshotDir
if ($reports.Count -eq 0) {
    throw "No dated gen-parity reports found under $SnapshotDir"
}

$currentPath = $reports[-1].FullName
$previousPath = if ($reports.Count -ge 2) { $reports[-2].FullName } else { "" }

$currentReport = Read-JsonFile -Path $currentPath
$currentFingerprint = Get-StableReportFingerprint -Report $currentReport
$state = $null
if (Test-Path -LiteralPath $commentStateJson) {
    $state = Read-JsonFile -Path $commentStateJson
}

if (-not $Force -and $state -and $state.last_posted_fingerprint -eq $currentFingerprint) {
    Write-Host "gen-parity-watch-comment: SKIP unchanged"
    exit 0
}

$heartbeat = $null
if (Test-Path -LiteralPath $heartbeatJson) {
    $heartbeat = Read-JsonFile -Path $heartbeatJson
}

$previousReport = $null
if ($previousPath) {
    $previousReport = Read-JsonFile -Path $previousPath
}

$lines = New-Object System.Collections.Generic.List[string]
$hasPriorPost = $null -ne $state
$mode = if ($hasPriorPost) { "update" } else { "baseline" }
$resolved = @()
$new = @()
$moved = @()

$lines.Add("## gen-parity monitor $mode")
$lines.Add("")
$lines.Add("- observed_at: $($currentReport.generated_at)")
$lines.Add("- repo: $IssueRepo")
$lines.Add("- issue: #$IssueNumber")
$lines.Add("- command ok: $($currentReport.command_ok)")
$lines.Add("- exit code: $($currentReport.command_exit_code)")
$lines.Add("- failure kind: $($currentReport.command_failure_kind)")
$lines.Add("- failing cases: $($currentReport.case_count)")
$lines.Add("- failure messages: $($currentReport.message_count)")
if ($heartbeat) {
    $lines.Add("- watcher pid: $($heartbeat.pid)")
    $lines.Add("- watcher iteration: $($heartbeat.iteration)")
    $lines.Add("- watched changed files: $((@($heartbeat.watched_changed_files) -join ', '))")
}

$beforeBuckets = $null
$afterBuckets = $null
$beforeCases = $null
$afterCases = $null

if ($hasPriorPost -and $previousReport -and $currentReport.command_failure_kind -ne "harness_failure" -and $previousReport.command_failure_kind -ne "harness_failure") {
    $beforeBuckets = Get-BucketMap -Report $previousReport
    $afterBuckets = Get-BucketMap -Report $currentReport
    $beforeCases = Get-CaseMap -Report $previousReport
    $afterCases = Get-CaseMap -Report $currentReport

    $resolved = @(
        foreach ($caseId in ($beforeCases.Keys | Sort-Object)) {
            if (-not $afterCases.ContainsKey($caseId)) {
                [pscustomobject]@{
                    case_id = $caseId
                    bucket_id = [string]$beforeCases[$caseId].bucket_id
                    issue = [int]$beforeCases[$caseId].issue
                }
            }
        }
    )
    $new = @(
        foreach ($caseId in ($afterCases.Keys | Sort-Object)) {
            if (-not $beforeCases.ContainsKey($caseId)) {
                [pscustomobject]@{
                    case_id = $caseId
                    bucket_id = [string]$afterCases[$caseId].bucket_id
                    issue = [int]$afterCases[$caseId].issue
                }
            }
        }
    )
    $moved = @(
        foreach ($caseId in ($beforeCases.Keys | Sort-Object)) {
            if ($afterCases.ContainsKey($caseId) -and $beforeCases[$caseId].bucket_id -ne $afterCases[$caseId].bucket_id) {
                [pscustomobject]@{
                    case_id = $caseId
                    before_bucket_id = [string]$beforeCases[$caseId].bucket_id
                    after_bucket_id = [string]$afterCases[$caseId].bucket_id
                }
            }
        }
    )
}

$lines.Add("- resolved cases: $($resolved.Count)")
$lines.Add("- new failing cases: $($new.Count)")
$lines.Add("- bucket moves: $($moved.Count)")
$lines.Add("")
$lines.Add("### Delta Summary")
$lines.Add("")
$lines.Add("| Metric | Count |")
$lines.Add("| --- | ---: |")
$lines.Add("| Resolved cases | $($resolved.Count) |")
$lines.Add("| New failing cases | $($new.Count) |")
$lines.Add("| Bucket moves | $($moved.Count) |")

$lines.Add("")
$lines.Add("### Bucket Summary")
$lines.Add("")
$lines.Add("| Bucket | Issue | Cases | Messages |")
$lines.Add("| --- | ---: | ---: | ---: |")
foreach ($bucket in $currentReport.buckets) {
    if ([int]$bucket.case_count -eq 0) { continue }
    $lines.Add("| $($bucket.bucket_id) | #$($bucket.issue) | $($bucket.case_count) | $($bucket.message_count) |")
}

if ($currentReport.command_failure_kind -eq "harness_failure") {
    $lines.Add("")
    $lines.Add("### Harness Failure")
    $lines.Add("")
    $lines.Add('```text')
    foreach ($excerptLine in $currentReport.command_excerpt) {
        $lines.Add([string]$excerptLine)
    }
    $lines.Add('```')
}

if ($hasPriorPost -and $previousReport -and $currentReport.command_failure_kind -ne "harness_failure" -and $previousReport.command_failure_kind -ne "harness_failure") {
    $lines.Add("")
    $lines.Add("### Delta")
    $lines.Add("")
    $lines.Add("- failing cases: $($previousReport.case_count) -> $($currentReport.case_count) (delta $([int]$currentReport.case_count - [int]$previousReport.case_count))")
    $lines.Add("- failure messages: $($previousReport.message_count) -> $($currentReport.message_count) (delta $([int]$currentReport.message_count - [int]$previousReport.message_count))")
    $lines.Add("")
    $lines.Add("| Bucket | Issue | Before | After | Delta |")
    $lines.Add("| --- | ---: | ---: | ---: | ---: |")
    $bucketIds = @((@($beforeBuckets.Keys) + @($afterBuckets.Keys)) | Sort-Object -Unique)
    foreach ($bucketId in $bucketIds) {
        $beforeCount = if ($beforeBuckets[$bucketId]) { [int]$beforeBuckets[$bucketId].case_count } else { 0 }
        $afterCount = if ($afterBuckets[$bucketId]) { [int]$afterBuckets[$bucketId].case_count } else { 0 }
        if ($afterBuckets[$bucketId]) {
            $issue = [int]$afterBuckets[$bucketId].issue
        } else {
            $issue = [int]$beforeBuckets[$bucketId].issue
        }
        if ($beforeCount -eq $afterCount) { continue }
        $lines.Add("| $bucketId | #$issue | $beforeCount | $afterCount | $($afterCount - $beforeCount) |")
    }

    New-ListSection -Lines $lines -Title "Resolved Cases" -Items $resolved -Formatter { param($x) "- ``$($x.case_id)`` from $($x.bucket_id) (#$($x.issue))" }
    New-ListSection -Lines $lines -Title "New Failing Cases" -Items $new -Formatter { param($x) "- ``$($x.case_id)`` into $($x.bucket_id) (#$($x.issue))" }
    New-ListSection -Lines $lines -Title "Bucket Moves" -Items $moved -Formatter { param($x) "- ``$($x.case_id)``: $($x.before_bucket_id) -> $($x.after_bucket_id)" }
}

$bodyPath = Join-Path $SnapshotDir "watch-comment-body.md"
Set-Content -LiteralPath $bodyPath -Value $lines -Encoding UTF8

if ($DryRun) {
    Write-Host "gen-parity-watch-comment: DRY RUN"
    Get-Content -LiteralPath $bodyPath
    exit 0
}

Push-Location $RepoRoot
try {
    gh issue comment $IssueNumber --repo $IssueRepo --body-file $bodyPath | Out-Null
} finally {
    Pop-Location
}

[ordered]@{
    last_posted_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
    last_posted_fingerprint = $currentFingerprint
    last_posted_report = $currentPath
    issue_repo = $IssueRepo
    issue_number = $IssueNumber
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $commentStateJson -Encoding UTF8

Write-Host "gen-parity-watch-comment: POSTED"
Write-Host ("  repo={0}" -f $IssueRepo)
Write-Host ("  issue=#{0}" -f $IssueNumber)
Write-Host ("  report={0}" -f $currentPath)
