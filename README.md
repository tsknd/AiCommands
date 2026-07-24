# AiCommands — Claude Code 个人效率工具集

一套可跨机器安装的 Claude Code 辅助工具。按类型分两类,安装位置不同:

| 目录 | 类型 | 安装位置 | 工具 |
|---|---|---|---|
| [`commands/`](commands/) | Slash 命令(`.md`) | `~/.claude/commands/` | `/hc` 交接压缩 |
| [`sessions/`](sessions/) | 终端命令(lss/oss) | `~/.bashrc` 或 PowerShell `$PROFILE` | 列出 / 打开历史会话(绕过面板 13 天上限) |

## 新机器快速安装

```bash
git clone https://github.com/tsknd/AiCommands.git
cd AiCommands

# 1) Slash 命令
cp commands/hc.md ~/.claude/commands/

# 2) 会话工具 lss/oss:按 sessions/安装指南.md 操作(bash 或 PowerShell 二选一)
```

> Windows 把 `~/.claude/` 换成 `C:\Users\<你>\.claude\`。

## 各工具说明

- **`/hc`** — 见 [commands/README.md](commands/README.md):智能判断是否需要压缩,需要时按 5 项生成交接摘要并落盘。
- **`lss` / `oss`** — 见 [sessions/使用说明.md](sessions/使用说明.md)(日常速查)、[sessions/安装指南.md](sessions/安装指南.md)(安装与原理):列出磁盘全量历史会话、按 id 前缀一键打开,解决官方面板只显示最近约 13~30 天的痛点。
