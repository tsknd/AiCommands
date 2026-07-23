# Claude Code 会话工具(lss / oss)安装指南

> 让另一台电脑照此文档安装。这套工具解决一个痛点:Claude Code(VSCode 扩展)**会话历史面板只显示最近约 13~30 天的会话,且范围不可配置**,更早的会话在面板里看不到,但 `.jsonl` 文件还在磁盘上。下面两个命令把磁盘上的全部会话列出来、并能按 ID 一键打开。

---

## 一、两个命令速览

| 命令 | 作用 |
|------|------|
| `lss` | 列出**当前项目**的全部历史会话(带标题,按日期升序,旧的在最上面) |
| `lss 关键词` | 在当前项目里模糊搜「标题 + session-id」 |
| `lss --all` | 列出**所有项目**的全部会话 |
| `oss <id前缀>` | 按 session-id 前缀打开旧会话(前缀在范围内唯一即可,自动补全完整 UUID + 唤起 VSCode) |
| `oss --all <id>` | 在所有项目里找并打开(用于打开别的项目的会话) |

### 典型流程

```bash
lss            # 找到想打开的旧会话,记住 id 前几位
oss e483ca06   # 用前缀打开(唯一就开)
```

### 三种匹配行为(oss)

- **唯一匹配** → 直接拼 `vscode://anthropic.claude-code/open?session=<完整id>` 并唤起 VSCode
- **多个匹配** → 列出全部完整 id,提示用更长的前缀
- **无匹配** → 提示 `用 lss 查看可用会话`

---

## 二、安装

> 提供两套:**A. git bash / Linux / macOS 终端**;**B. Windows PowerShell**。
> 两套功能完全等价,装你常用的那个即可;都用也行。

### 前置条件

- 已安装 Claude Code 的 VSCode 扩展(扩展 ID 见下文「原理」一节,默认 `anthropic.claude-code`)。
- 会话文件存放在:`~/.claude/projects/<项目目录名>/*.jsonl`(Windows 为 `C:\Users\<你>\.claude\projects\...`)。
- `lss` 需要 `python` 或 `python3`(纯 PowerShell 版不需要 Python)。

---

### 方式 A:git bash / 通用 shell(需要 Python)

#### A1. 创建脚本文件 `~/.claude/ls-sessions.sh`

