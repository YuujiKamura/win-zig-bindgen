<#
.SYNOPSIS
    Verifies com.zig IID and vtable method order against cppwinrt-generated C++ headers.
.DESCRIPTION
    Uses cppwinrt.exe to generate reference C++ headers from WinMD files, then compares
    IIDs and vtable method ordering against a com.zig file.
.EXAMPLE
    pwsh -File verify-abi.ps1 -ComZig "path/to/com.zig" -WinmdPath "path/to/Microsoft.UI.Xaml.winmd"
#>
param(
    [Parameter(Mandatory)][string]$ComZig,
    [Parameter(Mandatory)][string]$WinmdPath,
    [string[]]$Interfaces = @(),
    [string]$CppWinrtExe = "",
    [string]$RefDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- 1. Locate cppwinrt.exe ---
if (-not $CppWinrtExe) {
    $candidates = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\cppwinrt.exe" -ErrorAction SilentlyContinue |
        Sort-Object { $_.Directory.Parent.Name } -Descending
    if ($candidates.Count -eq 0) {
        Write-Error "cppwinrt.exe not found in Windows SDK. Specify -CppWinrtExe."
        exit 1
    }
    $CppWinrtExe = $candidates[0].FullName
}
Write-Host "cppwinrt: $CppWinrtExe"

# --- Resolve paths ---
$ComZig = (Resolve-Path $ComZig).Path
$WinmdPath = (Resolve-Path $WinmdPath).Path
$winmdDir = Split-Path $WinmdPath -Parent

if (-not $RefDir) {
    $RefDir = Join-Path (Split-Path $ComZig -Parent) "tmp" "cppwinrt_ref"
}

# --- Locate system WinMD ---
$sysWinmdCandidates = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\UnionMetadata\*\Windows.winmd" -ErrorAction SilentlyContinue |
    Where-Object { $_.Directory.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Directory.Name } -Descending
if ($sysWinmdCandidates.Count -eq 0) {
    Write-Error "System Windows.winmd not found in UnionMetadata."
    exit 1
}
$sysWinmd = $sysWinmdCandidates[0].FullName

# --- Detect additional ref directories (uap10.0.xxxxx siblings) ---
$parentDir = Split-Path $winmdDir -Parent
$additionalRefs = @()
Get-ChildItem $parentDir -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^uap10\.0\.\d+$' -and $_.FullName -ne $winmdDir
} | ForEach-Object {
    $additionalRefs += $_.FullName
}

# --- 1. Generate cppwinrt reference (with cache check) ---
$timestampFile = Join-Path $RefDir ".winmd_timestamp"
$winmdTime = (Get-Item $WinmdPath).LastWriteTimeUtc.ToString("o")
$needRegen = $true

if (Test-Path $timestampFile) {
    $cached = Get-Content $timestampFile -Raw
    if ($cached.Trim() -eq $winmdTime) {
        $needRegen = $false
        Write-Host "cppwinrt cache valid, skipping regeneration."
    }
}

if ($needRegen) {
    if (Test-Path $RefDir) { Remove-Item $RefDir -Recurse -Force }
    New-Item -ItemType Directory -Path $RefDir -Force | Out-Null

    $args_list = @("-in", $WinmdPath, "-ref", $sysWinmd, "-ref", $winmdDir)
    foreach ($ref in $additionalRefs) {
        $args_list += @("-ref", $ref)
    }
    $args_list += @("-out", $RefDir)

    Write-Host "Running: cppwinrt $($args_list -join ' ')"
    & $CppWinrtExe @args_list 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "cppwinrt failed with exit code $LASTEXITCODE"
        exit 1
    }

    $winmdTime | Set-Content $timestampFile
    Write-Host "cppwinrt headers generated in $RefDir"
}

# --- 2. Parse cppwinrt headers: IID + vtable methods ---
$cppIIDs = @{}       # interface name -> IID string (uppercase)
$cppMethods = @{}    # interface name -> ordered method names

$headerFiles = Get-ChildItem $RefDir -Recurse -Filter "*.0.h"
foreach ($hf in $headerFiles) {
    $content = Get-Content $hf.FullName -Raw

    # Extract IIDs from guid_v lines
    # Pattern: guid_v<winrt::...::IFoo>{ ... }; // XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
    $iidMatches = [regex]::Matches($content, 'guid_v<winrt::[\w.:]+::(\w+)>\{[^;]+\};\s*//\s*([0-9A-Fa-f-]+)')
    foreach ($m in $iidMatches) {
        $ifName = $m.Groups[1].Value
        $iid = $m.Groups[2].Value.ToUpper()
        $cppIIDs[$ifName] = $iid
    }

    # Extract vtable methods from abi structs
    # Pattern: template <> struct abi<winrt::...::IFoo> { struct ... : inspectable_abi { virtual ... } };
    $abiMatches = [regex]::Matches($content, '(?s)struct abi<winrt::[\w.:]+::(\w+)>\s*\{[^{]*inspectable_abi\s*\{(.*?)\}\s*;\s*\}')
    foreach ($m in $abiMatches) {
        $ifName = $m.Groups[1].Value
        $body = $m.Groups[2].Value
        $methods = [System.Collections.Generic.List[string]]::new()
        $methodMatches = [regex]::Matches($body, 'virtual\s+int32_t\s+__stdcall\s+(\w+)\(')
        foreach ($mm in $methodMatches) {
            $methods.Add($mm.Groups[1].Value)
        }
        $cppMethods[$ifName] = $methods
    }
}

