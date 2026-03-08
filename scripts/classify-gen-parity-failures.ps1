param(
    [string]$RepoRoot = "",
    [string]$InputPath = "",
    [string]$JsonOutPath = "",
    [string]$MarkdownOutPath = "",
    [switch]$RunTest
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$bucketMeta = [ordered]@{
    "A1" = @{
        label = "free-function actual generation path"
        issue = 28
    }
    "A2" = @{
        label = "Win32 dependency and foundational type closure"
        issue = 24
    }
    "CDFG" = @{
        label = "dependent type closure for struct/interface/class/reference cases"
        issue = 25
    }
    "D1" = @{
        label = "inherited and required interface method propagation"
        issue = 29
    }
    "D2" = @{
        label = "delegate and runtime-class interface resolution"
        issue = 26
    }
    "F2G2" = @{
        label = "required-interface dependency closure for class/reference cases"
        issue = 30
    }
    "G2" = @{
        label = "required interface propagation for IMemoryBufferReference"
        issue = 27
    }
}

function Get-BucketInfo([string[]]$Messages) {
    $joined = $Messages -join " | "

    if ($joined -match "actual generation failed: InterfaceNotFound") {
        return "D2"
    }

    if ($Messages | Where-Object { $_ -match "^missing method on IAsyncAction:" -or $_ -match "^missing vtable method on IAsyncAction:" }) {
        return "D1"
    }

    if ($Messages | Where-Object { $_ -match "^missing method on IMemoryBufferReference:" -or $_ -match "^missing vtable method on IMemoryBufferReference:" }) {
        return "G2"
    }

    if ($Messages | Where-Object { $_ -match "^missing type: IClosable$" }) {
        return "F2G2"
    }

    $hasFunction = @($Messages | Where-Object { $_ -match "^missing function:" }).Count -gt 0
    $hasType = @($Messages | Where-Object { $_ -match "^missing type:" }).Count -gt 0
    $hasUnsupported = $joined -match "actual generation failed: UnsupportedActualGeneration"

    if ($hasFunction -and $hasType) {
        return "A2"
    }

    if ($hasUnsupported -or ($hasFunction -and -not $hasType)) {
        return "A1"
    }

    if ($hasType) {
        return "CDFG"
    }

    throw "Unable to classify messages: $joined"
}

function Read-FailureText {
    param(
        [string]$RepoRoot,
        [string]$InputPath,
        [switch]$RunTest
    )

    if ($RunTest) {
        Push-Location $RepoRoot
        try {
            $lines = @(zig build test-gen-parity 2>&1)
            return [pscustomobject]@{
                lines = $lines
                exit_code = $LASTEXITCODE
            }
        } finally {
            Pop-Location
        }
    }

    if (-not $InputPath) {
        throw "Pass -RunTest or -InputPath."
    }
    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Missing input file: $InputPath"
    }
    return [pscustomobject]@{
        lines = @(Get-Content -LiteralPath $InputPath)
        exit_code = 0
    }
}

function ConvertTo-FailureReport {
    param(
        [string[]]$Lines,
        [int]$ExitCode
    )

    $regex = [regex]'\[(\d{3})\] (.+)$'
    $caseMap = [ordered]@{}

    foreach ($line in $Lines) {
        $m = $regex.Match($line)
        if (-not $m.Success) { continue }
        $caseId = $m.Groups[1].Value
        $message = $m.Groups[2].Value
        if (-not $caseMap.Contains($caseId)) {
            $caseMap[$caseId] = New-Object System.Collections.Generic.List[string]
        }
        $caseMap[$caseId].Add($message)
    }

    $commandFailureKind = if ($ExitCode -ne 0 -and $caseMap.Count -eq 0) {
        "harness_failure"
    } elseif ($ExitCode -ne 0) {
        "test_failures"
    } else {
        "ok"
    }
    $commandExcerpt = @($Lines | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Select-Object -First 40)

    $caseReports = New-Object System.Collections.Generic.List[object]
    $bucketReports = [ordered]@{}
    foreach ($bucketId in $bucketMeta.Keys) {
        $bucketReports[$bucketId] = [ordered]@{
            bucket_id = $bucketId
            label = $bucketMeta[$bucketId].label
            issue = $bucketMeta[$bucketId].issue
            case_ids = New-Object System.Collections.Generic.List[string]
            message_count = 0
        }
    }

    foreach ($entry in $caseMap.GetEnumerator() | Sort-Object Key) {
        $caseId = [string]$entry.Key
        $messages = @($entry.Value)
        $bucketId = Get-BucketInfo -Messages $messages
        $bucket = $bucketReports[$bucketId]
        $bucket.case_ids.Add($caseId)
        $bucket.message_count += $messages.Count

        $caseReports.Add([ordered]@{
            case_id = $caseId
            bucket_id = $bucketId
            bucket_label = $bucketMeta[$bucketId].label
            issue = $bucketMeta[$bucketId].issue
            messages = $messages
        })
    }

    $bucketSummary = foreach ($bucketId in $bucketMeta.Keys) {
        $bucket = $bucketReports[$bucketId]
        [ordered]@{
            bucket_id = $bucketId
            label = $bucket.label
            issue = $bucket.issue
            case_count = $bucket.case_ids.Count
            message_count = $bucket.message_count
            case_ids = @($bucket.case_ids)
        }
    }

    return [ordered]@{
        generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
        command_ok = ($ExitCode -eq 0)
        command_exit_code = $ExitCode
        command_failure_kind = $commandFailureKind
        command_excerpt = $commandExcerpt
        case_count = $caseReports.Count
        message_count = ($caseReports | ForEach-Object { $_.messages.Count } | Measure-Object -Sum).Sum
        buckets = $bucketSummary
        cases = $caseReports
    }
}

