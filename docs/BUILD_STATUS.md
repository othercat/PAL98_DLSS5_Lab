# Build status - 2026-09-04

## Completed

- Source baseline records PAL98 v1.61 20260904 Classic speedrun v5 critical hashes.
- All seven recorded hashes match `D:\PAL\完整包\PAL98_v1.61_20260904` in a read-only check.
- Isolated builder supports both `DxwrapperD3D9Chain` and `DgVoodooDirectDraw`.
- Package verifier checks hashes, route layout, required configuration, privacy exclusions, and an explicitly supplied test save.
- Dependency validation checks required roles, SHA-256, x86/x64 PE architecture, host64 placement, neural-consumer conflicts, and redistribution status.
- Windows PowerShell 5.1 fake-fixture tests pass for both routes, optional save, source preservation, privacy exclusions, missing roles, bad hashes, bad architecture, and Friend fail-closed behavior.
- The preflight-only fake-package test detected this host as `NVIDIA GeForce RTX 5060`, driver `591.86`, and did not start PAL.EXE. That driver is now below the explicit `616.64` runtime gate and may only be bypassed by the test fixture switch.
- A local, ignored, personal-use dependency bundle was completed and pinned by SHA-256.
- The completed set includes ReShade 6.8.0 full add-on binaries, DLSS5-Feeder 0.13.1-beta.1, dgVoodoo2 2.87.4, LumeniteFX at commit `76fa3e4d601c97e9bc63f119c01405b7b9938885`, ReShade shader headers at commit `6db142b4b1a05c764222e5b0bd9a644b7ccfe1dc`, user-supplied RenoDX DLSS5 v2.5, and NVIDIA-signed `nvngx_dlss.dll` plus `nvngx_dlssnr.dll` version 310.8.0 from the user's NBA2K27 early-access files.
- A real Personal package was emitted at `artifacts/PAL98_v1.61_20260904-DLSS5-LAB` through the `DxwrapperD3D9Chain` route. Its 34-file static verification passed; the SHA-256 of `DLSS5-Lab/lab-package.manifest.json` is `5BDE47E270E33FB21807BE13718C9A7BA55022AB6389690349F90F81EFEFA4B8`.
- The real-package preflight re-verified the package, detected `NVIDIA GeForce RTX 5060, 591.86`, blocked on the 616.64 driver gate, and did not start PAL.EXE. Evidence is under `DLSS5-Lab/evidence/20260904-214407` in that package.
- After the driver update, a user launch attempt exposed an overly strict mutable-config hash check. Only `RandomLevelUpSkills=1` to `0` changed in `config.ini`; `dxwrapper.ini` was semantically unchanged but reserialized, and ReShade had populated normal runtime settings. No PAL binary or dependency hash changed.
- The verifier now permits hash changes only for `config.ini`, the active-route `dxwrapper.ini`, `ReShade.ini`, `ReShadePreset.ini`, and `host64/ReShade.ini`, while enforcing Classic v5, strict-offline keys, dxwrapper Dd7to9/D3D9 routing, ReShade add-on/search paths, Lumenite-before-Feeder ordering, and `DLSS5_MV_PROVIDER=3`.
- The existing Personal package was repaired in place after backing up its verifier, manifest, and user-edited config. The repaired package passed 34 checks and preflight on `NVIDIA GeForce RTX 5060, 616.64`; PAL.EXE was not started. Evidence: `DLSS5-Lab/evidence/20260904-221711`.
- The repaired `DLSS5-Lab/lab-package.manifest.json` SHA-256 is `42AAD9752AE1F16F5D1CF8C8F530AC37C8D7B06C486F5D3319365F7EFA89988B`.
- The NVIDIA driver was subsequently updated to `616.64`, so the real-package hardware gate now passes on `NVIDIA GeForce RTX 5060`.
- A real `DgVoodooDirectDraw` package was launched with PAL.EXE. ReShade compiled `DLSS5_Feed.fx` and `lumenite_Kernel.fx`; the host identified NVIDIA-signed `nvngx_dlss.dll` and `nvngx_dlssnr.dll` version `310.8.0.0`, reported NGX feature 18 as supported, created a native 640x400 DLAA feature with flags 74, and continued evaluating frames.
- The direct route exposed a PAL98 palette/color incompatibility while dgVoodoo dithering was enabled. Setting `[DirectXExt] Dithering=disabled` restored the expected colors in the user's visual check.
- The direct route now enforces a centered 640x400 client area and restores a draggable title bar/system menu for the package's PAL.EXE only. The user confirmed that the corrected colors and window controls worked.
- With `Lumenite_Kernel` followed by `DLSS5_Feed` enabled, the user reported a perceptible visual change. This is an interactive observation, not a controlled image-quality comparison.

## Not completed

- No RTX 5090 evidence exists.
- No controlled visual-quality comparison, extended gameplay, speedrun, audio/focus, exit/restart, or cross-machine acceptance exists.
- A Friend package remains blocked until every selected third-party component is confirmed redistributable in its manifest entry.
- `sl.dlss_nr.dll` 2.13.0.0 and the Control-specific `renodx-control-rr.addon64` were inspected but are deliberately not deployed: the first is a Streamline plugin rather than a ReShade neural consumer, and the second is tied to `Control_DX12.exe` and Control-specific render resources.
- The `DxwrapperD3D9Chain` route reached the graphics stack but produced incorrect palette output in this PAL98 build; the direct dgVoodoo2 route is the only locally observed usable runtime path so far.
- Host-side ReShade logged an initial failure to find `NVSDK_NGX_D3D12_EvaluateFeature_C`, then hooked the non-`C` entry point and successfully created/evaluated feature 18. This fallback should remain a recorded compatibility risk until tested on the RTX 5090.
