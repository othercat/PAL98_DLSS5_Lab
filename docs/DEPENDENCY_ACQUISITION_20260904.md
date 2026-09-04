# 依赖取得记录（2026-09-04）

本机已从官方或作者控制的公开来源取得并校验以下个人测试依赖。二进制位于 Git 忽略的 `dependency-bundle/`，本文件只记录来源、版本、下载哈希和授权边界。

| 组件 | 固定来源 | 下载文件 SHA-256 | 当前边界 |
|---|---|---|---|
| ReShade 6.8.0 full add-on | <https://reshade.me/> | `AFE4C8F13048306307983B8B3D41D5BF00A86820440B0E57DEA10950E1176445` | 仅个人缓存；官网要求分享链接而非二进制 |
| DLSS5-Feeder 0.13.1-beta.1 | <https://github.com/jlrouzies-fr/DLSS5-Feeder/releases/tag/v0.13.1-beta.1> | `8DA626ED906A29289F001CB613640015360E36B0C3478348BF097A304B34BB18` | MIT；本轮取得的 Feeder 文件可再分发 |
| dgVoodoo2 2.87.4 | <https://github.com/dege-diosg/dgVoodoo2/releases/tag/v2.87.4> | `74AEB464D829DB80E3F4AA8FAE235E6E3B38FC01188776C5C2376BB0DEA0956E` | 当前清单保守标为个人用途 |
| LumeniteFX `76fa3e4d601c97e9bc63f119c01405b7b9938885` | <https://github.com/umar-afzaal/LumeniteFX/tree/76fa3e4d601c97e9bc63f119c01405b7b9938885> | `BF574543A6AF6527587AF0BAD139922E8C0363BB154CDFB3E41133C7DCA2EE3F` | AGNYA 1.4 要求公共传播只使用作者官方链接；仅个人缓存 |
| NVIDIA DLSS SDK sample 310.7.0 | <https://github.com/NVIDIA/DLSS/releases/tag/v310.7.0> | `6A66B2808976506B9BE07EEAB922914439F678A8AF2AF83AE0927EEAFA04DEDB` | 已取得 NVIDIA 签名有效的 `nvngx_dlss.dll`；当前保守标为个人用途 |

随后从用户合法持有的 NBA2K27 early-access 本地副本导入：

| 文件 | 版本 | SHA-256 | 签名/用途 |
|---|---|---|---|
| `nvngx_dlss.dll` | 310.8.0.0 | `C85F971CE023C9F3492FC7455F0B01A24BA18EA39636407A846902C4360B0B7E` | NVIDIA 签名有效；替换 payload 中的 310.7.0，仅个人研究 |
| `nvngx_dlssnr.dll` | 310.8.0.0 | `E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E` | NVIDIA 签名有效；仅个人研究 |
| `sl.dlss_nr.dll` | 2.13.0.0 | `9F6672E5E0170DC118A3188D21BDA187E1FC1AA3502895B21AB846D23165C11D` | NVIDIA 签名有效；是 Streamline plugin，不部署到 Feeder 包 |
| `renodx-dlss5-v2.5.addon64` | 0.2026.0827.2036 | `87AEF9DDD937C7241E6BF8D8EFEA0045D63559135E254C60DAB316DB3D3A4AEE` | 未签名；符合通用 RenoDX DLSS5 consumer 标记，仅个人研究 |
| `renodx-control-rr.addon64` | 0.2026.0827.1500 | `3E9D8CA0389B7B4C5F37555DFB86023296DCB18E7E5360B82DE7B88DEE891047` | 未签名；绑定 `Control_DX12.exe` 和 Control 专属资源，不部署 |

ReShade shader headers 另固定到 `crosire/reshade-shaders` 提交 `6db142b4b1a05c764222e5b0bd9a644b7ccfe1dc`，单文件哈希记录在本机 `bundle.manifest.json`。

## 验证结果

- 18 个 payload 文件全部通过清单 SHA-256 复核。
- `dxgi-x86.dll`、`dlss5-feed.addon32`、dgVoodoo2 `D3D9.dll` 和 `DDraw.dll` 均为 x86。
- `dxgi-x64.dll`、`dlss5-feed-host64.exe`、RenoDX consumer 和两个 NGX DLL 均为 x64。
- 两个 310.8.0 NGX DLL 的 Authenticode 状态均为 `Valid`，签名者为 NVIDIA Corporation，证书指纹为 `7B7B0B6697AFB438CF6F65A155F00E86676FB186`。
- ReShade 安装器的签名证书指纹为 `589690208A5E52FB96980C4A6698F50ACD47C49F`，与官网公布值一致；本机对完整签名链返回 `UnknownError`，因此只把证书一致性与链验证结果分别记录，不声称链验证通过。

## 消费者选择

Feeder 要求一个 ReShade 神经消费者；Streamline 的 `sl.dlss_nr.dll` 不能替代它。当前使用下载目录中发现的 `renodx-dlss5-v2.5.addon64`，并在包中使用 Feeder 能稳定识别的目标名 `host64/renodx-dlss5.addon64`。

Control 专用 `renodx-control-rr.addon64` 内含 `Control_DX12.exe`、Control RT/合成器和专属缓冲区诊断字符串，不作为 PAL98 的通用消费者。Feeder 当前文档也明确区分通用 `renodx-dlss5` 与其他 RenoDX add-on。

完整本地清单仍全部按 `personal-only` 处理。朋友版额外受再分发授权约束，应设计“在朋友电脑上从官方源下载”的安装流程，除非所有被打包组件都已有明确再分发许可。
