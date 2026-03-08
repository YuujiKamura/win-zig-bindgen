param(
    [Parameter(Mandatory = $true)]
    [string]$BeforePath,
    [Parameter(Mandatory = $true)]
    [string]$AfterPath,
    [string]$MarkdownOutPath = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $BeforePath)) {
    throw "Missing before report: $BeforePath"
}
if (-not (Test-Path -LiteralPath $AfterPath)) {
    throw "Missing after report: $AfterPath"
}

function Read-Report([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function ConvertTo-CaseMap([object]$Report) {
    $map = @{}
    foreach ($case in $Report.cases) {
        $map[[string]$case.case_id] = [ordered]@{
            case_id = [string]$case.case_id
            bucket_id = [string]$case.bucket_id
            bucket_label = [string]$case.bucket_label
            issue = [int]$case.issue
            messages = @($case.messages)
        }
    }
    return $map
}

function ConvertTo-BucketMap([object]$Report) {
    $map = @{}
    foreach ($bucket in $Report.buckets) {
        $map[[string]$bucket.bucket_id] = [ordered]@{
            bucket_id = [string]$bucket.bucket_id
            label = [string]$bucket.label
            issue = [int]$bucket.issue
            case_count = [int]$bucket.case_count
            message_count = [int]$bucket.message_count
            case_ids = @($bucket.case_ids)
        }
    }
    return $map
}

function Write-MarkdownDiff {
    param(
        [object]$Diff,
        [string]$Path
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Generation Parity Failure Diff")
    $lines.Add("")
    $lines.Add("Compared:")
    $lines.Add("- before: $($Diff.before.generated_at)")
    $lines.Add("- after: $($Diff.after.generated_at)")
    $lines.Add("")
    $lines.Add("| Metric | Before | After | Delta |")
    $lines.Add("| --- | ---: | ---: | ---: |")
    $lines.Add("| Failing cases | $($Diff.before.case_count) | $($Diff.after.case_count) | $($Diff.delta.case_count) |")
    $lines.Add("| Failure messages | $($Diff.before.message_count) | $($Diff.after.message_count) | $($Diff.delta.message_count) |")
    $lines.Add("")

    $lines.Add("## Bucket Delta")
    $lines.Add("")
    $lines.Add("| Bucket | Issue | Before | After | Delta |")
    $lines.Add("| --- | ---: | ---: | ---: | ---: |")
    foreach ($bucket in $Diff.bucket_delta) {
        $lines.Add("| $($bucket.bucket_id) $($bucket.label) | #$($bucket.issue) | $($bucket.before_case_count) | $($bucket.after_case_count) | $($bucket.delta_case_count) |")
    }
    $lines.Add("")

    $lines.Add("## Resolved Cases")
    $lines.Add("")
    if ($Diff.resolved_cases.Count -eq 0) {
        $lines.Add("- none")
    } else {
        foreach ($case in $Diff.resolved_cases) {
            $lines.Add("- ``$($case.case_id)`` from $($case.bucket_id) (#$($case.issue))")
        }
    }
    $lines.Add("")

    $lines.Add("## New Failing Cases")
    $lines.Add("")
    if ($Diff.new_cases.Count -eq 0) {
        $lines.Add("- none")
    } else {
        foreach ($case in $Diff.new_cases) {
            $lines.Add("- ``$($case.case_id)`` into $($case.bucket_id) (#$($case.issue))")
        }
    }
    $lines.Add("")

    $lines.Add("## Bucket Moves")
    $lines.Add("")
    if ($Diff.moved_cases.Count -eq 0) {
        $lines.Add("- none")
    } else {
        foreach ($move in $Diff.moved_cases) {
            $lines.Add("- ``$($move.case_id)``: $($move.before_bucket_id) -> $($move.after_bucket_id)")
        }
    }
    $lines.Add("")

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

$before = Read-Report -Path $BeforePath
$after = Read-Report -Path $AfterPath

$beforeCases = ConvertTo-CaseMap -Report $before
$afterCases = ConvertTo-CaseMap -Report $after
$beforeBuckets = ConvertTo-BucketMap -Report $before
$afterBuckets = ConvertTo-BucketMap -Report $after

$resolvedCases = New-Object System.Collections.Generic.List[object]
$newCases = New-Object System.Collections.Generic.List[object]
$movedCases = New-Object System.Collections.Generic.List[object]

foreach ($caseId in ($beforeCases.Keys | Sort-Object)) {
    if (-not $afterCases.ContainsKey($caseId)) {
        $resolvedCases.Add([ordered]@{
            case_id = $caseId
            bucket_id = $beforeCases[$caseId].bucket_id
            issue = $beforeCases[$caseId].issue
        })
        continue
    }

    if ($beforeCases[$caseId].bucket_id -ne $afterCases[$caseId].bucket_id) {
        $movedCases.Add([ordered]@{
            case_id = $caseId
            before_bucket_id = $beforeCases[$caseId].bucket_id
            after_bucket_id = $afterCases[$caseId].bucket_id
            before_issue = $beforeCases[$caseId].issue
            after_issue = $afterCases[$caseId].issue
        })
    }
}

foreach ($caseId in ($afterCases.Keys | Sort-Object)) {
    if ($beforeCases.ContainsKey($caseId)) { continue }
    $newCases.Add([ordered]@{
        case_id = $caseId
        bucket_id = $afterCases[$caseId].bucket_id
        issue = $afterCases[$caseId].issue
    })
}

$allBucketIds = @((@($beforeBuckets.Keys) + @($afterBuckets.Keys)) | Sort-Object -Unique)
$bucketDelta = foreach ($bucketId in $allBucketIds) {
    $beforeBucket = $beforeBuckets[$bucketId]
    $afterBucket = $afterBuckets[$bucketId]
    $beforeCount = if ($beforeBucket) { [int]$beforeBucket.case_count } else { 0 }
    $afterCount = if ($afterBucket) { [int]$afterBucket.case_count } else { 0 }
    $label = if ($afterBucket) { $afterBucket.label } else { $beforeBucket.label }
    $issue = if ($afterBucket) { $afterBucket.issue } else { $beforeBucket.issue }
    [ordered]@{
        bucket_id = $bucketId
        label = $label
        issue = $issue
        before_case_count = $beforeCount
        after_case_count = $afterCount
        delta_case_count = ($afterCount - $beforeCount)
    }
}

$bucketDeltaArray = @()
foreach ($bucket in $bucketDelta) {
    $bucketDeltaArray += [pscustomobject]$bucket
}

$resolvedCasesArray = @()
foreach ($case in $resolvedCases) {
    $resolvedCasesArray += [pscustomobject]$case
}

$newCasesArray = @()
foreach ($case in $newCases) {
    $newCasesArray += [pscustomobject]$case
}

$movedCasesArray = @()
foreach ($case in $movedCases) {
    $movedCasesArray += [pscustomobject]$case
}

$diff = [pscustomobject]@{
    before = [pscustomobject]@{
        generated_at = [string]$before.generated_at
        case_count = [int]$before.case_count
        message_count = [int]$before.message_count
    }
    after = [pscustomobject]@{
        generated_at = [string]$after.generated_at
        case_count = [int]$after.case_count
        message_count = [int]$after.message_count
    }
    delta = [pscustomobject]@{
        case_count = ([int]$after.case_count - [int]$before.case_count)
        message_count = ([int]$after.message_count - [int]$before.message_count)
    }
    bucket_delta = $bucketDeltaArray
    resolved_cases = $resolvedCasesArray
    new_cases = $newCasesArray
    moved_cases = $movedCasesArray
}

if ($MarkdownOutPath) {
    Write-MarkdownDiff -Diff $diff -Path $MarkdownOutPath
}

Write-Host "gen-parity-diff: PASS"
Write-Host ("  failing_cases: before={0} after={1} delta={2}" -f $diff.before.case_count, $diff.after.case_count, $diff.delta.case_count)
Write-Host ("  failure_messages: before={0} after={1} delta={2}" -f $diff.before.message_count, $diff.after.message_count, $diff.delta.message_count)
Write-Host ("  resolved_cases={0}" -f $diff.resolved_cases.Count)
Write-Host ("  new_cases={0}" -f $diff.new_cases.Count)
Write-Host ("  moved_cases={0}" -f $diff.moved_cases.Count)

foreach ($bucket in $diff.bucket_delta) {
    if ($bucket.delta_case_count -eq 0) { continue }
    Write-Host ("  {0}: before={1} after={2} delta={3} issue=#{4}" -f $bucket.bucket_id, $bucket.before_case_count, $bucket.after_case_count, $bucket.delta_case_count, $bucket.issue)
}
