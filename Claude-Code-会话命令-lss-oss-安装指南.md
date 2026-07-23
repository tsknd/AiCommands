# Claude Code 会话工具(lss / oss)安装指南

> 让另一台电脑照此安装。解决 Claude Code(VSCode 扩展)会话面板**只显示最近约 13~30 天、且范围不可配置**的痛点:更早的会话面板看不到,但 `.jsonl` 还在磁盘上。`lss` 列出磁盘全部会话(支持正文全文搜索),`oss` 按 id 前缀一键打开。

## 本目录文件

| 文件 | 作用 |
|---|---|
| `ls-sessions.sh` | 列会话脚本(bash 版,需 `python3`) |
| `open-session.sh` | 打开会话脚本(bash 版) |
| `claude-session-profile.ps1` | PowerShell 函数(贴入 `$PROFILE`,纯 PS,不依赖 python/bash) |
| `安装指南.md` | 本文件 |
| `使用说明.md` | 日常命令速查 |

> 把整个目录拷到另一台电脑即可。脚本文件是实际可用的,不用从 markdown 复制代码。

---

## 命令速览

| 命令 | 作用 |
|------|------|
| `lss` | 列出**当前项目**全部会话(按日期升序,旧在前,带标题) |
| `lss 关键词` | 搜**标题 + session-id**(快) |
| `lss -f 关键词` | 搜**标题 + 正文全文**(慢但全,找「聊过某话题」的会话) |
| `lss --all` | 列出**所有项目**的会话 |
| `lss --all -f 关键词` | 所有项目 + 正文全文搜索 |
| `oss <id前缀>` | 按 session-id 前缀打开(唯一即开,自动唤起 VSCode) |
| `oss --all <id>` | 跨项目打开 |

---

## 一、安装(任选一套,功能等价)

### 前置条件
- 已装 Claude Code 的 VSCode 扩展(默认 ID `anthropic.claude-code`)。
- 会话文件在:`~/.claude/projects/<项目目录名>/*.jsonl`。
- bash 版 `lss` 需要 `python3`(PowerShell 版不需要)。

### 方式 A:git bash(Windows)/ Linux / macOS

1. 把 `ls-sessions.sh`、`open-session.sh` 放到 `~/.claude/`:
   ```bash
   mkdir -p ~/.claude
   cp ls-sessions.sh open-session.sh ~/.claude/
   ```

2. 在 `~/.bashrc`(macOS/Linux 用 zsh 则 `~/.zshrc`)追加别名:
   ```bash
   alias lss='bash ~/.claude/ls-sessions.sh'
   alias oss='bash ~/.claude/open-session.sh'
   ```
   > zsh 用户:保持别名里的 `bash` 开头,别直接 `zsh open-session.sh`(脚本用了 bash 4+ 的 `${var,}` 和 `mapfile`)。

3. 若 `~/.bash_profile` 不存在,创建(让登录 shell 也加载别名):
   ```bash
   echo '[ -f ~/.bashrc ] && . ~/.bashrc' >> ~/.bash_profile
   ```

4. 非 Windows 系统:改 `open-session.sh` 末尾唤起命令 ——
   - macOS:`open "$uri"`
   - Linux:`xdg-open "$uri" >/dev/null 2>&1`

5. 生效:新开终端,或 `source ~/.bashrc`。

### 方式 B:Windows PowerShell 7+(pwsh)

> 需 PowerShell 7 以上(用了 `` `e `` 转义符做可点击链接;PS 5.1 不支持,5.1 用户请用方式 A)。

1. 找到 profile 路径(以实际输出为准):
   ```powershell
   $PROFILE
   ```

2. 把 `claude-session-profile.ps1` 的**全部内容追加**进 `$PROFILE`:
   ```powershell
   Get-Content claude-session-profile.ps1 | Add-Content $PROFILE
   ```
   (若 `$PROFILE` 不存在先建:`New-Item -ItemType File -Path $PROFILE -Force`)

3. 生效:新开 PowerShell,或 `. $PROFILE`。

4. 遇执行策略报错:`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`。

---

## 二、原理与关键细节(给安装者/AI)

1. **会话存哪**:每个会话是 `~/.claude/projects/<项目目录名>/<session-id>.jsonl`,**全量保留、不会因面板上限被删**。面板上限只影响显示。

2. **项目目录名推导**(踩坑点):取当前工作目录绝对路径 → 把所有非字母数字字符(`:` `\` `/` `_` 空格)替换成 `-` → **首字母(盘符)小写**。例:`E:\soft\php\phpstudy_pro\WWW\xfawu` → `e--soft-php-phpstudy-pro-WWW-xfawu`(`e:`+`\`=`e--`,`_`→`-`,其余大小写保留)。验证:`ls ~/.claude/projects/` 对照。

3. **标题取什么**(2026-07 实测 v2.1.209):
   - 优先级 **`custom-title`/`customTitle`(用户手改) > `ai-title`/`aiTitle`(AI 生成) > `summary`(旧,本机已 0 条) > 首条 `user` 消息**。
   - 同类标题会话期间可能多条,脚本取**最后一条**(最新)。字段是 `aiTitle`/`customTitle`(驼峰)。
   - **只搜标题会漏**:很多会话关键词只在正文,标题是 AI 另起的概括名。所以提供 `-f` 做正文全文搜索(扫 jsonl 每一行,含文件名/路径/消息)。

4. **扩展 ID**:`anthropic.claude-code`(官方)。魔改/中转扩展要改 publisher 段 —— 查法:`ls ~/.vscode/extensions/` 找 `*claude*` 目录名。协议前缀:VSCode=`vscode://`、VSCodium=`vscodium://`、Cursor=`cursor://`。bash 版还支持环境变量 `CLAUDE_PUBLISHER` 覆盖。

5. **可点击链接**:输出的 session-id 用 OSC 8 超链接,VSCode 集成终端 / Windows Terminal / iTerm2 可 **Ctrl+点击**直接打开。老控制台不识别则用 `oss`。

6. **限制**:
   - 用 URI 打开会话时,**当前 VSCode 工作区须与该会话所属项目一致**,否则报 not found。
   - `oss` 前缀要在范围内唯一;不唯一会列出全部匹配。
   - 面板显示范围是产品设定不可调;`cleanupPeriodDays` 只管磁盘清理,不管面板。

---

## 三、打开旧会话的 URI(手动备用)

`oss` 唤起失败时,手动打开:
```
vscode://anthropic.claude-code/open?session=<完整-session-id>
```
- Win+R 粘贴回车(最干净)
- PowerShell:`Start-Process "vscode://anthropic.claude-code/open?session=<id>"`
- git bash:`start "" "vscode://anthropic.claude-code/open?session=<id>"`

---

## 四、卸载

- **bash**:删 `~/.claude/ls-sessions.sh`、`~/.claude/open-session.sh`,从 `~/.bashrc` 移除两行别名。
- **PowerShell**:编辑 `$PROFILE`,删除 `# ===== Claude Code 会话工具` 到结尾整段。
