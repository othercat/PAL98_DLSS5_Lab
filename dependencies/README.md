# Dependency bundle

`Build-LabPackage.ps1` never downloads DLLs, changes Defender settings, or adds system-wide graphics layers. The builder only consumes a local, hash-locked dependency bundle.

Create an ignored directory named `dependency-bundle`, copy `bundle.manifest.example.json` to `dependency-bundle/bundle.manifest.json`, then place each locally obtained file at the manifest's `path`.

Every manifest entry must record:

- the exact SHA-256;
- the original source URL;
- the component's license;
- `redistribution` as `redistributable`, `personal-only`, or `unknown`.

Generate a hash with:

```powershell
Get-FileHash -LiteralPath .\dependency-bundle\payload\path\file.dll -Algorithm SHA256
```

The `Friend` build audience is fail-closed: every selected component must be marked `redistributable`. This is intentional. The MIT license of DLSS5-Feeder does not grant redistribution rights for ReShade, dgVoodoo2, a neural consumer, or NVIDIA runtime libraries.

Required roles for both routes:

- `reshade_x86`
- `feeder_addon32`
- `feeder_shader`
- `reshade_fxh`
- `reshade_ui_fxh`
- `drawtext_fxh`
- `motion_vectors`
- `host64_exe`
- `reshade_x64`
- `neural_consumer`
- `nvngx_dlssnr`
- `nvngx_dlss`
- `dgvoodoo_config`

Route-specific role:

- `DxwrapperD3D9Chain`: `dgvoodoo_d3d9_x86`
- `DgVoodooDirectDraw`: `dgvoodoo_ddraw_x86`

`motion_vectors` may appear more than once. For the current Lumenite Kernel route, list the kernel shader and every included `.fxh` separately. Additional shader assets, textures, consumer configuration files, and license files may also be listed as extra manifest entries. Every third-party file copied into the final package must be listed; directory-wide opaque copying is deliberately unsupported.

The lab writes its own hash-checked `ReShade.ini`, `ReShadePreset.ini`, and `host64/ReShade.ini`. Those destinations and `DLSS5-Lab/` are reserved and cannot be supplied by the dependency bundle. The preset enables `Lumenite_Kernel` before `DLSS5_Feed` with `DLSS5_MV_PROVIDER=3`, following the current upstream 32-bit/D3D9 instructions.