```bash
#!/usr/bin/env bash
# ls-sessions.sh — 列出 Claude Code 历史会话(磁盘全量,含面板没显示的旧会话)
#
# 用法:
#   bash ~/.claude/ls-sessions.sh              列出当前项目的全部会话(按日期升序,旧在前)
#   bash ~/.claude/ls-sessions.sh --all        列出所有项目的全部会话
#   bash ~/.claude/ls-sessions.sh 关键词        在当前项目按标题/id 模糊搜索
#   bash ~/.claude/ls-sessions.sh --all 关键词  所有项目里模糊搜索
#
# 找到想打开的旧会话后,用 URI handler 直接 resume(绕过面板 13 天上限):
#   vscode://anthropic.claude-code/open?session=<session-id>

set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROJECTS="$CLAUDE_DIR/projects"
PUBLISHER="${CLAUDE_PUBLISHER:-anthropic.claude-code}"   # 扩展ID,魔改/中转扩展可用 CLAUDE_PUBLISHER 覆盖

[ -d "$PROJECTS" ] || { echo "会话目录不存在: $PROJECTS"; exit 1; }

all=0
filter=""
for a in "$@"; do
  case "$a" in
    --all|-all|-a) all=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) filter="$a" ;;
  esac
done

# 把当前工作目录映射成 Claude Code 的 projects 子目录名
derive_proj() {
  local winpath proj
  winpath=$(cygpath -m "$PWD" 2>/dev/null || pwd -W 2>/dev/null || pwd)
  proj=$(printf '%s' "$winpath" | sed 's/[^A-Za-z0-9]/-/g')
  printf '%s' "${proj,}"   # 首字母小写,适配盘符大小写
}

if [ "$all" -eq 1 ]; then
  mapfile -t dirs < <(find "$PROJECTS" -maxdepth 1 -mindepth 1 -type d)
else
  proj=$(derive_proj)
  if [ ! -d "$PROJECTS/$proj" ]; then
    echo "当前目录没有对应的会话目录: $PROJECTS/$proj" >&2
    echo "现有项目:" >&2
    ls -1 "$PROJECTS" 2>/dev/null | sed 's/^/  /' >&2
    exit 1
  fi
  dirs=("$PROJECTS/$proj")
fi

PY=$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)
[ -n "$PY" ] || { echo "需要 python 或 python3"; exit 1; }

PYTHONIOENCODING=utf-8 PUBLISHER="$PUBLISHER" "$PY" - "$filter" "${dirs[@]}" <<'PY'
import json, os, sys, glob, time
filter = sys.argv[1].lower() if len(sys.argv) > 1 and sys.argv[1] else ""
dirs = sys.argv[2:]
PUBLISHER = os.environ.get("PUBLISHER", "anthropic.claude-code")

def first_text(path):
    # 标题优先级: custom-title(用户手改) > ai-title(AI生成) > summary(旧格式) > 首条user消息
    # 取每类标题的最后一条(最新),而非第一条
    titles = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try: o = json.loads(line)
                except Exception: continue
                t = o.get("type")
                if t == "custom-title" and o.get("customTitle"):
                    titles["custom"] = o["customTitle"]
                elif t == "ai-title" and o.get("aiTitle"):
                    titles["ai"] = o["aiTitle"]
                elif t == "summary" and o.get("summary"):
                    titles["summary"] = o["summary"]
        for _k in ("custom", "ai", "summary"):
            if titles.get(_k):
                return titles[_k]
        # 都没有再回退到首条 user 消息
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try: o = json.loads(line)
                except Exception: continue
                if o.get("type") == "user":
                    c = o.get("message", {}).get("content")
                    if isinstance(c, str): return c
                    if isinstance(c, list):
                        for it in c:
                            if isinstance(it, dict) and it.get("type") == "text":
                                return it.get("text", "")
    except Exception:
        return ""
    return ""

rows = []
for d in dirs:
    for f in glob.glob(os.path.join(d, "*.jsonl")):
        t = first_text(f).replace("\n", " ").strip()
        sid = os.path.basename(f)[:-6]
        if filter and filter not in t.lower() and filter not in sid.lower():
            continue
        proj_tail = os.path.basename(os.path.normpath(d)).split("-")[-1]
        rows.append((time.strftime("%Y-%m-%d %H:%M", time.localtime(os.path.getmtime(f))),
                     proj_tail, sid, t[:48]))

rows.sort()
print("日期           | 项目   | session-id                           | 标题(customTitle/aiTitle/首条消息)")
print("-" * 118)
for r in rows:
    uri = f"vscode://{PUBLISHER}/open?session={r[2]}"
    sid_link = f"\033]8;;{uri}\033\\{r[2]}\033]8;;\033\\"
    print(f"{r[0]} | {r[1]:<6} | {sid_link} | {r[3]}")
print(f"\n共 {len(rows)} 个会话  |  点上面的 session-id 直接打开(或: oss <id前缀>)")
PY
```

#### A2. 创建脚本文件 `~/.claude/open-session.sh`

