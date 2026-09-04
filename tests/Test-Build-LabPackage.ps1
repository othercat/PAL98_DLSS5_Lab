[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$testRoot = Join-Path $repoRoot ('test-output\run-' + [guid]::NewGuid().ToString('N'))
$startChineseName = ([string][char]0x5F00) + ([char]0x59CB) + 'DLSS5' + ([char]0x6D4B) + ([char]0x8BD5) + '.cmd'
$windowedChineseName = ([string][char]0x542F) + ([char]0x52A8) + '640x400' + ([char]0x7A97) + ([char]0x53E3) + '.cmd'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Write-TestFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::ASCII)
}

function Write-FakePe {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('x86', 'x64')][string]$Architecture
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $bytes = New-Object byte[] 512
    $bytes[0] = 0x4D
    $bytes[1] = 0x5A
    [BitConverter]::GetBytes([int]0x80).CopyTo($bytes, 0x3C)
    $bytes[0x80] = 0x50
    $bytes[0x81] = 0x45
    $machine = if ($Architecture -eq 'x86') { [uint16]0x014C } else { [uint16]0x8664 }
    [BitConverter]::GetBytes($machine).CopyTo($bytes, 0x84)
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $json = $Value | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

function New-FakeSource {
    param([Parameter(Mandatory = $true)][string]$Root)
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $files = [ordered]@{
        'PAL.EXE' = 'fake-pal-exe'
        'PAL.dll' = 'fake-pal-dll'
        'PALOLD.dll' = 'fake-palold-dll'
        'ddraw.dll' = 'fake-dxwrapper-proxy'
        'dxwrapper.dll' = 'fake-dxwrapper-core'
        'config.ini' = "[Patch]`r`nDefaultPatch=pal98fix-classic-v5`r`n`r`n[extra]`r`nRandomLevelUpSkills=1`r`n`r`n[NetworkBoundary]`r`nStrictOfflineMode=true`r`nAudienceBridgeEnabled=false`r`nAllowLoopbackIpc=false`r`n"
        'dxwrapper.ini' = "[General]`r`nRealDllPath = AUTO`r`n`r`n[Compatibility]`r`nDd7to9 = 1`r`nD3d9HookSystem32 = 1`r`n`r`n[d3d9]`r`nEnableWindowMode = 1`r`nFullscreenWindowMode = 0`r`n`r`n[FullScreen]`r`nFullScreen = 0`r`n"
        'DATA.MKF' = 'fake-game-resource'
    }
    foreach ($entry in $files.GetEnumerator()) {
        Write-TestFile -Path (Join-Path $Root $entry.Key) -Content $entry.Value
    }
    Write-TestFile -Path (Join-Path $Root '1.RPG') -Content 'private-save'
    Write-TestFile -Path (Join-Path $Root 'run.log') -Content 'private-log'
    Write-TestFile -Path (Join-Path $Root '_codex_backups\secret.txt') -Content 'backup'
    Write-TestFile -Path (Join-Path $Root 'blackscreen_logs\trace.txt') -Content 'trace'
    Write-TestFile -Path (Join-Path $Root 'palmod\Profiles\active.txt') -Content 'profile'
    Write-TestFile -Path (Join-Path $Root 'palmod\TournamentLock\history\event.txt') -Content 'history'
}

function New-FakeBaseline {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $names = @('PAL.EXE', 'PAL.dll', 'PALOLD.dll', 'ddraw.dll', 'dxwrapper.dll', 'config.ini', 'dxwrapper.ini')
    $entries = @($names | ForEach-Object {
        [ordered]@{ path = $_; sha256 = Get-Sha256 (Join-Path $SourceRoot $_) }
    })
    Write-JsonFile -Path $Path -Value ([ordered]@{
        schema = 'PAL98.DLSS5Lab.SourceBaseline.v1'
        baseline_id = 'fake-classic-v5'
        source_package = 'fake-source'
        files = $entries
    })
}

