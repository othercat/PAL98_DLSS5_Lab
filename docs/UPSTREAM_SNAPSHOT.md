# Upstream snapshot

Observed on 2026-09-04 (Asia/Shanghai):

- DLSS5-Feeder latest release returned by GitHub: `v0.13.1-beta.1`.
- DLSS5-Feeder `main`: `792755324574ff4703eb441a7bc14c724e125b84`.
- LumeniteFX `mainline`: `76fa3e4d601c97e9bc63f119c01405b7b9938885`.
- dgVoodoo2 latest GitHub release: `v2.87.4`.
- NVIDIA DLSS latest GitHub release used for the official SDK sample: `v310.7.0`; it contains `nvngx_dlss.dll` but not `nvngx_dlssnr.dll`.
- The user's NBA2K27 early-access files provide NVIDIA-signed `nvngx_dlss.dll` and `nvngx_dlssnr.dll` version `310.8.0.0`, plus NVIDIA-signed Streamline `sl.dlss_nr.dll` version `2.13.0.0`. These local files are personal research inputs, not an asserted redistribution source.
- NVIDIA's 2026-09-03 DLSS 5 launch driver is `616.64` WHQL; the launcher uses that version as its minimum hardware gate.
- ReShade full add-on installer used for personal acquisition: `6.8.0`.
- ReShade requirement in the Feeder installer: 6.8 or newer, add-on-enabled x86 beside PAL.EXE and x64 under `host64/`.

The 32-bit D3D9 layout and configuration templates in this repository follow the current upstream installer and README:

- <https://github.com/jlrouzies-fr/DLSS5-Feeder/blob/main/README.md>
- <https://github.com/jlrouzies-fr/DLSS5-Feeder/blob/main/tools/Install-DLSS5Feeder.ps1>
- <https://github.com/umar-afzaal/LumeniteFX/tree/mainline>
- <https://github.com/dege-diosg/dgVoodoo2/releases/tag/v2.87.4>
- <https://github.com/NVIDIA/DLSS/releases/tag/v310.7.0>
- <https://reshade.me/>

This snapshot is evidence, not an auto-update channel. A real dependency bundle remains pinned by SHA-256. Re-check upstream behavior before changing versions. DLSS5-Feeder's MIT license does not grant rights for the neural consumer, NVIDIA runtime DLLs, ReShade, dgVoodoo2, or LumeniteFX. ReShade's official page requests links rather than redistributed binaries, and LumeniteFX's AGNYA License restricts public propagation to official author links; both are therefore treated as personal-only in the current local bundle.
