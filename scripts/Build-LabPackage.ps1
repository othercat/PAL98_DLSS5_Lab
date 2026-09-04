[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceGameRoot,

    [Parameter(Mandatory = $true)]
    [string]$DependencyBundleRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [ValidateSet('DxwrapperD3D9Chain', 'DgVoodooDirectDraw')]
    [string]$Route = 'DxwrapperD3D9Chain',

    [ValidateSet('Personal', 'Friend')]
    [string]$PackageAudience = 'Personal',

    [string]$BaselinePath,

    [string]$TestSavePath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Test-PathInside {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Parent
    )
    $candidateFull = Get-FullPath $Candidate
    $parentFull = Get-FullPath $Parent
    return $candidateFull.StartsWith($parentFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-SafeRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "$Label must be a non-empty relative path: $RelativePath"
    }
    $segments = $RelativePath -split '[\\/]'
    if ($segments -contains '..' -or $segments -contains '.') {
        throw "$Label contains an unsafe path segment: $RelativePath"
    }
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Set-IniValueStrict {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $lines = [System.IO.File]::ReadAllLines($Path)
    $currentSection = $null
    $matchIndex = -1
    $replacement = $null
    for ($index = 0; $index -lt $lines.Length; $index++) {
        $sectionMatch = [regex]::Match($lines[$index], '^\s*\[([^]]+)\]\s*(?:[;#].*)?$')
        if ($sectionMatch.Success) {
            $currentSection = $sectionMatch.Groups[1].Value.Trim()
            continue
        }
        if ($currentSection -ieq $Section) {
            $keyMatch = [regex]::Match(
                $lines[$index],
                '^(\s*' + [regex]::Escape($Key) + '\s*=\s*)([^;#]*?)(\s*(?:[;#].*)?)$')
            if ($keyMatch.Success) {
                if ($matchIndex -ge 0) {
                    throw "Duplicate [$Section] $Key entry in $Path"
                }
                $matchIndex = $index
                $replacement = $keyMatch.Groups[1].Value + $Value + $keyMatch.Groups[3].Value
            }
        }
    }
    if ($matchIndex -lt 0) {
        throw "Missing [$Section] $Key entry in $Path"
    }
    $lines[$matchIndex] = $replacement
    [System.IO.File]::WriteAllLines($Path, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-PeMachine {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = $null
    $reader = $null
    try {
        $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $reader = New-Object System.IO.BinaryReader($stream)
        if ($stream.Length -lt 68 -or $reader.ReadUInt16() -ne 0x5A4D) { return 'not-pe' }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -le 0 -or ($peOffset + 6) -gt $stream.Length) { return 'not-pe' }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { return 'not-pe' }
        $machine = $reader.ReadUInt16()
        if ($machine -eq 0x014C) { return 'x86' }
        if ($machine -eq 0x8664) { return 'x64' }
        return ('machine-0x{0:X4}' -f $machine)
    }
    finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }
}

function Set-IniSetting {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $sourceLines = @(Get-Content -LiteralPath $Path)
    $result = New-Object 'System.Collections.Generic.List[string]'
    $insideTarget = $false
    $sectionFound = $false
    $keyFound = $false

    foreach ($line in $sourceLines) {
        $sectionMatch = [regex]::Match($line, '^\s*\[([^]]+)\]\s*$')
        if ($sectionMatch.Success) {
            if ($insideTarget -and -not $keyFound) {
                $result.Add("$Key = $Value")
                $keyFound = $true
            }
            $insideTarget = ($sectionMatch.Groups[1].Value -ieq $Section)
            if ($insideTarget) {
                $sectionFound = $true
            }
            $result.Add($line)
            continue
        }

        if ($insideTarget -and $line -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $result.Add("$Key = $Value")
            $keyFound = $true
        }
        else {
            $result.Add($line)
        }
    }

    if (-not $sectionFound) {
        if ($result.Count -gt 0 -and $result[$result.Count - 1] -ne '') {
            $result.Add('')
        }
        $result.Add("[$Section]")
        $result.Add("$Key = $Value")
    }
    elseif ($insideTarget -and -not $keyFound) {
        $result.Add("$Key = $Value")
    }

    [System.IO.File]::WriteAllLines($Path, $result, [System.Text.Encoding]::ASCII)
}

function Add-Check {
    param(
        [Parameter(Mandatory = $true)]$List,
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Kind
    )
    Assert-SafeRelativePath -RelativePath $RelativePath -Label 'check path'
    $absolutePath = Join-Path $PackageRoot $RelativePath
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        throw "Cannot add missing file to package checks: $RelativePath"
    }
    $List.Add([pscustomobject]@{
        path = ($RelativePath -replace '\\', '/')
        sha256 = Get-Sha256 $absolutePath
        kind = $Kind
    })
}