function New-FakeBundle {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$OmitRole,
        [string]$NonRedistributableRole,
        [string]$BadHashRole,
        [string]$BadArchitectureRole
    )
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $specs = @(
        @('reshade_x86', 'payload/common/dxgi-x86.dll', 'dxgi.dll', 'all'),
        @('feeder_addon32', 'payload/common/dlss5-feed.addon32', 'dlss5-feed.addon32', 'all'),
        @('feeder_shader', 'payload/common/DLSS5_Feed.fx', 'reshade-shaders/Shaders/DLSS5_Feed.fx', 'all'),
        @('reshade_fxh', 'payload/common/ReShade.fxh', 'reshade-shaders/Shaders/ReShade.fxh', 'all'),
        @('reshade_ui_fxh', 'payload/common/ReShadeUI.fxh', 'reshade-shaders/Shaders/ReShadeUI.fxh', 'all'),
        @('drawtext_fxh', 'payload/common/DrawText.fxh', 'reshade-shaders/Shaders/DrawText.fxh', 'all'),
        @('motion_vectors', 'payload/common/lumenite_Kernel.fx', 'reshade-shaders/Shaders/lumenite_Kernel.fx', 'all'),
        @('motion_vectors', 'payload/common/lumenite_Compute.fxh', 'reshade-shaders/Shaders/include/lumenite_Compute.fxh', 'all'),
        @('host64_exe', 'payload/common/dlss5-feed-host64.exe', 'host64/dlss5-feed-host64.exe', 'all'),
        @('reshade_x64', 'payload/common/dxgi-x64.dll', 'host64/dxgi.dll', 'all'),
        @('neural_consumer', 'payload/common/neural-consumer.addon64', 'host64/neural-consumer.addon64', 'all'),
        @('nvngx_dlssnr', 'payload/common/nvngx_dlssnr.dll', 'host64/nvngx_dlssnr.dll', 'all'),
        @('nvngx_dlss', 'payload/common/nvngx_dlss.dll', 'host64/nvngx_dlss.dll', 'all'),
        @('dgvoodoo_config', 'payload/common/dgVoodoo.conf', 'dgVoodoo.conf', 'all'),
        @('dgvoodoo_d3d9_x86', 'payload/chain/D3D9.dll', 'd3d9.dll', 'DxwrapperD3D9Chain'),
        @('dgvoodoo_ddraw_x86', 'payload/direct/DDraw.dll', 'ddraw.dll', 'DgVoodooDirectDraw')
    )
    $entries = New-Object 'System.Collections.Generic.List[object]'
    foreach ($spec in $specs) {
        $role = [string]$spec[0]
        if ($OmitRole -and $role -eq $OmitRole) {
            continue
        }
        $relativePath = [string]$spec[1]
        $filePath = Join-Path $Root $relativePath
        $x86Roles = @('reshade_x86', 'feeder_addon32', 'dgvoodoo_d3d9_x86', 'dgvoodoo_ddraw_x86')
        $x64Roles = @('host64_exe', 'reshade_x64', 'neural_consumer', 'nvngx_dlssnr', 'nvngx_dlss')
        if ($x86Roles -contains $role) {
            $architecture = if ($BadArchitectureRole -and $role -eq $BadArchitectureRole) { 'x64' } else { 'x86' }
            Write-FakePe -Path $filePath -Architecture $architecture
        }
        elseif ($x64Roles -contains $role) {
            $architecture = if ($BadArchitectureRole -and $role -eq $BadArchitectureRole) { 'x86' } else { 'x64' }
            Write-FakePe -Path $filePath -Architecture $architecture
        }
        elseif ($role -eq 'dgvoodoo_config') {
            Write-TestFile -Path $filePath -Content "[General]`r`nFullScreenMode=true`r`nCaptureMouse=true`r`nCenterAppWindow=false`r`n[GeneralExt]`r`nImageScaleFactor=1`r`n[DirectX]`r`nAppControlledScreenMode=true`r`n[DirectXExt]`r`nDithering=forcealways`r`n"
        }
        else {
            Write-TestFile -Path $filePath -Content ('fake-dependency-' + $role)
        }
        $hash = Get-Sha256 $filePath
        if ($BadHashRole -and $role -eq $BadHashRole) {
            $hash = ('0' * 64)
        }
        $redistribution = if ($NonRedistributableRole -and $role -eq $NonRedistributableRole) { 'unknown' } else { 'redistributable' }
        $entries.Add([ordered]@{
            path = $relativePath
            destination = [string]$spec[2]
            role = $role
            routes = @([string]$spec[3])
            sha256 = $hash
            source_url = 'https://example.invalid/test-fixture'
            license = 'test-only'
            redistribution = $redistribution
        })
    }
    Write-JsonFile -Path (Join-Path $Root 'bundle.manifest.json') -Value ([ordered]@{
        schema = 'PAL98.DLSS5Lab.DependencyBundle.v1'
        bundle_id = 'fake-bundle'
        files = $entries.ToArray()
    })
}

