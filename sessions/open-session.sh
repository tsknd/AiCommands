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
PUBLISHER="${CLAUDE_PUBLISHER:-anthropic.claude-code}"   # 扩展ID,魔改/中转扩展可用 CLAUDE_PUBLISHER 环境变量覆盖

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

# 按前缀匹配 *.jsonl(支持 --all 时跨项目)
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
