# PAL98 DLSS 5 Lab

这是仙剑 98 / PALDLL_DX9 的隔离图形实验包构建器。目标是在不修改原游戏目录、不向 Git 提交游戏资源或第三方二进制的前提下，生成可供 RTX 50 系列机器测试的本地副本。

当前状态：**个人实验包已生成并通过静态验证；本机 RTX 5060 / 616.64 已在 `DgVoodooDirectDraw` 路线上完成真实 PAL.EXE 启动。日志确认 NGX feature 18 可用、640×400 DLAA feature ready 且持续完成帧求值；用户确认调色板正常、窗口可拖动，并能感觉到启用效果后的变化。此结果仍是单机个人研究观察，不等于画质对照或 RTX 5090 验收。**

## 两条渲染路线

默认路线 `DxwrapperD3D9Chain`：

```text
PALOLD DirectDraw
  -> dxwrapper DirectDraw-to-D3D9
  -> dgVoodoo2 D3D9-to-D3D11
  -> ReShade x86
  -> DLSS5-Feeder x86
  -> host64 / neural consumer / NVIDIA runtime
```

高风险对照路线 `DgVoodooDirectDraw`：

```text
PALOLD DirectDraw
  -> dgVoodoo2 DirectDraw-to-D3D11
  -> ReShade x86
  -> DLSS5-Feeder x86
  -> host64 / neural consumer / NVIDIA runtime
```

第二条路线会把构建副本中的 dxwrapper 三件套移入 `DLSS5-Lab/rollback/dxwrapper`，但绝不触碰源目录。它没有继承现有 dxwrapper 的 DirectDraw/surface/palette/window 运行时验收，不能作为默认路线或比赛包。

## 安全边界

- 构建器不联网、不安装软件、不改注册表、不申请管理员权限、不修改 Defender。
- 所有 PE 依赖同时校验 SHA-256 和 x86/x64 架构；32 位与 `host64` 放反会停止构建。
- 二进制、脚本和资源继续按 SHA-256 锁定；`config.ini`、活动路线的 `dxwrapper.ini` 与 ReShade 配置允许被配置工具/运行时重写，但每次启动都会检查 Classic v5、离线边界、渲染链和效果顺序等必要语义。
- `dependency-bundle/`、`artifacts/` 和测试输出都被 Git 忽略。
- 默认排除源目录中的存档、日志、`_codex_backups`、运行时 Profile 指针和 TournamentLock 历史。
- `Friend` 构建要求依赖清单中的每个文件都明确标记为可再分发；`unknown` 会失败关闭。
- 构建成功只证明静态组包和哈希检查通过，不证明 DLSS 5 已运行。

## 准备依赖

按 [依赖合同](dependencies/README.md) 创建 `dependency-bundle/bundle.manifest.json`。不要把依赖目录提交到 Git。本机的完整清单包含用户提供的 NVIDIA 310.8.0 DLL 和 RenoDX DLSS5 v2.5，只允许构建 `Personal` 包。

## 构建个人实验副本

```powershell
.\scripts\Build-LabPackage.ps1 `
  -SourceGameRoot 'D:\PAL\完整包\PAL98_v1.61_20260904' `
  -DependencyBundleRoot '.\dependency-bundle' `
  -OutputRoot '.\artifacts\PAL98_v1.61_20260904-DLSS5-LAB' `
  -Route DxwrapperD3D9Chain `
  -PackageAudience Personal
```

生成结果后先执行：

```powershell
.\scripts\Verify-LabPackage.ps1 `
  -PackageRoot '.\artifacts\PAL98_v1.61_20260904-DLSS5-LAB'
```

最终玩家入口位于生成包根目录：

- `README-FIRST.txt`：给测试者的七步中文说明；
- `仅检查DLSS5环境.cmd`：只读预检，不启动游戏；
- `开始DLSS5测试.cmd`：预检通过后启动 PAL.EXE，退出后收集相关日志。
- `DgVoodooDirectDraw` 路线由启动器强制保持为可拖动、居中的 640×400 客户区；也可用 `启动640x400窗口.cmd` 单独做渲染基线测试。

预检会确认包内关键文件、64 位 Windows、RTX 50 系列名称和 ReShade 版本。运行入口里的 `ExecutionPolicy Bypass` 只用于执行包内已被清单哈希锁定的本地脚本；它不改变系统策略。

## 构建朋友测试包

只有全部组件的再分发状态已经核实时才使用：

```powershell
.\scripts\Build-LabPackage.ps1 `
  -SourceGameRoot 'D:\PAL\完整包\PAL98_v1.61_20260904' `
  -DependencyBundleRoot '.\dependency-bundle' `
  -OutputRoot '.\artifacts\PAL98_v1.61_20260904-DLSS5-FRIEND' `
  -Route DxwrapperD3D9Chain `
  -PackageAudience Friend
```

不要直接把当前正在使用的游戏目录发给朋友；它可能包含存档、日志、备份和本机运行状态。

## 自动化测试

测试只使用脚本生成的假游戏/假依赖目录，不启动真实 PAL.EXE：

```powershell
.\tests\Test-Build-LabPackage.ps1
```

真实回归项目见 [测试矩阵](docs/TEST_MATRIX.md)。
当前上游版本和提交证据见 [上游快照](docs/UPSTREAM_SNAPSHOT.md)。
本轮已验证/未验证边界见 [构建状态](docs/BUILD_STATUS.md)。
本机公开来源依赖的取得与授权边界见 [依赖取得记录](docs/DEPENDENCY_ACQUISITION_20260904.md)。

## 上游边界

- DLSS5-Feeder: <https://github.com/jlrouzies-fr/DLSS5-Feeder>
- ReShade: <https://reshade.me/>
- dgVoodoo2: <http://dege.freeweb.hu/dgVoodoo2/>
- NVIDIA DLSS 5 research: <https://research.nvidia.com/labs/adlr/DLSS5/>

这些链接只是来源记录，不表示本仓库替第三方授予下载、使用或再分发权。
