param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }

$scriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $scriptsDir)) {
    throw "scripts directory not found: $scriptsDir"
}

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host "lint-powershell: SKIP (PSScriptAnalyzer not installed)"
    exit 0
}

$result = Invoke-ScriptAnalyzer -Path $scriptsDir -Recurse -Severity Error
if ($result) {
    $result | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize
    throw "PowerShell lint failed"
}

Write-Host "lint-powershell: PASS"
exit 0