function Get-TreeHashes {
    param([Parameter(Mandatory = $true)][string]$Root)
    $result = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File)) {
        $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
        $result[$relative] = Get-Sha256 $file.FullName
    }
    return $result
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$ExpectedMessage
    )
    $threw = $false
    try {
        & $Action
    }
    catch {
        $threw = $true
        if ($_.Exception.Message -notlike ('*' + $ExpectedMessage + '*')) {
            throw "Expected error containing '$ExpectedMessage', got '$($_.Exception.Message)'"
        }
    }
    if (-not $threw) {
        throw "Expected action to fail with '$ExpectedMessage'."
    }
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $sourceRoot = Join-Path $testRoot 'source'
    $baselinePath = Join-Path $testRoot 'baseline.json'
    New-FakeSource -Root $sourceRoot
    New-FakeBaseline -SourceRoot $sourceRoot -Path $baselinePath
    $sourceBefore = Get-TreeHashes $sourceRoot

    $bundleRoot = Join-Path $testRoot 'bundle-good'
    New-FakeBundle -Root $bundleRoot

    $chainOutput = Join-Path $testRoot 'output-chain'
    & (Join-Path $repoRoot 'scripts\Build-LabPackage.ps1') `
        -SourceGameRoot $sourceRoot `
        -DependencyBundleRoot $bundleRoot `
        -OutputRoot $chainOutput `
        -Route DxwrapperD3D9Chain `
        -PackageAudience Personal `
        -BaselinePath $baselinePath
    & (Join-Path $repoRoot 'scripts\Verify-LabPackage.ps1') -PackageRoot $chainOutput
    & (Join-Path $chainOutput 'DLSS5-Lab\Start-DLSS5Lab.ps1') -PreflightOnly -AllowUnsupportedDriver

    Assert-True (Test-Path -LiteralPath (Join-Path $chainOutput 'd3d9.dll') -PathType Leaf) 'Chain route must include d3d9.dll.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $chainOutput 'dxwrapper.ini') -Raw) -match '(?im)^\s*D3d9HookSystem32\s*=\s*0\s*$') 'Chain route must disable System32-only D3D9 loading.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $chainOutput '1.RPG'))) 'Private saves must be excluded.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $chainOutput 'run.log'))) 'Runtime logs must be excluded.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $chainOutput '_codex_backups'))) 'Backup directory must be excluded.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $chainOutput 'palmod\Profiles'))) 'Profile state must be excluded.'
    Assert-True (Test-Path -LiteralPath (Join-Path $chainOutput $startChineseName) -PathType Leaf) 'Chinese novice launcher must be present.'
    Assert-True (Test-Path -LiteralPath (Join-Path $chainOutput 'DLSS5-Lab\lab-package.manifest.json') -PathType Leaf) 'Package manifest must be present.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $chainOutput 'ReShadePreset.ini') -Raw) -match '^Techniques=Lumenite_Kernel@lumenite_Kernel\.fx,DLSS5_Feed@DLSS5_Feed\.fx') 'Preset must enable motion vectors before the feeder.'
    $preflightLogs = @(Get-ChildItem -LiteralPath (Join-Path $chainOutput 'DLSS5-Lab\evidence') -Recurse -Filter 'preflight.txt' -File)
    Assert-True ($preflightLogs.Count -eq 1) 'Preflight-only run must create one evidence log.'
    Assert-True ((Get-Content -LiteralPath $preflightLogs[0].FullName -Raw) -match 'PAL.EXE was not started') 'Preflight-only run must not start PAL.EXE.'

    $mutableConfigPath = Join-Path $chainOutput 'config.ini'
    $mutableConfigBaselineHash = Get-Sha256 $mutableConfigPath
    $mutableConfigText = (Get-Content -LiteralPath $mutableConfigPath -Raw).Replace('RandomLevelUpSkills=1', 'RandomLevelUpSkills=0')
    [System.IO.File]::WriteAllText($mutableConfigPath, $mutableConfigText, [System.Text.Encoding]::ASCII)
    Assert-True ((Get-Sha256 $mutableConfigPath) -ne $mutableConfigBaselineHash) 'Mutable config test must change the config hash.'

    foreach ($relativeMutablePath in @('dxwrapper.ini', 'ReShade.ini', 'ReShadePreset.ini', 'host64\ReShade.ini')) {
        $mutablePath = Join-Path $chainOutput $relativeMutablePath
        $mutableText = Get-Content -LiteralPath $mutablePath -Raw
        [System.IO.File]::WriteAllText($mutablePath, ($mutableText + "`r`n; simulated runtime/config-tool rewrite`r`n"), [System.Text.Encoding]::ASCII)
    }
    & (Join-Path $repoRoot 'scripts\Verify-LabPackage.ps1') -PackageRoot $chainOutput -AllowRuntimeState

    $unsafeConfigText = $mutableConfigText.Replace('StrictOfflineMode=true', 'StrictOfflineMode=false')
    [System.IO.File]::WriteAllText($mutableConfigPath, $unsafeConfigText, [System.Text.Encoding]::ASCII)
    Assert-Throws -ExpectedMessage 'Mutable config.ini requires' -Action {
        & (Join-Path $repoRoot 'scripts\Verify-LabPackage.ps1') -PackageRoot $chainOutput -AllowRuntimeState
    }

    $sourceAfter = Get-TreeHashes $sourceRoot
    Assert-True ($sourceBefore.Count -eq $sourceAfter.Count) 'Source file count must not change.'
    foreach ($key in $sourceBefore.Keys) {
        Assert-True ($sourceAfter.ContainsKey($key) -and $sourceAfter[$key] -eq $sourceBefore[$key]) "Source file changed: $key"
    }

    $directOutput = Join-Path $testRoot 'output-direct'
    & (Join-Path $repoRoot 'scripts\Build-LabPackage.ps1') `
        -SourceGameRoot $sourceRoot `
        -DependencyBundleRoot $bundleRoot `
        -OutputRoot $directOutput `
        -Route DgVoodooDirectDraw `
        -PackageAudience Personal `
        -BaselinePath $baselinePath
    & (Join-Path $repoRoot 'scripts\Verify-LabPackage.ps1') -PackageRoot $directOutput
    Assert-True ((Get-Sha256 (Join-Path $directOutput 'ddraw.dll')) -eq (Get-Sha256 (Join-Path $bundleRoot 'payload/direct/DDraw.dll'))) 'Direct route must install dgVoodoo DDraw.dll.'
    Assert-True (Test-Path -LiteralPath (Join-Path $directOutput 'DLSS5-Lab\Start-PAL-Windowed.ps1') -PathType Leaf) 'Direct route must include the window helper.'
    Assert-True (Test-Path -LiteralPath (Join-Path $directOutput $windowedChineseName) -PathType Leaf) 'Direct route must include the 640x400 novice launcher.'
    $directConfig = Join-Path $directOutput 'dgVoodoo.conf'
    Assert-True ((Get-Content -LiteralPath $directConfig -Raw) -match '(?im)^\s*FullScreenMode\s*=\s*false\s*$') 'Direct route must force dgVoodoo windowed mode.'
    Assert-True ((Get-Content -LiteralPath $directConfig -Raw) -match '(?im)^\s*ImageScaleFactor\s*=\s*2\s*$') 'Direct route must request 2x image scaling.'
    foreach ($name in @('ddraw.dll', 'dxwrapper.dll', 'dxwrapper.ini')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $directOutput ('DLSS5-Lab\rollback\dxwrapper\' + $name)) -PathType Leaf) "Direct route must preserve $name."
    }

    $saveOutput = Join-Path $testRoot 'output-explicit-save'
    & (Join-Path $repoRoot 'scripts\Build-LabPackage.ps1') `
        -SourceGameRoot $sourceRoot `
        -DependencyBundleRoot $bundleRoot `
        -OutputRoot $saveOutput `
        -Route DxwrapperD3D9Chain `
        -PackageAudience Personal `
        -BaselinePath $baselinePath `
        -TestSavePath (Join-Path $sourceRoot '1.RPG')
    & (Join-Path $repoRoot 'scripts\Verify-LabPackage.ps1') -PackageRoot $saveOutput
    Assert-True ((Get-Content -LiteralPath (Join-Path $saveOutput '1.RPG') -Raw) -eq 'private-save') 'Explicit test save must be copied and hash checked.'

    $friendBundle = Join-Path $testRoot 'bundle-friend-blocked'
    New-FakeBundle -Root $friendBundle -NonRedistributableRole 'neural_consumer'
    Assert-Throws -ExpectedMessage 'Friend package is blocked' -Action {
        & (Join-Path $repoRoot 'scripts\Build-LabPackage.ps1') `
            -SourceGameRoot $sourceRoot -DependencyBundleRoot $friendBundle `
            -OutputRoot (Join-Path $testRoot 'output-friend-blocked') `
            -Route DxwrapperD3D9Chain -PackageAudience Friend -BaselinePath $baselinePath
    }

    $missingBundle = Join-Path $testRoot 'bundle-missing-role'
    New-FakeBundle -Root $missingBundle -OmitRole 'motion_vectors'
    Assert-Throws -ExpectedMessage "requires at least one dependency with role 'motion_vectors'" -Action {
        & (Join-Path $repoRoot 'scripts\Build-LabPackage.ps1') `
            -SourceGameRoot $sourceRoot -DependencyBundleRoot $missingBundle `
            -OutputRoot (Join-Path $testRoot 'output-missing-role') `
            -Route DxwrapperD3D9Chain -PackageAudience Personal -BaselinePath $baselinePath
    }

    $badHashBundle = Join-Path $testRoot 'bundle-bad-hash'
    New-FakeBundle -Root $badHashBundle -BadHashRole 'feeder_shader'
    Assert-Throws -ExpectedMessage 'Dependency hash mismatch' -Action {
        & (Join-Path $repoRoot 'scripts\Build-LabPackage.ps1') `
            -SourceGameRoot $sourceRoot -DependencyBundleRoot $badHashBundle `
            -OutputRoot (Join-Path $testRoot 'output-bad-hash') `
            -Route DxwrapperD3D9Chain -PackageAudience Personal -BaselinePath $baselinePath
    }

    $badArchitectureBundle = Join-Path $testRoot 'bundle-bad-architecture'
    New-FakeBundle -Root $badArchitectureBundle -BadArchitectureRole 'reshade_x86'
    Assert-Throws -ExpectedMessage 'Dependency architecture mismatch' -Action {
        & (Join-Path $repoRoot 'scripts\Build-LabPackage.ps1') `
            -SourceGameRoot $sourceRoot -DependencyBundleRoot $badArchitectureBundle `
            -OutputRoot (Join-Path $testRoot 'output-bad-architecture') `
            -Route DxwrapperD3D9Chain -PackageAudience Personal -BaselinePath $baselinePath
    }

    Write-Host 'All lab package tests passed.'
}
finally {
    $expectedParent = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'test-output')).TrimEnd('\', '/')
    $testFull = [System.IO.Path]::GetFullPath($testRoot).TrimEnd('\', '/')
    if ((Test-Path -LiteralPath $testFull) -and $testFull.StartsWith($expectedParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -and ([System.IO.Path]::GetFileName($testFull) -like 'run-*')) {
        Remove-Item -LiteralPath $testFull -Recurse -Force
    }
}
