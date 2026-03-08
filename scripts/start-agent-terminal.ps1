param(
    [ValidateSet("codex", "gemini", "pwsh")]
    [string]$Agent = "codex",
    [string]$RepoRoot = "",
    [string]$WindowId = "0",
    [string]$TabTitle = "",
    [string[]]$AgentArgs = @(),
    [string]$CommandOverride = "",
    [switch]$CloseOnExit,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

function Quote-PwshLiteral {
    param([string]$Text)
    return "'" + $Text.Replace("'", "''") + "'"
}

function Resolve-WtPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wt.exe"),
        "wt.exe"
    )

    foreach ($candidate in $candidates) {
        if ([System.IO.Path]::IsPathRooted($candidate)) {
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
            continue
        }

        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) {
            return $cmd.Source
        }
    }

    throw "Windows Terminal (wt.exe) was not found."
}

function Resolve-AgentPath {
    param([string]$AgentName)

    if ($AgentName -eq "pwsh") {
        $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        $cmd = Get-Command powershell -ErrorAction Stop
        return $cmd.Source
    }

    $cmd = Get-Command $AgentName -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $ps1 = Get-Command ("{0}.ps1" -f $AgentName) -ErrorAction SilentlyContinue
    if ($ps1) { return $ps1.Source }

    throw "Agent command not found: $AgentName"
}

function Build-AgentCommand {
    param(
        [string]$AgentPath,
        [string[]]$AgentArgs
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add("&")
    $parts.Add((Quote-PwshLiteral -Text $AgentPath))
    foreach ($arg in $AgentArgs) {
        $parts.Add((Quote-PwshLiteral -Text $arg))
    }
    return ($parts -join " ")
}

$wtPath = Resolve-WtPath
$agentPath = Resolve-AgentPath -AgentName $Agent

if (-not $TabTitle) {
    $repoName = Split-Path -Leaf $RepoRoot
    $TabTitle = "{0}:{1}" -f $Agent, $repoName
}

$commandText = if ($CommandOverride) {
    $CommandOverride
} else {
    $agentCommand = Build-AgentCommand -AgentPath $agentPath -AgentArgs $AgentArgs
    "Set-Location -LiteralPath {0}; {1}" -f (Quote-PwshLiteral -Text $RepoRoot), $agentCommand
}

$pwshPath = Resolve-AgentPath -AgentName "pwsh"
$wtArgs = New-Object System.Collections.Generic.List[string]
$wtArgs.Add("-w")
$wtArgs.Add($WindowId)
$wtArgs.Add("new-tab")
$wtArgs.Add("--title")
$wtArgs.Add($TabTitle)
$wtArgs.Add($pwshPath)
$wtArgs.Add("-NoLogo")
$wtArgs.Add("-NoProfile")
if (-not $CloseOnExit) {
    $wtArgs.Add("-NoExit")
}
$wtArgs.Add("-Command")
$wtArgs.Add($commandText)

if ($DryRun) {
    Write-Host "start-agent-terminal: DRY RUN"
    Write-Host ("  wt={0}" -f $wtPath)
    Write-Host ("  agent={0}" -f $agentPath)
    Write-Host ("  title={0}" -f $TabTitle)
    Write-Host ("  repo={0}" -f $RepoRoot)
    Write-Host ("  command={0}" -f $commandText)
    exit 0
}

$proc = Start-Process -FilePath $wtPath -ArgumentList $wtArgs -WorkingDirectory $RepoRoot -PassThru

Write-Host "start-agent-terminal: STARTED"
Write-Host ("  wt_pid={0}" -f $proc.Id)
Write-Host ("  title={0}" -f $TabTitle)
Write-Host ("  agent={0}" -f $Agent)
Write-Host ("  repo={0}" -f $RepoRoot)
