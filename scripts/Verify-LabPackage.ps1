[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackageRoot,

    [switch]$AllowRuntimeState
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-SafeRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Unsafe manifest path: $RelativePath"
    }
    $segments = $RelativePath -split '[\\/]'
    if ($segments -contains '..' -or $segments -contains '.') {
        throw "Unsafe manifest path: $RelativePath"
    }
}

function Get-IniValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $currentSection = $null
    foreach ($line in @(Get-Content -LiteralPath $Path)) {
        $sectionMatch = [regex]::Match($line, '^\s*\[([^]]+)\]\s*(?:[;#].*)?$')
        if ($sectionMatch.Success) {
            $currentSection = $sectionMatch.Groups[1].Value.Trim()
            continue
        }
        if ($currentSection -ieq $Section) {
            $keyMatch = [regex]::Match($line, '^\s*' + [regex]::Escape($Key) + '\s*=\s*([^;#]*?)\s*(?:[;#].*)?$')
            if ($keyMatch.Success) {
                return $keyMatch.Groups[1].Value.Trim()
            }
        }
    }
    return $null
}

function Assert-MutableConfigPolicy {
    param([Parameter(Mandatory = $true)][string]$Path)
    $requirements = @(
        @{ Section = 'Patch'; Key = 'DefaultPatch'; Value = 'pal98fix-classic-v5' },
        @{ Section = 'NetworkBoundary'; Key = 'StrictOfflineMode'; Value = 'true' },
        @{ Section = 'NetworkBoundary'; Key = 'AudienceBridgeEnabled'; Value = 'false' },
        @{ Section = 'NetworkBoundary'; Key = 'AllowLoopbackIpc'; Value = 'false' }
    )
    foreach ($requirement in $requirements) {
        $actual = Get-IniValue -Path $Path -Section $requirement.Section -Key $requirement.Key
        if ($actual -ine $requirement.Value) {
            throw "Mutable config.ini requires [$($requirement.Section)] $($requirement.Key)=$($requirement.Value); found '$actual'."
        }
    }
}

function Assert-DxwrapperConfigPolicy {
    param([Parameter(Mandatory = $true)][string]$Path)
    $requirements = @(
        @{ Section = 'Compatibility'; Key = 'Dd7to9'; Value = '1' },
        @{ Section = 'Compatibility'; Key = 'D3d9HookSystem32'; Value = '0' },
        @{ Section = 'd3d9'; Key = 'EnableWindowMode'; Value = '1' },
        @{ Section = 'd3d9'; Key = 'FullscreenWindowMode'; Value = '0' },
        @{ Section = 'FullScreen'; Key = 'FullScreen'; Value = '0' }
    )
    foreach ($requirement in $requirements) {
        $actual = Get-IniValue -Path $Path -Section $requirement.Section -Key $requirement.Key
        if ($actual -ine $requirement.Value) {
            throw "Mutable dxwrapper.ini requires [$($requirement.Section)] $($requirement.Key)=$($requirement.Value); found '$actual'."
        }
    }
}

function Assert-DgVoodooDirectConfigPolicy {
    param([Parameter(Mandatory = $true)][string]$Path)
    $requirements = @(
        @{ Section = 'General'; Key = 'FullScreenMode'; Value = 'false' },
        @{ Section = 'General'; Key = 'CaptureMouse'; Value = 'false' },
        @{ Section = 'General'; Key = 'CenterAppWindow'; Value = 'true' },
        @{ Section = 'GeneralExt'; Key = 'ImageScaleFactor'; Value = '2' },
        @{ Section = 'DirectX'; Key = 'AppControlledScreenMode'; Value = 'false' },
        @{ Section = 'DirectXExt'; Key = 'Dithering'; Value = 'disabled' }
    )
    foreach ($requirement in $requirements) {
        $actual = Get-IniValue -Path $Path -Section $requirement.Section -Key $requirement.Key
        if ($actual -ine $requirement.Value) {
            throw "DirectDraw dgVoodoo.conf requires [$($requirement.Section)] $($requirement.Key)=$($requirement.Value); found '$actual'."
        }
    }
}