$repoRoot = Get-FullPath (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $repoRoot 'config\pal98-v1.61-classic-v5-baseline.json'
}
$startChineseName = ([string][char]0x5F00) + ([char]0x59CB) + 'DLSS5' + ([char]0x6D4B) + ([char]0x8BD5) + '.cmd'
$preflightChineseName = ([string][char]0x4EC5) + ([char]0x68C0) + ([char]0x67E5) + 'DLSS5' + ([char]0x73AF) + ([char]0x5883) + '.cmd'
$windowedChineseName = ([string][char]0x542F) + ([char]0x52A8) + '640x400' + ([char]0x7A97) + ([char]0x53E3) + '.cmd'
$sourceRoot = Get-FullPath $SourceGameRoot
$bundleRoot = Get-FullPath $DependencyBundleRoot
$outputFull = Get-FullPath $OutputRoot
$baselineFull = Get-FullPath $BaselinePath

if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Source game root does not exist: $sourceRoot"
}
if (-not (Test-Path -LiteralPath $bundleRoot -PathType Container)) {
    throw "Dependency bundle root does not exist: $bundleRoot"
}
if (-not (Test-Path -LiteralPath $baselineFull -PathType Leaf)) {
    throw "Baseline file does not exist: $baselineFull"
}
if ($outputFull -ieq $sourceRoot -or (Test-PathInside -Candidate $outputFull -Parent $sourceRoot)) {
    throw 'OutputRoot must not be the source game root or a child of it.'
}
if (Test-Path -LiteralPath $outputFull) {
    throw "OutputRoot already exists. Choose a new directory: $outputFull"
}
if ($TestSavePath -and -not (Test-Path -LiteralPath $TestSavePath -PathType Leaf)) {
    throw "Test save does not exist: $TestSavePath"
}

$baseline = Get-Content -LiteralPath $baselineFull -Raw -Encoding UTF8 | ConvertFrom-Json
if ($baseline.schema -ne 'PAL98.DLSS5Lab.SourceBaseline.v1') {
    throw "Unsupported baseline schema: $($baseline.schema)"
}

$sourceChecks = New-Object 'System.Collections.Generic.List[object]'
foreach ($entry in @($baseline.files)) {
    Assert-SafeRelativePath -RelativePath ([string]$entry.path) -Label 'baseline path'
    $sourceFile = Join-Path $sourceRoot ([string]$entry.path)
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Source baseline file is missing: $($entry.path)"
    }
    $actualHash = Get-Sha256 $sourceFile
    $expectedHash = ([string]$entry.sha256).ToUpperInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Source baseline hash mismatch for $($entry.path). Expected $expectedHash, got $actualHash"
    }
    $sourceChecks.Add([pscustomobject]@{ path = ([string]$entry.path -replace '\\', '/'); sha256 = $actualHash })
}

$bundleManifestPath = Join-Path $bundleRoot 'bundle.manifest.json'
if (-not (Test-Path -LiteralPath $bundleManifestPath -PathType Leaf)) {
    throw "Dependency manifest is missing: $bundleManifestPath"
}
$bundle = Get-Content -LiteralPath $bundleManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($bundle.schema -ne 'PAL98.DLSS5Lab.DependencyBundle.v1') {
    throw "Unsupported dependency bundle schema: $($bundle.schema)"
}