Write-Host "Parsed $($cppIIDs.Count) IIDs and $($cppMethods.Count) vtable definitions from cppwinrt headers."

# --- 3. Parse com.zig: interfaces, IIDs, vtable methods ---
$zigContent = Get-Content $ComZig -Raw

$zigIIDs = @{}
$zigMethods = @{}
$zigInterfaceNames = [System.Collections.Generic.List[string]]::new()

# Find all interface definitions: pub const IFoo = extern struct {
$ifMatches = [regex]::Matches($zigContent, '(?m)^pub const (\w+) = extern struct \{')
foreach ($m in $ifMatches) {
    $ifName = $m.Groups[1].Value
    $zigInterfaceNames.Add($ifName)
}

# For each interface, extract IID and VTable methods
foreach ($ifName in $zigInterfaceNames) {
    # Find the block for this interface
    $blockPattern = "(?s)pub const $([regex]::Escape($ifName)) = extern struct \{"
    $blockMatch = [regex]::Match($zigContent, $blockPattern)
    if (-not $blockMatch.Success) { continue }

    $startIdx = $blockMatch.Index + $blockMatch.Length

    # Extract IID: pub const IID = GUID{ .Data1 = 0x..., .Data2 = 0x..., .Data3 = 0x..., .Data4 = .{ 0x.., ... } };
    # We need to find the IID within this interface's block
    $iidPattern = 'pub const IID = GUID\{\s*\.Data1\s*=\s*0x([0-9a-fA-F]+),\s*\.Data2\s*=\s*0x([0-9a-fA-F]+),\s*\.Data3\s*=\s*0x([0-9a-fA-F]+),\s*\.Data4\s*=\s*\.\{\s*0x([0-9a-fA-F]+),\s*0x([0-9a-fA-F]+),\s*0x([0-9a-fA-F]+),\s*0x([0-9a-fA-F]+),\s*0x([0-9a-fA-F]+),\s*0x([0-9a-fA-F]+),\s*0x([0-9a-fA-F]+),\s*0x([0-9a-fA-F]+)\s*\}'
    $remaining = $zigContent.Substring($startIdx, [Math]::Min(5000, $zigContent.Length - $startIdx))
    $iidMatch = [regex]::Match($remaining, $iidPattern)
    if ($iidMatch.Success) {
        $d1 = $iidMatch.Groups[1].Value.PadLeft(8, '0').ToUpper()
        $d2 = $iidMatch.Groups[2].Value.PadLeft(4, '0').ToUpper()
        $d3 = $iidMatch.Groups[3].Value.PadLeft(4, '0').ToUpper()
        $d4_0 = $iidMatch.Groups[4].Value.PadLeft(2, '0').ToUpper()
        $d4_1 = $iidMatch.Groups[5].Value.PadLeft(2, '0').ToUpper()
        $d4_2 = $iidMatch.Groups[6].Value.PadLeft(2, '0').ToUpper()
        $d4_3 = $iidMatch.Groups[7].Value.PadLeft(2, '0').ToUpper()
        $d4_4 = $iidMatch.Groups[8].Value.PadLeft(2, '0').ToUpper()
        $d4_5 = $iidMatch.Groups[9].Value.PadLeft(2, '0').ToUpper()
        $d4_6 = $iidMatch.Groups[10].Value.PadLeft(2, '0').ToUpper()
        $d4_7 = $iidMatch.Groups[11].Value.PadLeft(2, '0').ToUpper()
        $iid = "$d1-$d2-$d3-$d4_0$d4_1-$d4_2$d4_3$d4_4$d4_5$d4_6$d4_7"
        $zigIIDs[$ifName] = $iid
    }

    # Extract VTable methods
    # Find VTable = extern struct { ... } within this interface block
    $vtblPattern = '(?s)pub const VTable = extern struct \{(.*?)\};'
    $vtblMatch = [regex]::Match($remaining, $vtblPattern)
    if ($vtblMatch.Success) {
        $vtblBody = $vtblMatch.Groups[1].Value
        # Extract all field names (each line like: FieldName: ...)
        $fieldMatches = [regex]::Matches($vtblBody, '(?m)^\s+(\w+)\s*:')
        $allFields = [System.Collections.Generic.List[string]]::new()
        foreach ($fm in $fieldMatches) {
            $allFields.Add($fm.Groups[1].Value)
        }
        # Skip first 6 entries (QueryInterface, AddRef, Release, GetIids, GetRuntimeClassName, GetTrustLevel)
        # But some interfaces (IUnknown, IInspectable) have fewer base entries
        # Detect: if has GetIids -> skip 6, if has only QI/AddRef/Release -> skip 3
        $skipCount = 0
        if ($allFields.Count -ge 6 -and $allFields[3] -eq "GetIids") {
            $skipCount = 6
        } elseif ($allFields.Count -ge 3 -and $allFields[0] -eq "QueryInterface") {
            # IUnknown-derived without IInspectable (e.g., ISwapChainPanelNative, IWindowNative)
            # Check if 4th field is GetIids
            if ($allFields.Count -ge 4 -and $allFields[3] -eq "GetIids") {
                $skipCount = 6
            } else {
                $skipCount = 3
            }
        }

        $methods = [System.Collections.Generic.List[string]]::new()
        for ($i = $skipCount; $i -lt $allFields.Count; $i++) {
            $methods.Add($allFields[$i])
        }
        $zigMethods[$ifName] = $methods
    }
}

