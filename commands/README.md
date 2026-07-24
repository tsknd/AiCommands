# Claude Code Slash 命令

复制到 `~/.claude/commands/` 即可用(Windows 下 `C:\Users\<你>\.claude\commands\`)。

## 命令

### `/hc` — 交接压缩(智能判断)

- **文件**:`hc.md`
- **作用**:敲 `/hc` 后,先判断本次会话**是否需要压缩**:
  - 不需要(短会话 / 纯讨论)→ 只回一句理由,不落盘。
  - 需要(长会话 / 做过改动 / 到收尾)→ 按「工作·文件 / 进度 / 待办 / 决策 / 踩坑」5 项生成结构化交接摘要,**按项目写入 `~/.claude/handoff/<项目名>.md`(跨项目互不覆盖)**,再提示 `/compact` 释放上下文。
- **背景**:`/compact` 无法每次自动带约束(`PreCompact` hook 不支持注入文本、自定义命令也触发不了内置压缩),所以用这个命令把交接清单固化下来。

## 安装

```bash
# git bash / Linux / macOS(在仓库根目录执行)
cp commands/hc.md ~/.claude/commands/

# Windows PowerShell
Copy-Item commands/hc.md $HOME\.claude\commands\
```

装完在 Claude Code 里敲 `/hc`。改完命令内容后,**新开会话**才生效(当前会话不会热加载)。