function Assert-ReShadeConfigPolicy {
    param([Parameter(Mandatory = $true)][string]$Path)
    $requirements = @(
        @{ Section = 'ADDON'; Key = 'AddonPath'; Value = '.\' },
        @{ Section = 'GENERAL'; Key = 'EffectSearchPaths'; Value = '.\reshade-shaders\Shaders\**' },
        @{ Section = 'GENERAL'; Key = 'PresetPath'; Value = '.\ReShadePreset.ini' }
    )
    foreach ($requirement in $requirements) {
        $actual = Get-IniValue -Path $Path -Section $requirement.Section -Key $requirement.Key
        if ($actual -ine $requirement.Value) {
            throw "Mutable ReShade.ini requires [$($requirement.Section)] $($requirement.Key)=$($requirement.Value); found '$actual'."
        }
    }
}

function Assert-ReShadePresetPolicy {
    param([Parameter(Mandatory = $true)][string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw
    if ($text -notmatch '(?im)^\s*Techniques\s*=\s*Lumenite_Kernel@lumenite_Kernel\.fx\s*,\s*DLSS5_Feed@DLSS5_Feed\.fx(?:\s*,|\s*$)') {
        throw 'Mutable ReShadePreset.ini must enable Lumenite_Kernel before DLSS5_Feed.'
    }
    $provider = Get-IniValue -Path $Path -Section 'DLSS5_Feed.fx' -Key 'PreprocessorDefinitions'
    if ($provider -notmatch '(?i)(^|,)\s*DLSS5_MV_PROVIDER=3\s*(,|$)') {
        throw "Mutable ReShadePreset.ini requires DLSS5_MV_PROVIDER=3; found '$provider'."
    }
}

function Assert-HostReShadeConfigPolicy {
    param([Parameter(Mandatory = $true)][string]$Path)
    foreach ($key in @('EffectSearchPaths', 'TextureSearchPaths')) {
        $actual = Get-IniValue -Path $Path -Section 'GENERAL' -Key $key
        if ($actual -ine '.\') {
            throw "Mutable host64/ReShade.ini requires [GENERAL] $key=.\; found '$actual'."
        }
    }
}

$root = [System.IO.Path]::GetFullPath($PackageRoot).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Package root does not exist: $root"
}

$manifestPath = Join-Path $root 'DLSS5-Lab\lab-package.manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Package manifest is missing: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schema -ne 'PAL98.DLSS5Lab.PackageManifest.v1') {
    throw "Unsupported package manifest schema: $($manifest.schema)"
}
if (@('DxwrapperD3D9Chain', 'DgVoodooDirectDraw') -notcontains [string]$manifest.route) {
    throw "Unsupported package route: $($manifest.route)"
}

$mutablePaths = @('config.ini', 'ReShade.ini', 'ReShadePreset.ini', 'host64/ReShade.ini')
if ($manifest.route -eq 'DxwrapperD3D9Chain') {
    $mutablePaths += 'dxwrapper.ini'
}
$verifiedCount = 0
$mutableChanges = @()
foreach ($entry in @($manifest.checks)) {
    $relativePath = [string]$entry.path
    Assert-SafeRelativePath $relativePath
    $filePath = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        throw "Checked package file is missing: $relativePath"
    }
    $actualHash = Get-Sha256 $filePath
    $expectedHash = ([string]$entry.sha256).ToUpperInvariant()
    if ($actualHash -ne $expectedHash) {
        if ($mutablePaths -contains $relativePath) {
            $mutableChanges += $relativePath
        }
        else {
            throw "Package hash mismatch for $relativePath. Expected $expectedHash, got $actualHash"
        }
    }
    $verifiedCount++
}

$configPath = Join-Path $root 'config.ini'
Assert-MutableConfigPolicy -Path $configPath
Assert-ReShadeConfigPolicy -Path (Join-Path $root 'ReShade.ini')
Assert-ReShadePresetPolicy -Path (Join-Path $root 'ReShadePreset.ini')
Assert-HostReShadeConfigPolicy -Path (Join-Path $root 'host64\ReShade.ini')
if ($mutableChanges.Count -gt 0) {
    Write-Host ('Mutable configuration differs from the build baseline; required lab safety keys passed: ' + ($mutableChanges -join ', '))
}

if ($manifest.route -eq 'DxwrapperD3D9Chain') {
    foreach ($name in @('ddraw.dll', 'dxwrapper.dll', 'dxwrapper.ini', 'd3d9.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)) {
            throw "Chain route file is missing: $name"
        }
    }
    Assert-DxwrapperConfigPolicy -Path (Join-Path $root 'dxwrapper.ini')
}
else {
    foreach ($name in @('ddraw.dll', 'dgVoodoo.conf')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)) {
            throw "DirectDraw route file is missing: $name"
        }
    }
    foreach ($name in @('ddraw.dll', 'dxwrapper.dll', 'dxwrapper.ini')) {
        $rollbackPath = Join-Path $root ('DLSS5-Lab\rollback\dxwrapper\' + $name)
        if (-not (Test-Path -LiteralPath $rollbackPath -PathType Leaf)) {
            throw "DirectDraw rollback file is missing: $name"
        }
    }
    Assert-DgVoodooDirectConfigPolicy -Path (Join-Path $root 'dgVoodoo.conf')
}

$explicitSaveAllowed = ($manifest.PSObject.Properties.Name -contains 'test_save_included') -and [bool]$manifest.test_save_included
if ($explicitSaveAllowed) {
    $saveChecks = @($manifest.checks | Where-Object { $_.path -ieq '1.RPG' -and $_.kind -eq 'explicit-test-save' })
    if ($saveChecks.Count -ne 1) {
        throw 'Manifest allows an explicit test save but does not check exactly one 1.RPG.'
    }
}
if (-not $AllowRuntimeState) {
    $privateFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
        $relative = $_.FullName.Substring($root.Length).TrimStart('\', '/')
        if ($relative -like 'DLSS5-Lab\evidence\*') { return $false }
        if ($explicitSaveAllowed -and $relative -ieq '1.RPG') { return $false }
        return ($relative -match '(?i)^(_codex_backups|blackscreen_logs|palmod\\Profiles|palmod\\TournamentLock\\history)\\') -or
            ($_.Name -match '(?i)\.RPG($|\.)|\.log$|\.bak($|\.)') -or
            ($_.Name -in @('PALDLL_DX9_random_skills.txt', 'font_stats.txt', 'key.txt'))
    })
    if ($privateFiles.Count -gt 0) {
        throw ('Package contains excluded private/runtime files: ' + (($privateFiles | ForEach-Object { $_.FullName.Substring($root.Length).TrimStart('\', '/') }) -join ', '))
    }
}

Write-Host "Package verification passed: $root"
Write-Host "Verified files: $verifiedCount"
Write-Host "Route: $($manifest.route)"
Write-Host "Audience: $($manifest.audience)"
if ($AllowRuntimeState) { Write-Host 'Runtime-created state was allowed during privacy scanning.' }