Write-Host "Parsed $($zigIIDs.Count) IIDs and $($zigMethods.Count) vtable definitions from com.zig."

# --- 4. Compare ---
if ($Interfaces.Count -eq 0) {
    $Interfaces = $zigInterfaceNames.ToArray()
}

$passed = 0
$errors = 0
$warnings = 0
$skipped = 0
$errorDetails = [System.Collections.Generic.List[string]]::new()

foreach ($ifName in $Interfaces) {
    # Skip interfaces not in cppwinrt reference (Windows.Foundation etc from other WinMDs)
    if (-not $cppIIDs.ContainsKey($ifName) -and -not $cppMethods.ContainsKey($ifName)) {
        Write-Host "  SKIP  $ifName (not in cppwinrt reference)"
        $skipped++
        continue
    }

    $ifErrors = $false

    # Compare IID
    if ($zigIIDs.ContainsKey($ifName) -and $cppIIDs.ContainsKey($ifName)) {
        if ($zigIIDs[$ifName] -ne $cppIIDs[$ifName]) {
            $msg = "  ERROR $ifName IID mismatch: zig=$($zigIIDs[$ifName]) cpp=$($cppIIDs[$ifName])"
            Write-Host $msg -ForegroundColor Red
            $errorDetails.Add($msg)
            $ifErrors = $true
        }
    }

    # Compare vtable method order
    if ($zigMethods.ContainsKey($ifName) -and $cppMethods.ContainsKey($ifName)) {
        $zm = $zigMethods[$ifName]
        $cm = $cppMethods[$ifName]

        if ($zm.Count -ne $cm.Count) {
            $msg = "  WARN  $ifName method count mismatch: zig=$($zm.Count) cpp=$($cm.Count)"
            Write-Host $msg -ForegroundColor Yellow
            $warnings++
        }

        $compareCount = [Math]::Min($zm.Count, $cm.Count)
        $orderOk = $true
        for ($i = 0; $i -lt $compareCount; $i++) {
            if ($zm[$i] -ne $cm[$i]) {
                # Allow overload naming difference: zig uses _N suffix, cppwinrt uses descriptive name
                # Both refer to the same vtable slot if the base name matches
                $zigBase = $zm[$i] -replace '_\d+$', ''
                $cppBase = $cm[$i]
                # Check if zig name is an _N variant of a method that shares the same prefix as cppwinrt name
                if ($zm[$i] -match '_\d+$' -and $cppBase.StartsWith($zigBase)) {
                    $msg = "  NOTE  $ifName slot $($i + 6) overload naming: zig=$($zm[$i]) cpp=$($cm[$i]) (OK)"
                    Write-Host $msg -ForegroundColor Cyan
                } else {
                    $msg = "  ERROR $ifName method order mismatch at slot $($i + 6): zig=$($zm[$i]) cpp=$($cm[$i])"
                    Write-Host $msg -ForegroundColor Red
                    $errorDetails.Add($msg)
                    $orderOk = $false
                    $ifErrors = $true
                }
            }
        }

        # Extra methods in zig that aren't in cpp
        if ($zm.Count -gt $cm.Count) {
            for ($i = $cm.Count; $i -lt $zm.Count; $i++) {
                $msg = "  ERROR $ifName extra method in zig at slot $($i + 6): $($zm[$i])"
                Write-Host $msg -ForegroundColor Red
                $errorDetails.Add($msg)
                $ifErrors = $true
            }
        }
    }

    if ($ifErrors) {
        $errors++
    } else {
        Write-Host "  PASS  $ifName"
        $passed++
    }
}

# --- Final summary ---
Write-Host ""
Write-Host "ABI Verification: $passed passed, $errors errors, $warnings warnings, $skipped skipped"

if ($errorDetails.Count -gt 0) {
    Write-Host ""
    Write-Host "Error details:" -ForegroundColor Red
    foreach ($d in $errorDetails) {
        Write-Host $d -ForegroundColor Red
    }
    exit 1
}

exit 0