$selectedFiles = @($bundle.files | Where-Object {
    $routes = @($_.routes)
    ($routes -contains 'all') -or ($routes -contains $Route)
})

$commonSingleRoles = @(
    'reshade_x86', 'feeder_addon32', 'feeder_shader',
    'reshade_fxh', 'reshade_ui_fxh', 'drawtext_fxh',
    'host64_exe', 'reshade_x64', 'neural_consumer', 'nvngx_dlssnr',
    'nvngx_dlss', 'dgvoodoo_config'
)
$routeRole = if ($Route -eq 'DxwrapperD3D9Chain') { 'dgvoodoo_d3d9_x86' } else { 'dgvoodoo_ddraw_x86' }
$requiredSingleRoles = @($commonSingleRoles + $routeRole)

foreach ($role in $requiredSingleRoles) {
    $matches = @($selectedFiles | Where-Object { $_.role -eq $role })
    if ($matches.Count -ne 1) {
        throw "Selected route requires exactly one dependency with role '$role'; found $($matches.Count)."
    }
}
$motionVectorFiles = @($selectedFiles | Where-Object { $_.role -eq 'motion_vectors' })
if ($motionVectorFiles.Count -lt 1) {
    throw "Selected route requires at least one dependency with role 'motion_vectors'."
}

