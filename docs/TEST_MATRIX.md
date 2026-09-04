# PAL98 DLSS 5 Lab test matrix

Passing build-time verification does not prove that DLSS 5 ran or that Classic speedrun v5 remains compatible.

## Gate 1 - build and provenance

| Test | Setup | Steps | Expected | Failure symptoms | v1.14 comparison |
|---|---|---|---|---|---|
| Source identity | Exact PAL98 v1.61 source | Run builder | All baseline hashes match | Build refuses drift | No |
| Dependency identity | Completed bundle manifest | Run builder | Every selected file matches SHA-256 | Build refuses missing or mismatched file | No |
| Friend distribution | All selected files have documented rights | Build with `-PackageAudience Friend` | Build succeeds only when every entry is `redistributable` | Unknown/personal-only entry blocks build | No |
| Source preservation | Source and output are different paths | Compare hashes after build | Source files unchanged | Any source write is a failure | No |

## Gate 2 - local RTX 5060 smoke test

Prerequisite: NVIDIA driver 616.64 or newer. The launcher must fail closed before PAL.EXE when an older driver is detected.

| Test | Setup | Steps | Expected | Failure symptoms | v1.14 comparison |
|---|---|---|---|---|---|
| Preflight only | Built Lab package | Double-click `仅检查DLSS5环境.cmd` | Hashes, OS and GPU are reported; PAL is not started | Missing/hash mismatch | No |
| Conflict guard | Smooth Motion and OptiScaler disabled for PAL.EXE | Confirm driver/tool settings before launch | No competing frame hook | Corruption, silent neural stop, unstable present | No |
| Mutable configuration | Change a non-critical PAL option and allow ReShade/Feeder to persist settings | Run verifier again | Hash differences are reported, required Classic/offline/render-chain semantics still pass | Any immutable-file change or critical semantic change fails closed | Automated fixture passed |
| Wrapper ownership | `DxwrapperD3D9Chain` route | Start game once | dgVoodoo reports D3D11; ReShade attaches as `dxgi.dll` | System D3D9 still used, black screen, no ReShade log | No |
| Feeder delivery | Same run | Enter main menu and map | Feeder log contains a ready DLAA feature and delivered frames | STANDBY, zero motion vectors, no host connection | No |
| Neural consumer | Open the helper window and press Home | Enable neural rendering; restart once if the consumer requests it | Host ReShade log reports feature creation and successful evaluation | Feeder alone works but neural pass remains idle | No |
| Visual A/B | 1920x1200 first | Capture same static and moving scenes enabled/disabled | Difference is visible and readable | Text/sprites smear, flicker or change identity | No |
| Launch/new/load | Known clean test save | New game, load save, return to title | No crash/hang; state is correct | Wrong profile/save, stuck transition | Yes, behavior only |
| Map/menu/battle | Known short route | Move, open/close menu, enter/end battle | Input and presentation remain synchronized | Dropped/repeated input, frozen frame | Yes |
| Audio/focus | Same route | BGM change, sound effect, Alt-Tab twice | Audio, render and input recover | Black frame, muted/stuck audio, focus trap | Yes |
| Exit/restart | Same package | Exit and relaunch | No orphan host or stale hooks | Host remains active, second launch fails | Yes |

## Gate 3 - RTX 5090 friend smoke test

Use exactly the SHA-256-identified package accepted on the RTX 5060. The friend should only extract to a short English path, run `仅检查DLSS5环境.cmd`, then run `开始DLSS5测试.cmd`.

Record GPU, driver, display resolution/refresh rate, package manifest hash, route, PAL/PALOLD/PALDLL hashes, and all collected logs. A 5090 success is one-machine runtime evidence, not speedrun certification.

## Gate 4 - speedrun-sensitive acceptance

Only after Gates 1-3:

- compare disabled/enabled wall-clock transitions with identical save and endpoints;
- confirm PalTimer still recognizes the environment;
- test input timing, battle start/end, scene scripts and palette fades;
- keep `DxwrapperD3D9Chain` and `DgVoodooDirectDraw` results separate;
- never call a visual smoke test competition compatible.
