# ===== Claude Code 会话工具 (PowerShell) =====
# lss — 列出历史会话(磁盘全量,含面板没显示的旧会话)
#   lss              当前项目全部会话(按日期升序,旧在前)
#   lss 关键词        模糊搜标题/id
#   lss --all        所有项目
# oss — 按 id 前缀打开旧会话(唯一即开,自动唤起 VSCode)
#   oss e483ca06     当前项目按前缀打开
#   oss --all <id>   所有项目里找
#   $env:OSS_DRY=1; oss <id>   只打印 URI 不实际唤起
# ============================================

$_ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$_Projects  = Join-Path $_ClaudeDir 'projects'
$_Publisher = 'anthropic.claude-code'

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
    $all = $false; $full = $false; $filter = ''
    foreach ($a in $Rest) { if ($a -in '--all','-all','-a') { $all = $true } elseif ($a -in '--full','-f') { $full = $true } else { $filter = $a } }
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
            if ($filter -and -not ($t -like "*$filter*" -or $sid -like "*$filter*")) {
                if (-not $full) { continue }
                $bodyHit = $false
                foreach ($line in [System.IO.File]::ReadLines($f.FullName, [System.Text.Encoding]::UTF8)) {
                    if ($line.Contains($filter)) { $bodyHit = $true; break }
                }
                if (-not $bodyHit) { continue }
            }
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