$destinationSet = @{}
$validatedDependencies = New-Object 'System.Collections.Generic.List[object]'
$reservedDestinations = @(
    'reshade.ini',
    'reshadepreset.ini',
    'host64\reshade.ini',
    'dlss5-lab',
    'start-dlss5-test.cmd',
    'preflight-dlss5-test.cmd',
    ($startChineseName.ToLowerInvariant()),
    ($preflightChineseName.ToLowerInvariant()),
    ($windowedChineseName.ToLowerInvariant())
)
foreach ($entry in $selectedFiles) {
    $relativeSource = [string]$entry.path
    $relativeDestination = [string]$entry.destination
    Assert-SafeRelativePath -RelativePath $relativeSource -Label 'dependency path'
    Assert-SafeRelativePath -RelativePath $relativeDestination -Label 'dependency destination'

    $destinationKey = ($relativeDestination -replace '/', '\').ToLowerInvariant()
    if ($destinationKey -eq 'dlss5-lab' -or $destinationKey.StartsWith('dlss5-lab\') -or $reservedDestinations -contains $destinationKey) {
        throw "Dependency destination is reserved by the lab runtime: $relativeDestination"
    }
    if ($destinationSet.ContainsKey($destinationKey)) {
        throw "Duplicate dependency destination: $relativeDestination"
    }
    $destinationSet[$destinationKey] = $true

    if ($PackageAudience -eq 'Friend' -and ([string]$entry.redistribution -ine 'redistributable')) {
        throw "Friend package is blocked by redistribution status '$($entry.redistribution)' for role '$($entry.role)'."
    }

    $sourceDependency = Join-Path $bundleRoot $relativeSource
    if (-not (Test-Path -LiteralPath $sourceDependency -PathType Leaf)) {
        throw "Dependency file is missing: $relativeSource"
    }
    $actualHash = Get-Sha256 $sourceDependency
    $expectedHash = ([string]$entry.sha256).ToUpperInvariant()
    if ($expectedHash -notmatch '^[0-9A-F]{64}$' -or $actualHash -ne $expectedHash) {
        throw "Dependency hash mismatch for $relativeSource. Expected $expectedHash, got $actualHash"
    }

    $expectedArchitecture = $null
    if (@('reshade_x86', 'feeder_addon32', 'dgvoodoo_d3d9_x86', 'dgvoodoo_ddraw_x86') -contains [string]$entry.role) {
        $expectedArchitecture = 'x86'
    }
    elseif (@('host64_exe', 'reshade_x64', 'neural_consumer', 'nvngx_dlssnr', 'nvngx_dlss') -contains [string]$entry.role) {
        $expectedArchitecture = 'x64'
    }
    if ($expectedArchitecture) {
        $actualArchitecture = Get-PeMachine $sourceDependency
        if ($actualArchitecture -ne $expectedArchitecture) {
            throw "Dependency architecture mismatch for role '$($entry.role)'. Expected $expectedArchitecture, got $actualArchitecture."
        }
        $isHostDestination = $destinationKey.StartsWith('host64\')
        if ($expectedArchitecture -eq 'x64' -and -not $isHostDestination) {
            throw "64-bit dependency role '$($entry.role)' must be placed under host64/: $relativeDestination"
        }
        if ($expectedArchitecture -eq 'x86' -and $isHostDestination) {
            throw "32-bit dependency role '$($entry.role)' must not be placed under host64/: $relativeDestination"
        }
    }

    $validatedDependencies.Add([pscustomobject]@{
        path = ($relativeSource -replace '\\', '/')
        destination = ($relativeDestination -replace '\\', '/')
        role = [string]$entry.role
        sha256 = $actualHash
        source_url = [string]$entry.source_url
        license = [string]$entry.license
        redistribution = [string]$entry.redistribution
    })
}

$selectedDestinationNames = @($validatedDependencies | ForEach-Object { [System.IO.Path]::GetFileName([string]$_.destination).ToLowerInvariant() })
if ($selectedDestinationNames -contains 'dlss5-dx11-bridge.addon64') {
    throw 'dlss5-dx11-bridge.addon64 must not be combined with DLSS5-Feeder.'
}
$consumerAddonNames = @('deep-fried-chicken.addon64', 'renodx-dlss5.addon64', 'alexs-toolkit.addon64')
$consumerAddonCount = @($selectedDestinationNames | Where-Object { $consumerAddonNames -contains $_ }).Count
if ($consumerAddonCount -gt 1) {
    throw 'More than one neural consumer add-on was selected. Keep exactly one consumer.'
}

$stageRoot = $outputFull + '.partial-' + [guid]::NewGuid().ToString('N')
$stageCreated = $false
try {
    $outputParent = Split-Path -Parent $outputFull
    if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
        New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    }
    New-Item -ItemType Directory -Path $stageRoot | Out-Null
    $stageCreated = $true

    $excludedDirectories = @(
        (Join-Path $sourceRoot '_codex_backups'),
        (Join-Path $sourceRoot 'blackscreen_logs'),
        (Join-Path $sourceRoot 'palmod\Profiles'),
        (Join-Path $sourceRoot 'palmod\TournamentLock\history')
    )
    $robocopyArgs = @(
        $sourceRoot, $stageRoot, '/E', '/COPY:DAT', '/DCOPY:DAT', '/R:1', '/W:1',
        '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/XD'
    ) + $excludedDirectories + @(
        '/XF', '*.RPG', '*.RPG.*', '*.log', '*.bak', '*.bak.*',
        'PALDLL_DX9_random_skills.txt', 'font_stats.txt', 'key.txt'
    )
    & robocopy.exe @robocopyArgs | Out-Null
    $robocopyCode = $LASTEXITCODE
    if ($robocopyCode -gt 7) {
        throw "robocopy failed with exit code $robocopyCode"
    }

    if ($Route -eq 'DgVoodooDirectDraw') {
        $rollbackRoot = Join-Path $stageRoot 'DLSS5-Lab\rollback\dxwrapper'
        New-Item -ItemType Directory -Path $rollbackRoot -Force | Out-Null
        foreach ($name in @('ddraw.dll', 'dxwrapper.dll', 'dxwrapper.ini')) {
            $originalPath = Join-Path $stageRoot $name
            if (-not (Test-Path -LiteralPath $originalPath -PathType Leaf)) {
                throw "DirectDraw route cannot preserve missing source file: $name"
            }
            Move-Item -LiteralPath $originalPath -Destination (Join-Path $rollbackRoot $name)
        }
    }

    foreach ($entry in $validatedDependencies) {
        $sourceDependency = Join-Path $bundleRoot ([string]$entry.path)
        $destination = Join-Path $stageRoot ([string]$entry.destination)
        if (Test-Path -LiteralPath $destination) {
            throw "Dependency overlay refuses to replace an existing file: $($entry.destination)"
        }
        $destinationParent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $sourceDependency -Destination $destination
    }

    if ($Route -eq 'DxwrapperD3D9Chain') {
        $dxwrapperIni = Join-Path $stageRoot 'dxwrapper.ini'
        if (-not (Test-Path -LiteralPath $dxwrapperIni -PathType Leaf)) {
            throw 'dxwrapper.ini is required for the chain route.'
        }
        Set-IniSetting -Path $dxwrapperIni -Section 'Compatibility' -Key 'D3d9HookSystem32' -Value '0'
    }

    if ($TestSavePath) {
        Copy-Item -LiteralPath $TestSavePath -Destination (Join-Path $stageRoot '1.RPG')
    }

    $templateCopies = [ordered]@{
        (Join-Path $repoRoot 'config\ReShade.ini') = (Join-Path $stageRoot 'ReShade.ini')
        (Join-Path $repoRoot 'config\ReShadePreset.ini') = (Join-Path $stageRoot 'ReShadePreset.ini')
        (Join-Path $repoRoot 'config\host64-ReShade.ini') = (Join-Path $stageRoot 'host64\ReShade.ini')
    }
    foreach ($template in $templateCopies.GetEnumerator()) {
        if (Test-Path -LiteralPath $template.Value) {
            throw "Lab configuration refuses to replace an existing file: $($template.Value.Substring($stageRoot.Length).TrimStart('\', '/'))"
        }
        $templateParent = Split-Path -Parent $template.Value
        if (-not (Test-Path -LiteralPath $templateParent -PathType Container)) {
            New-Item -ItemType Directory -Path $templateParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $template.Key -Destination $template.Value
    }

    if ($Route -eq 'DgVoodooDirectDraw') {
        $dgVoodooConfig = Join-Path $stageRoot 'dgVoodoo.conf'
        Set-IniValueStrict -Path $dgVoodooConfig -Section 'General' -Key 'FullScreenMode' -Value 'false'
        Set-IniValueStrict -Path $dgVoodooConfig -Section 'General' -Key 'CaptureMouse' -Value 'false'
        Set-IniValueStrict -Path $dgVoodooConfig -Section 'General' -Key 'CenterAppWindow' -Value 'true'
        Set-IniValueStrict -Path $dgVoodooConfig -Section 'GeneralExt' -Key 'ImageScaleFactor' -Value '2'
        Set-IniValueStrict -Path $dgVoodooConfig -Section 'DirectX' -Key 'AppControlledScreenMode' -Value 'false'
        Set-IniValueStrict -Path $dgVoodooConfig -Section 'DirectXExt' -Key 'Dithering' -Value 'disabled'
    }

    $labRuntimeRoot = Join-Path $stageRoot 'DLSS5-Lab'
    New-Item -ItemType Directory -Path $labRuntimeRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'runtime\Start-DLSS5Lab.ps1') -Destination $labRuntimeRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot 'runtime\Start-PAL-Windowed.ps1') -Destination $labRuntimeRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\Verify-LabPackage.ps1') -Destination $labRuntimeRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot 'runtime\Start-DLSS5-Test.cmd') -Destination (Join-Path $stageRoot 'Start-DLSS5-Test.cmd')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'runtime\Preflight-DLSS5-Test.cmd') -Destination (Join-Path $stageRoot 'Preflight-DLSS5-Test.cmd')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'runtime\README-FIRST.txt') -Destination (Join-Path $stageRoot 'README-FIRST.txt')
    Copy-Item -LiteralPath (Join-Path (Join-Path $repoRoot 'runtime') $startChineseName) -Destination (Join-Path $stageRoot $startChineseName)
    Copy-Item -LiteralPath (Join-Path (Join-Path $repoRoot 'runtime') $preflightChineseName) -Destination (Join-Path $stageRoot $preflightChineseName)
    if ($Route -eq 'DgVoodooDirectDraw') {
        Copy-Item -LiteralPath (Join-Path (Join-Path $repoRoot 'runtime') $windowedChineseName) -Destination (Join-Path $stageRoot $windowedChineseName)
    }

    $checks = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in $sourceChecks) {
        $sourceCheckPath = [string]$entry.path
        if ($Route -eq 'DgVoodooDirectDraw' -and @('ddraw.dll', 'dxwrapper.dll', 'dxwrapper.ini') -contains $sourceCheckPath) {
            $sourceCheckPath = 'DLSS5-Lab/rollback/dxwrapper/' + $sourceCheckPath
        }
        $sourceCheckKind = if ($sourceCheckPath -ieq 'config.ini') {
            'mutable-config-baseline'
        }
        elseif ($sourceCheckPath -ieq 'dxwrapper.ini') {
            'mutable-dxwrapper-config-baseline'
        }
        else {
            'source-baseline-final'
        }
        Add-Check -List $checks -PackageRoot $stageRoot -RelativePath $sourceCheckPath -Kind $sourceCheckKind
    }
    foreach ($entry in $validatedDependencies) {
        Add-Check -List $checks -PackageRoot $stageRoot -RelativePath ([string]$entry.destination) -Kind ('dependency:' + [string]$entry.role)
    }
    $runtimePaths = @(
        'DLSS5-Lab/Start-DLSS5Lab.ps1',
        'DLSS5-Lab/Start-PAL-Windowed.ps1',
        'DLSS5-Lab/Verify-LabPackage.ps1',
        'ReShade.ini',
        'ReShadePreset.ini',
        'host64/ReShade.ini',
        'README-FIRST.txt',
        'Start-DLSS5-Test.cmd',
        'Preflight-DLSS5-Test.cmd',
        $startChineseName,
        $preflightChineseName
    )
    if ($Route -eq 'DgVoodooDirectDraw') {
        $runtimePaths += $windowedChineseName
    }
    foreach ($relativePath in $runtimePaths) {
        $runtimeKind = if (@('ReShade.ini', 'ReShadePreset.ini', 'host64/ReShade.ini') -contains $relativePath) {
            'mutable-runtime-config-baseline'
        }
        else {
            'lab-runtime'
        }
        Add-Check -List $checks -PackageRoot $stageRoot -RelativePath $relativePath -Kind $runtimeKind
    }
    if ($TestSavePath) {
        Add-Check -List $checks -PackageRoot $stageRoot -RelativePath '1.RPG' -Kind 'explicit-test-save'
    }
    $packageManifest = [ordered]@{
        schema = 'PAL98.DLSS5Lab.PackageManifest.v1'
        built_at_utc = [DateTime]::UtcNow.ToString('o')
        route = $Route
        audience = $PackageAudience
        test_save_included = [bool]$TestSavePath
        source_copy_policy = 'exclude-saves-logs-backups-profiles-and-tournament-history'
        source = [ordered]@{
            root_at_build_time = $sourceRoot
            baseline_id = [string]$baseline.baseline_id
            files = $sourceChecks.ToArray()
        }
        dependency_bundle = [ordered]@{
            bundle_id = [string]$bundle.bundle_id
            files = $validatedDependencies.ToArray()
        }
        checks = $checks.ToArray()
    }
    $manifestPath = Join-Path $labRuntimeRoot 'lab-package.manifest.json'
    $manifestJson = $packageManifest | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($manifestPath, $manifestJson + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))

    Move-Item -LiteralPath $stageRoot -Destination $outputFull
    $stageCreated = $false
    Write-Host "Package built successfully: $outputFull"
    Write-Host "Route: $Route"
    Write-Host "Audience: $PackageAudience"
    Write-Host 'Run Preflight-DLSS5-Test.cmd before the first game launch.'
}
finally {
    if ($stageCreated -and (Test-Path -LiteralPath $stageRoot)) {
        $expectedParent = Get-FullPath (Split-Path -Parent $outputFull)
        if ((Test-PathInside -Candidate $stageRoot -Parent $expectedParent) -and ([System.IO.Path]::GetFileName($stageRoot) -like ([System.IO.Path]::GetFileName($outputFull) + '.partial-*'))) {
            Remove-Item -LiteralPath $stageRoot -Recurse -Force
        }
    }
}
