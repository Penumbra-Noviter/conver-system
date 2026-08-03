# Tauri 桌面端环境搭建

> Conver System 桌面版基于 Tauri（Rust + Web 前端）。本文档记录 Rust 工具链、MSVC 编译器的安装状态与环境注意事项。

---

## 工具链清单（2026-08-03）

| 组件 | 版本 | 路径 |
|------|------|------|
| rustup | 1.29.0 | `C:\Users\Administrator\.rustup` |
| rustc / cargo | 1.97.1 (stable) | `C:\Users\Administrator\.cargo\bin\` |
| MSVC 工具 | 14.50.35717 | `C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.50.35717\` |
| Windows SDK | 10.0.22621.0 | `C:\Program Files (x86)\Windows Kits\10\` |

- **目标平台**：`x86_64-pc-windows-msvc`
- **冒烟测试**：`cargo build` 通过 ✅

---

## ⚠️ Git Bash `link.exe` 遮蔽问题

Git Bash 自带的 `/usr/bin/link.exe`（GNU coreutils）会遮蔽 MSVC 的 `link.exe`，导致 `cargo build` 链接阶段失败。

**解决方案**：在 **cmd.exe** 或 **PowerShell** 中运行 `cargo build`，不要使用 Git Bash。