```bash
#!/usr/bin/env bash
# open-session.sh — 按 session-id(支持短前缀)打开 Claude Code 旧会话
#
# 用法:
#   oss <id>          当前项目里按 id 前缀匹配并打开(例: oss e483ca06)
#   oss --all <id>    所有项目里匹配(用于打开别的项目的会话)
#   OSS_DRY=1 oss <id>   只打印 URI 不实际唤起(调试用)
#
# 前缀只要在范围内唯一即可,无需敲完整 UUID。
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROJECTS="$CLAUDE_DIR/projects"
PUBLISHER="${CLAUDE_PUBLISHER:-anthropic.claude-code}"   # 扩展ID,魔改/中转扩展可用 CLAUDE_PUBLISHER 覆盖

all=0
id=""
for a in "$@"; do
  case "$a" in
    --all|-all|-a) all=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) id="$a" ;;
  esac
done

[ -n "$id" ] || { echo "用法: oss <session-id 或前缀>   例: oss e483ca06"; exit 1; }

derive_proj() {
  local winpath proj
  winpath=$(cygpath -m "$PWD" 2>/dev/null || pwd -W 2>/dev/null || pwd)
  proj=$(printf '%s' "$winpath" | sed 's/[^A-Za-z0-9]/-/g')
  printf '%s' "${proj,}"
}

if [ "$all" -eq 1 ]; then
  searchdir="$PROJECTS"
else
  proj=$(derive_proj)
  searchdir="$PROJECTS/$proj"
  [ -d "$searchdir" ] || { echo "当前目录无对应会话目录: $searchdir"; exit 1; }
fi

matches=()
while IFS= read -r f; do
  matches+=("$f")
done < <(find "$searchdir" -maxdepth 2 -name "${id}*.jsonl" 2>/dev/null)

count=${#matches[@]}
if [ "$count" -eq 0 ]; then
  echo "没找到匹配「$id」的会话。用 lss 查看可用会话。"
  exit 1
elif [ "$count" -gt 1 ]; then
  echo "「$id」匹配到 $count 个,请用更长的前缀:"
  for f in "${matches[@]}"; do
    echo "  $(basename "$f" .jsonl)"
  done
  exit 1
fi

sid=$(basename "${matches[0]}" .jsonl)
uri="vscode://${PUBLISHER}/open?session=${sid}"
echo "打开会话: $sid"
echo "  $uri"

if [ -n "${OSS_DRY:-}" ]; then
  echo "[dry-run] 未实际唤起"
else
  powershell.exe -NoProfile -Command "Start-Process '${uri}'" >/dev/null 2>&1 \
    && echo "已唤起 VSCode" \
    || echo "自动唤起失败,请把上面那行 URI 贴进 Win+R 运行框。"
fi
```

> ⚠️ **非 Windows 系统**:把 `open-session.sh` 末尾的 `powershell.exe Start-Process` 换成系统对应的开 URI 命令:
> - **macOS**:`open "$uri"`
> - **Linux**:`xdg-open "$uri" >/dev/null 2>&1` 或 `command -v xdg-open >/dev/null && xdg-open "$uri"`

#### A3. 配置别名 `lss` / `oss`

在 `~/.bashrc`(或 `~/.zshrc`)追加:

```bash
# 列出 Claude Code 历史会话: lss | lss 关键词 | lss --all
alias lss='bash ~/.claude/ls-sessions.sh'
# 打开旧会话(按id前缀): oss e483ca06 | oss --all <id>
alias oss='bash ~/.claude/open-session.sh'
```

> macOS / Linux 用 zsh:别名放 `~/.zshrc`,写法相同。**注意**:`open-session.sh` 用了 bash 4+ 的 `${proj,}` 和 `mapfile`,zsh 用户请保持别名里的 `bash` 开头来调用,别直接 `zsh open-session.sh`。

然后让登录 shell 也能读到别名。若 `~/.bash_profile` 不存在,创建:

```bash
# ~/.bash_profile
[ -f ~/.bashrc ] && . ~/.bashrc
```

生效:新开终端,或当前终端 `source ~/.bashrc`。

---

### 方式 B:Windows PowerShell(纯 PS,不依赖 Python/bash)

#### B1. 找到你的 PowerShell 配置文件路径

在 PowerShell 里跑:

```powershell
$PROFILE
```

- Windows PowerShell 5.1:`C:\Users\<你>\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`
- PowerShell 7(pwsh):`C:\Users\<你>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`
- (若 Documents 被 OneDrive 重定向,路径会变成 `...\OneDrive\Documents\...`,**以 `$PROFILE` 实际输出为准**)

#### B2. 创建 profile 文件(若不存在)

```powershell
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
```

#### B3. 把下面整段追加进 `$PROFILE`

```powershell
# ===== Claude Code 会话工具 (PowerShell) =====
$_ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$_Projects  = Join-Path $_ClaudeDir 'projects'
$_Publisher = 'anthropic.claude-code'   # 扩展ID,魔改/中转扩展请改这里

function _ClaudeProjDir {
    $raw = (Get-Location).Path
    $name = -join ($raw.ToCharArray() | ForEach-Object { if ($_ -match '[A-Za-z0-9]') { $_ } else { '-' } })
    if ($name.Length -gt 1) { $name = $name.Substring(0,1).ToLower() + $name.Substring(1) }
    return Join-Path $_Projects $name
}

function _ClaudeFirstText([string]$Path) {
    try {
        # 标题优先级: custom-title(用户手改) > ai-title > summary(旧),取每类最后一条(最新)
        $titles = @{}
        foreach ($line in [System.IO.File]::ReadLines($Path, [System.Text.Encoding]::UTF8)) {
            try { $o = $line | ConvertFrom-Json } catch { continue }
            if ($o.type -eq 'custom-title' -and $o.customTitle) { $titles['custom'] = [string]$o.customTitle }
            elseif ($o.type -eq 'ai-title' -and $o.aiTitle) { $titles['ai'] = [string]$o.aiTitle }
            elseif ($o.type -eq 'summary' -and $o.summary) { $titles['summary'] = [string]$o.summary }
        }
        foreach ($k in 'custom','ai','summary') { if ($titles[$k]) { return $titles[$k] } }
        # 都没有再回退到首条 user 消息
        foreach ($line in [System.IO.File]::ReadLines($Path, [System.Text.Encoding]::UTF8)) {
            try { $o = $line | ConvertFrom-Json } catch { continue }
            if ($o.type -eq 'user') {
                $c = $o.message.content
                if ($c -is [string]) { return $c }
                foreach ($it in $c) { if ($it.type -eq 'text') { return [string]$it.text } }
            }
        }
    } catch { }
    return ''
}

function lss {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
    $all = $false; $filter = ''
    foreach ($a in $Rest) { if ($a -in '--all','-all','-a') { $all = $true } else { $filter = $a } }
    if (-not (Test-Path $_Projects)) { Write-Host "会话目录不存在: $_Projects"; return }
    if ($all) { $dirs = Get-ChildItem $_Projects -Directory }
    else {
        $pd = _ClaudeProjDir
        if (-not (Test-Path $pd)) {
            Write-Host "当前目录无对应会话目录: $pd" -ForegroundColor Yellow
            Write-Host "现有项目:"
            Get-ChildItem $_Projects -Directory | ForEach-Object { Write-Host "  $($_.Name)" }
            return
        }
        $dirs = @(Get-Item $pd)
    }
    $rows = @()
    foreach ($d in $dirs) {
        foreach ($f in Get-ChildItem $d.FullName -Filter *.jsonl -File) {
            $t = (_ClaudeFirstText $f.FullName) -replace "[\r\n]+", ' '
            $sid = $f.BaseName
            if ($filter -and -not ($t -like "*$filter*" -or $sid -like "*$filter*")) { continue }
            $tt = $t.Trim()
            if ($tt.Length -gt 48) { $tt = $tt.Substring(0,48) }
            $rows += [PSCustomObject]@{ 日期=$f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'); 项目=$d.Name.Split('-')[-1]; SessionId=$sid; 标题=$tt }
        }
    }
    if ($rows.Count -eq 0) { Write-Host "没有匹配的会话"; return }
    Write-Host ("{0,-16} | {1,-6} | {2,-36} | {3}" -f '日期','项目','session-id','标题(customTitle/aiTitle/首条消息)')
    Write-Host ('-' * 118)
    foreach ($r in ($rows | Sort-Object 日期)) {
        $uri = "vscode://$_Publisher/open?session=$($r.SessionId)"
        $link = "`e]8;;$uri`e\$($r.SessionId)`e]8;;`e\"
        $tt = $r.标题
        Write-Host ("{0,-16} | {1,-6} | {2,-36} | {3}" -f $r.日期, $r.项目, $link, $tt)
    }
    Write-Host "共 $($rows.Count) 个会话  |  点上面的 session-id 直接打开(或: oss <id前缀>)"
}

function oss {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
    $all = $false; $id = ''
    foreach ($a in $Rest) {
        if ($a -in '--all','-all','-a') { $all = $true }
        elseif ($a -in '-h','--help') { Write-Host '用法: oss <session-id 或前缀>   例: oss e483ca06'; return }
        else { $id = $a }
    }
    if (-not $id) { Write-Host '用法: oss <session-id 或前缀>   例: oss e483ca06'; return }
    if ($all) { $ms = Get-ChildItem $_Projects -Recurse -Depth 1 -Filter "$id*.jsonl" -File -ErrorAction SilentlyContinue }
    else {
        $pd = _ClaudeProjDir
        if (-not (Test-Path $pd)) { Write-Host "当前目录无对应会话目录: $pd"; return }
        $ms = Get-ChildItem $pd -Filter "$id*.jsonl" -File -ErrorAction SilentlyContinue
    }
    if (-not $ms -or $ms.Count -eq 0) { Write-Host "没找到匹配「$id」的会话。用 lss 查看可用会话。"; return }
    if ($ms.Count -gt 1) {
        Write-Host "「$id」匹配到 $($ms.Count) 个,请用更长的前缀:"
        $ms | ForEach-Object { Write-Host "  $($_.BaseName)" }
        return
    }
    $sid = $ms[0].BaseName
    $uri = "vscode://$_Publisher/open?session=$sid"
    Write-Host "打开会话: $sid"
    Write-Host "  $uri"
    if ($env:OSS_DRY) { Write-Host '[dry-run] 未实际唤起' }
    else {
        try { Start-Process $uri; Write-Host '已唤起 VSCode' }
        catch { Write-Host "自动唤起失败,请把上面那行 URI 贴进 Win+R 运行框。" }
    }
}
```