function Write-MarkdownReport {
    param(
        [object]$Report,
        [string]$Path
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Generation Parity Failure Report")
    $lines.Add("")
    $lines.Add("Generated: $($Report.generated_at)")
    $lines.Add("")
    $lines.Add("## Command Status")
    $lines.Add("")
    $lines.Add("- command ok: $($Report.command_ok)")
    $lines.Add("- exit code: $($Report.command_exit_code)")
    $lines.Add("- failure kind: $($Report.command_failure_kind)")
    if ($Report.command_failure_kind -ne "ok") {
        $lines.Add("")
        $lines.Add('```text')
        foreach ($excerptLine in $Report.command_excerpt) {
            $lines.Add([string]$excerptLine)
        }
        $lines.Add('```')
        $lines.Add("")
    }
    $lines.Add("- failing cases: $($Report.case_count)")
    $lines.Add("- failure messages: $($Report.message_count)")
    $lines.Add("")
    $lines.Add("## Bucket Summary")
    $lines.Add("")
    $lines.Add("| Bucket | Issue | Cases | Messages | IDs |")
    $lines.Add("| --- | ---: | ---: | ---: | --- |")
    foreach ($bucket in $Report.buckets) {
        $ids = ($bucket.case_ids -join ", ")
        $lines.Add("| $($bucket.bucket_id) $($bucket.label) | #$($bucket.issue) | $($bucket.case_count) | $($bucket.message_count) | $ids |")
    }
    $lines.Add("")
    $lines.Add("## Details")
    $lines.Add("")
    foreach ($bucket in $Report.buckets) {
        if ($bucket.case_count -eq 0) { continue }
        $lines.Add("### $($bucket.bucket_id) $($bucket.label) (#$($bucket.issue))")
        $lines.Add("")
        foreach ($case in $Report.cases | Where-Object { $_.bucket_id -eq $bucket.bucket_id }) {
            $lines.Add("- ``$($case.case_id)``")
            foreach ($message in $case.messages) {
                $lines.Add("  - $message")
            }
        }
        $lines.Add("")
    }

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

$result = Read-FailureText -RepoRoot $RepoRoot -InputPath $InputPath -RunTest:$RunTest
$report = ConvertTo-FailureReport -Lines $result.lines -ExitCode $result.exit_code

if ($JsonOutPath) {
    $dir = Split-Path -Parent $JsonOutPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $JsonOutPath -Encoding UTF8
}

if ($MarkdownOutPath) {
    Write-MarkdownReport -Report $report -Path $MarkdownOutPath
}

$summary = @(
    ("gen-parity-classification: {0}" -f $(if ($report.command_failure_kind -eq "harness_failure") { "HARNESS_FAILURE" } else { "PASS" }))
    ("  command_ok={0}" -f $report.command_ok)
    ("  exit_code={0}" -f $report.command_exit_code)
    ("  failure_kind={0}" -f $report.command_failure_kind)
    ("  failing_cases={0}" -f $report.case_count)
    ("  failure_messages={0}" -f $report.message_count)
)

foreach ($bucket in $report.buckets) {
    if ($bucket.case_count -eq 0) { continue }
    $summary += ("  {0}=cases:{1},messages:{2},issue:#{3}" -f $bucket.bucket_id, $bucket.case_count, $bucket.message_count, $bucket.issue)
}

$summary | ForEach-Object { Write-Host $_ }
