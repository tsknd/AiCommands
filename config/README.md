# 个人级配置文件

装到 `~/.claude/`(用户级,对所有项目生效)。Windows 下 `~` = `C:\Users\<你>\`。

> `CLAUDE.md` 在**会话启动时**一次性加载,所以装完要**新开会话**才生效,当前会话不会热加载。

## 文件

### `CLAUDE.md` — 会话压缩契约(自动压缩兜底)

- **作用**:当会话被 `/compact` 或上下文满自动压缩时,引导摘要保留 5 项交接信息(工作·文件 / 进度 / 待办 / 决策 / 踩坑)。
- **背景**:自动压缩**不经过** [`/hc`](../commands/README.md) 命令,可能把关键交接当闲聊丢掉;这份契约写在系统提示里,给自动压缩兜底。与 `/hc` 互补:`/hc` 管主动收尾,契约管自动压缩。

## 安装

### 新机器(还没有 `~/.claude/CLAUDE.md`)

```bash
cp config/CLAUDE.md ~/.claude/CLAUDE.md
```

### 已有 `~/.claude/CLAUDE.md`(里面有别的个人指令)

**只追加「会话压缩契约」那一段,别整个覆盖**。手动:打开 `config/CLAUDE.md`,把从下面这行开始到结尾的内容复制、贴到你的 `~/.claude/CLAUDE.md` 末尾:

```
## 会话压缩契约(自动压缩兜底用)
```

或用 sed(git bash 的 locale 是 UTF-8 时可用):

```bash
sed -n '/^## 会话压缩契约/,$p' config/CLAUDE.md >> ~/.claude/CLAUDE.md
```

## 卸载

从 `~/.claude/CLAUDE.md` 里删掉 `## 会话压缩契约` 标题到结尾整段。
