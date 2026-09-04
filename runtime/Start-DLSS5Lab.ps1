[CmdletBinding()]
param(
    [switch]$PreflightOnly,

    [switch]$AllowUnsupportedDriver
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$labRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$packageRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $labRoot))
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$evidenceRoot = Join-Path $labRoot ('evidence\' + $timestamp)
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$preflightLog = Join-Path $evidenceRoot 'preflight.txt'
$minimumNvidiaDriver = [version]'616.64'

function Write-LabLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    Write-Host $line
    Add-Content -LiteralPath $preflightLog -Value $line -Encoding UTF8
}

try {
    Write-LabLog "Package root: $packageRoot"
    Write-LabLog "Windows 64-bit: $([Environment]::Is64BitOperatingSystem)"
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'This lab requires 64-bit Windows for the helper process.'
    }

    $manifestPath = Join-Path $labRoot 'lab-package.manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Package manifest is missing: $manifestPath"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-LabLog "Route: $($manifest.route)"
    Write-LabLog "Audience: $($manifest.audience)"

    & (Join-Path $labRoot 'Verify-LabPackage.ps1') -PackageRoot $packageRoot -AllowRuntimeState
    Write-LabLog 'Package hashes and route layout passed.'

    $palExe = Join-Path $packageRoot 'PAL.EXE'
    if (-not (Test-Path -LiteralPath $palExe -PathType Leaf)) {
        throw 'PAL.EXE is missing.'
    }

    $alreadyRunning = @(Get-CimInstance Win32_Process -Filter "Name='PAL.EXE'" -ErrorAction SilentlyContinue | Where-Object {
        try { ([System.IO.Path]::GetFullPath($_.ExecutablePath) -ieq $palExe) } catch { $false }
    })
    if ($alreadyRunning.Count -gt 0) {
        throw 'This package PAL.EXE is already running. Close it before continuing.'
    }

    $nvidiaSmi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    $hardwareBlock = $null
    if ($nvidiaSmi) {
        $gpuLines = @(& $nvidiaSmi.Source --query-gpu=name,driver_version --format=csv,noheader 2>&1)
        $rtx50Detected = $false
        $supportedDriverDetected = $false
        foreach ($gpuLine in $gpuLines) {
            Write-LabLog "GPU: $gpuLine"
            if ($gpuLine -match '(?i)RTX\s*50\d{2}') {
                $rtx50Detected = $true
            }
            if ($gpuLine -match ',\s*(\d+(?:\.\d+)+)\s*$') {
                $driverVersion = [version]$Matches[1]
                if ($driverVersion -ge $minimumNvidiaDriver) {
                    $supportedDriverDetected = $true
                }
            }
        }
        if (-not $rtx50Detected) {
            $hardwareBlock = 'No RTX 50-series GPU was detected.'
        }
        elseif (-not $supportedDriverDetected) {
            $hardwareBlock = "NVIDIA driver $minimumNvidiaDriver or newer is required for this DLSS 5 experiment."
        }
    }
    else {
        $hardwareBlock = 'nvidia-smi.exe was not found, so GPU and driver eligibility could not be verified.'
    }
    if ($hardwareBlock) {
        if ($AllowUnsupportedDriver) {
            Write-LabLog "WARNING: $hardwareBlock Hardware block was overridden for fixture/diagnostic use."
        }
        else {
            throw $hardwareBlock
        }
    }
    else {
        Write-LabLog "Hardware gate passed: RTX 50-series and NVIDIA driver $minimumNvidiaDriver or newer."
    }
    $reshadePath = Join-Path $packageRoot 'dxgi.dll'
    $reshadeVersionText = (Get-Item -LiteralPath $reshadePath).VersionInfo.FileVersion
    if ($reshadeVersionText -and $reshadeVersionText -match '(\d+\.\d+(?:\.\d+(?:\.\d+)?)?)') {
        $reshadeVersion = [version]$Matches[1]
        Write-LabLog "ReShade file version: $reshadeVersion"
        if ($reshadeVersion -lt [version]'6.8') {
            throw "ReShade 6.8 or newer is required; found $reshadeVersion."
        }
    }
    else {
        Write-LabLog 'WARNING: ReShade file version could not be read; the package hash still matched.'
    }
    Write-LabLog 'Before runtime testing, disable NVIDIA Smooth Motion and OptiScaler for PAL.EXE.'

    if ($PreflightOnly) {
        Write-LabLog 'Preflight-only mode completed. PAL.EXE was not started.'
        Write-Host "Evidence: $evidenceRoot"
        return
    }

    Write-LabLog 'Starting PAL.EXE. Close the game normally when testing is finished.'
    if ([string]$manifest.route -eq 'DgVoodooDirectDraw') {
        $windowHelper = Join-Path $labRoot 'Start-PAL-Windowed.ps1'
        if (-not (Test-Path -LiteralPath $windowHelper -PathType Leaf)) {
            throw "DirectDraw window helper is missing: $windowHelper"
        }
        Write-LabLog 'DirectDraw route: enforcing a draggable, centered 640x400 game client area.'
        $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $windowHelperArguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $windowHelper + '" -ClientWidth 640 -ClientHeight 400'
        $process = Start-Process -FilePath $windowsPowerShell -ArgumentList $windowHelperArguments -WindowStyle Hidden -PassThru -Wait
        Write-LabLog "PAL.EXE/window helper exit code: $($process.ExitCode)"
    }
    else {
        $process = Start-Process -FilePath $palExe -WorkingDirectory $packageRoot -PassThru -Wait
        Write-LabLog "PAL.EXE exit code: $($process.ExitCode)"
    }

    $knownLogs = @(
        'ReShade.log',
        'dlss5-feed.log',
        'deep-fried-chicken.log',
        'host64\dlss5-feed-host.log',
        'host64\ReShade.log',
        'host64\deep-fried-chicken.log',
        'dxwrapper-pal.log'
    )
    foreach ($relativeLog in $knownLogs) {
        $sourceLog = Join-Path $packageRoot $relativeLog
        if (Test-Path -LiteralPath $sourceLog -PathType Leaf) {
            $safeName = ($relativeLog -replace '[\\/]', '__')
            Copy-Item -LiteralPath $sourceLog -Destination (Join-Path $evidenceRoot $safeName) -Force
            Write-LabLog "Collected log: $relativeLog"
        }
    }

    $collectedText = @()
    foreach ($logFile in @(Get-ChildItem -LiteralPath $evidenceRoot -File -ErrorAction SilentlyContinue)) {
        if ($logFile.Name -ne 'preflight.txt') {
            $collectedText += Get-Content -LiteralPath $logFile.FullName -ErrorAction SilentlyContinue
        }
    }
    $joinedText = $collectedText -join [Environment]::NewLine
    if ($joinedText -match '(?i)feature\s+ready|frame\s+\d+\s+delivered|feature\s+18\s+created|inline\s+feature\s+18\s+evaluation\s+succeeded') {
        Write-LabLog 'A positive DLSS/Feeder readiness marker was found in collected logs.'
    }
    else {
        Write-LabLog 'No known readiness marker was found. This does not prove DLSS 5 was active.'
    }
    Write-Host "Evidence: $evidenceRoot"
}
catch {
    Write-LabLog ('FAILED: ' + $_.Exception.Message)
    Write-Host "Evidence: $evidenceRoot"
    throw
}