#### B4. 让 profile 生效

新开 PowerShell 窗口即可。或当前窗口:`. $PROFILE`(dot-source)。

> 若遇到执行策略报错:`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`(profile 属于本地脚本,RemoteSigned 即可)。

---

## 三、打开旧会话的 URI(手动备用方式)

`oss` 唤起失败时,可手动打开。完整格式:

```
vscode://anthropic.claude-code/open?session=<完整-session-id>
```

触发方式(任选):
- **Win+R** 运行框粘贴整行 URI 回车(最干净,不弹确认)
- 浏览器地址栏粘贴回车 → 允许打开 VS Code
- PowerShell:`Start-Process "vscode://anthropic.claude-code/open?session=<id>"`
- git bash:`start "" "vscode://anthropic.claude-code/open?session=<id>"`

---

## 四、原理与关键细节(给安装者/AI 看)

1. **会话存哪了**:Claude Code 把每个会话存成 `~/.claude/projects/<项目目录名>/<session-id>.jsonl`,**全量保留、不会因面板上限被删**。面板上限只影响「显示」,不影响磁盘文件。

2. **项目目录名怎么来的**(推导规则,踩坑点):
   - 取当前工作目录的绝对路径(Windows 风格,如 `E:\soft\php\phpstudy_pro\WWW\xfawu`)
   - 把**所有非字母数字字符**(`:` `\` `/` `_` 空格 等)替换成 `-`
   - **首字母(盘符)转小写**
   - 结果:`e--soft-php-phpstudy-pro-WWW-xfawu`(注意 `e:` + `\` → `e--` 两个减号;`_` 也变 `-`;其余大小写保留)
   - 验证方法:列出 `~/.claude/projects/` 下的实际目录名,对照确认。

3. **标题取什么**(实测 jsonl 结构,2026-07 验证于 Claude Code v2.1.x):
   - 优先级:**`custom-title`(用户手改标题,字段 `customTitle`) > `ai-title`(AI 生成,字段 `aiTitle`) > `summary`(旧格式,字段 `summary`) > 首条 `user` 消息文本**。
   - 同一类标题在会话期间可能有多条(每次更新都 append 一条),脚本取**最后一条**(即最新标题)。
   - **本机实测**:`ai-title` 普遍存在,`summary` 已不存在(0 条),`custom-title` 在约一半会话里存在。所以**必须按上面的优先级取**,只取 `aiTitle` 会漏掉用户手改的标题。
   - 字段名是 `aiTitle` / `customTitle`(驼峰),**不是** `title` 或 `summary`。
   - 没有任何标题记录时回退首条 user 消息(截断 48 字符)。

4. **扩展 ID**:`anthropic.claude-code`(官方)。若装的是魔改/中转扩展,URI 里的 publisher 段要改 —— 查法:看 `~/.vscode/extensions/` 下 `anthropic.claude-code-*` 或 `*claude*` 目录名。URI 协议前缀:标准 VSCode 用 `vscode://`;VSCodium 用 `vscodium://`;Cursor 用 `cursor://`;Windsurf 用 `windsurf://`。bash 版还支持环境变量 `CLAUDE_PUBLISHER` 覆盖。

5. **可点击链接**:输出里的 session-id 用了终端的 **OSC 8 超链接**转义序列(`ESC ] 8 ; ; <uri> ESC \ <text> ESC ] 8 ; ; ESC \`),VSCode 集成终端 / Windows Terminal / iTerm2 等会渲染成可点击链接,**Ctrl+点击**(或 Cmd+点击)即打开对应会话。传统控制台(老 cmd、重定向到文件)不识别,会看到原始字符,这时用 `oss <id前缀>` 代替。PowerShell 版用 `` `e ``(PS 7+ 的 ESC),**需 PowerShell 7 以上**;PS 5.1 不支持 `` `e ``,会原样输出——5.1 用户请用 bash 版或 `oss` 命令。

6. **重要限制**:
   - 用 URI 打开某会话时,**当前 VSCode 打开的工作区目录必须与该会话所属项目一致**,否则扩展报 not found。要打开别的项目的会话:先把 VSCode 工作区切到那个目录。
   - `oss` 的 id 要给到「在范围内唯一」的前缀;不唯一时会列出全部匹配让你加长。
   - 面板的「只显示 N 天 / 显示范围」**是产品设定、不可配置**(截至 Claude Code v2.1.x),`settings.json` 的 `cleanupPeriodDays` 只管磁盘文件的清理周期,不管面板显示范围。这套 `lss`/`oss` 就是为了绕过这个面板限制。

---

## 五、卸载

- **bash**:删除 `~/.claude/ls-sessions.sh`、`~/.claude/open-session.sh`,并从 `~/.bashrc` 移除两行 `alias`。
- **PowerShell**:编辑 `$PROFILE`,删除 `# ===== Claude Code 会话工具` 到结尾的整段。

---

## 六、速查

```bash
lss                 # 看清单(当前项目,旧在前)
lss 关键词          # 搜
lss --all           # 所有项目
oss e483ca06        # 开(前缀唯一即可)
oss --all <id>      # 跨项目开
```
