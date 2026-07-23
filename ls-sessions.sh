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
PUBLISHER="${CLAUDE_PUBLISHER:-anthropic.claude-code}"

[ -d "$PROJECTS" ] || { echo "会话目录不存在: $PROJECTS"; exit 1; }

all=0
full=0
filter=""
for a in "$@"; do
  case "$a" in
    --all|-all|-a) all=1 ;;
    --full|-f) full=1 ;;
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

PYTHONIOENCODING=utf-8 FULL="$full" PUBLISHER="$PUBLISHER" "$PY" - "$filter" "${dirs[@]}" <<'PY'
import json, os, sys, glob, time
filter = sys.argv[1].lower() if len(sys.argv) > 1 and sys.argv[1] else ""
dirs = sys.argv[2:]
PUBLISHER = os.environ.get("PUBLISHER", "anthropic.claude-code")
FULL = os.environ.get("FULL") == "1"

def body_has(path, kw):
    lk = kw.lower()
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                if lk in line.lower():
                    return True
    except Exception:
        pass
    return False

def first_text(path):
    try:
        titles = {}
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try: o = json.loads(line)
                except Exception: continue
                t = o.get("type")
                # 标题优先级: custom-title(用户手改) > ai-title > summary(旧),取每类最后一条(最新)
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
        if filter:
            lk = filter.lower()
            if lk not in t.lower() and lk not in sid.lower():
                if not (FULL and body_has(f, filter)):
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
