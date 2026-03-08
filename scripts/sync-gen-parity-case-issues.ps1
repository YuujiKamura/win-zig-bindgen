param(
    [Parameter(Mandatory = $true)]
    [string]$BucketId,
    [Parameter(Mandatory = $true)]
    [int]$ParentIssue,
    [string]$RepoRoot = "",
    [string]$IssueRepo = "",
    [string]$ReportPath = "",
    [string]$CasesPath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

if (-not $IssueRepo) {
    Push-Location $RepoRoot
    try {
        $IssueRepo = gh repo view --json nameWithOwner --jq .nameWithOwner
    } finally {
        Pop-Location
    }
}

if (-not $ReportPath) {
    $ReportPath = "C:\Users\yuuji\AppData\Local\Temp\win-zig-bindgen-gen-parity-watch-live\latest-gen-parity.json"
}

if (-not $CasesPath) {
    $CasesPath = Join-Path $RepoRoot "shadow\windows-rs\bindgen-cases.json"
}

if (-not (Test-Path -LiteralPath $ReportPath)) {
    throw "Missing report path: $ReportPath"
}
if (-not (Test-Path -LiteralPath $CasesPath)) {
    throw "Missing cases path: $CasesPath"
}

$report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
$caseManifest = Get-Content -LiteralPath $CasesPath -Raw | ConvertFrom-Json
$existingIssues = gh issue list --repo $IssueRepo --state all --limit 500 --json number,title,url | ConvertFrom-Json

$bucket = $report.buckets | Where-Object { $_.bucket_id -eq $BucketId } | Select-Object -First 1
if (-not $bucket) {
    throw "Bucket not found in report: $BucketId"
}

$caseEntries = @(
    $report.cases |
        Where-Object { $_.bucket_id -eq $BucketId } |
        Sort-Object case_id
)

function Get-ArgValue {
    param(
        [string]$ArgText,
        [string]$Flag
    )

    $pattern = '(?:^|\s){0}\s+(.+?)(?=\s+--|$)' -f [regex]::Escape($Flag)
    $m = [regex]::Match($ArgText, $pattern)
    if ($m.Success) {
        return $m.Groups[1].Value.Trim()
    }
    return ""
}

function Get-ShortTitle {
    param(
        [string]$BucketId,
        [string]$CaseId,
        [string]$OutName
    )

    $suffix = switch ($BucketId) {
        "CDFG" { "dependency closure" }
        "D2" { "interface resolution" }
        default { "parity fix" }
    }
    if ($OutName) {
        return "parity case ${CaseId}: $OutName $suffix"
    }
    return "parity case ${CaseId}: $suffix"
}

function Get-BodyLines {
    param(
        [object]$CaseEntry,
        [object]$ManifestEntry,
        [string]$BucketLabel,
        [int]$ParentIssue,
        [string]$OutName,
        [string]$FilterText
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Parent: #$ParentIssue")
    $lines.Add("Roadmap: #12")
    $lines.Add("")
    $lines.Add("## Scope")
    $lines.Add("")
    $lines.Add("Fix case ``$($CaseEntry.case_id)`` currently classified under ``$($CaseEntry.bucket_id)``.")
    $lines.Add("")
    $lines.Add("## Case")
    $lines.Add("")
    $lines.Add("- id: ``$($CaseEntry.case_id)``")
    $lines.Add("- bucket: ``$($CaseEntry.bucket_id)``")
    $lines.Add("- bucket label: $BucketLabel")
    if ($ManifestEntry.kind) {
        $lines.Add("- kind: ``$($ManifestEntry.kind)``")
    }
    if ($OutName) {
        $lines.Add("- out: ``$OutName``")
    }
    if ($FilterText) {
        $lines.Add("- filter: ``$FilterText``")
    }
    if ($ManifestEntry.args) {
        $lines.Add("- args: ``$($ManifestEntry.args)``")
    }
    $lines.Add("- source report: ``$($report.generated_at)``")
    $lines.Add("")
    $lines.Add("## Current failures")
    $lines.Add("")
    foreach ($message in $CaseEntry.messages) {
        $lines.Add("- $message")
    }
    $lines.Add("")
    $lines.Add("## Done")
    $lines.Add("")
    $lines.Add("- [ ] case ``$($CaseEntry.case_id)`` no longer appears in bucket ``$($CaseEntry.bucket_id)``")
    $lines.Add("- [ ] current failure messages for ``$($CaseEntry.case_id)`` disappear from ``zig build test-gen-parity``")
    $lines.Add("- [ ] parent #$ParentIssue can remove this case from active tracking")
    return $lines
}

$manifestMap = @{}
foreach ($entry in $caseManifest) {
    $manifestMap[[string]$entry.id] = $entry
}

$resultRows = New-Object System.Collections.Generic.List[object]

foreach ($caseEntry in $caseEntries) {
    $caseId = [string]$caseEntry.case_id
    $manifestEntry = $manifestMap[$caseId]
    if (-not $manifestEntry) {
        throw "Manifest entry not found for case $caseId"
    }

    $argText = [string]$manifestEntry.args
    $outName = Get-ArgValue -ArgText $argText -Flag "--out"
    $filterText = Get-ArgValue -ArgText $argText -Flag "--filter"
    $title = Get-ShortTitle -BucketId $BucketId -CaseId $caseId -OutName $outName

    $existing = $existingIssues | Where-Object { $_.title -eq $title } | Select-Object -First 1
    if ($existing) {
        $resultRows.Add([pscustomobject]@{
            case_id = $caseId
            action = "existing"
            number = $existing.number
            title = $existing.title
            url = $existing.url
        })
        continue
    }

    $bodyLines = Get-BodyLines `
        -CaseEntry $caseEntry `
        -ManifestEntry $manifestEntry `
        -BucketLabel ([string]$bucket.label) `
        -ParentIssue $ParentIssue `
        -OutName $outName `
        -FilterText $filterText

    if ($DryRun) {
        $resultRows.Add([pscustomobject]@{
            case_id = $caseId
            action = "dry_run"
            number = 0
            title = $title
            url = ""
        })
        continue
    }

    $bodyPath = Join-Path $env:TEMP ("gen-parity-case-{0}.md" -f $caseId)
    Set-Content -LiteralPath $bodyPath -Value $bodyLines -Encoding UTF8
    $createOutput = gh issue create --repo $IssueRepo --title $title --body-file $bodyPath
    if ($LASTEXITCODE -ne 0) {
        throw "gh issue create failed for case $caseId"
    }
    $issueUrl = ($createOutput | Select-Object -Last 1).Trim()
    $issueNumber = [int]([regex]::Match($issueUrl, "/issues/(\d+)$").Groups[1].Value)
    $existingIssues += [pscustomobject]@{
        number = $issueNumber
        title = $title
        url = $issueUrl
    }
    $resultRows.Add([pscustomobject]@{
        case_id = $caseId
        action = "created"
        number = $issueNumber
        title = $title
        url = $issueUrl
    })
}

$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add("## case issue sync for $BucketId")
$summaryLines.Add("")
$summaryLines.Add("- source report: ``$($report.generated_at)``")
$summaryLines.Add("- parent: #$ParentIssue")
$summaryLines.Add("- bucket: ``$BucketId``")
$summaryLines.Add("- total cases: $($caseEntries.Count)")
$summaryLines.Add("- created: $((@($resultRows | Where-Object { $_.action -eq 'created' })).Count)")
$summaryLines.Add("- reused: $((@($resultRows | Where-Object { $_.action -eq 'existing' })).Count)")
if ($DryRun) {
    $summaryLines.Add("- mode: dry-run")
}
$summaryLines.Add("")
$summaryLines.Add("| Case | Issue | Action | Title |")
$summaryLines.Add("| --- | ---: | --- | --- |")
foreach ($row in $resultRows | Sort-Object case_id) {
    $issueCell = if ($row.number -gt 0) { "#$($row.number)" } else { "-" }
    $summaryLines.Add("| ``$($row.case_id)`` | $issueCell | $($row.action) | $($row.title) |")
}

if ($DryRun) {
    $summaryLines | ForEach-Object { Write-Host $_ }
    exit 0
}

$summaryBody = Join-Path $env:TEMP ("gen-parity-case-sync-{0}.md" -f $BucketId.ToLowerInvariant())
Set-Content -LiteralPath $summaryBody -Value $summaryLines -Encoding UTF8
for ($attempt = 1; $attempt -le 5; $attempt += 1) {
    gh issue comment $ParentIssue --repo $IssueRepo --body-file $summaryBody | Out-Null
    if ($LASTEXITCODE -eq 0) {
        break
    }
    if ($attempt -ge 5) {
        throw "gh issue comment failed for parent #$ParentIssue"
    }
    Start-Sleep -Seconds (5 * $attempt)
}

Write-Host "gen-parity-case-sync: PASS"
Write-Host ("  bucket={0}" -f $BucketId)
Write-Host ("  parent_issue=#{0}" -f $ParentIssue)
Write-Host ("  total_cases={0}" -f $caseEntries.Count)
Write-Host ("  created={0}" -f ((@($resultRows | Where-Object { $_.action -eq 'created' })).Count))
Write-Host ("  reused={0}" -f ((@($resultRows | Where-Object { $_.action -eq 'existing' })).Count))
