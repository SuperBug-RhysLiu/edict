# ══════════════════════════════════════════════════════════════
# 三省六部 · OpenClaw Multi-Agent System 一键安装脚本 (Windows)
# PowerShell 版本 — 对应 install.sh
# ══════════════════════════════════════════════════════════════
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$REPO_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$OC_HOME = Join-Path $env:USERPROFILE ".openclaw"
$OC_CFG = Join-Path $OC_HOME "openclaw.json"

function Write-Banner {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host "║  🏛️  三省六部 · OpenClaw Multi-Agent     ║" -ForegroundColor Blue
    Write-Host "║       安装向导 (Windows)                  ║" -ForegroundColor Blue
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Blue
    Write-Host ""
}

function Log   { param($msg) Write-Host "✅ $msg" -ForegroundColor Green }
function Warn  { param($msg) Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Error { param($msg) Write-Host "❌ $msg" -ForegroundColor Red }
function Info  { param($msg) Write-Host "ℹ️  $msg" -ForegroundColor Blue }

# ── Step 0: 依赖检查 ──
function Check-Deps {
    Info "检查依赖..."

    $oc = Get-Command openclaw -ErrorAction SilentlyContinue
    if (-not $oc) {
        Error "未找到 openclaw CLI。请先安装 OpenClaw: https://openclaw.ai"
        exit 1
    }
    Log "OpenClaw CLI: OK"

    $py = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $py) {
        $py = Get-Command python -ErrorAction SilentlyContinue
    }
    if (-not $py) {
        Error "未找到 python3 或 python"
        exit 1
    }
    $global:PYTHON = $py.Source
    Log "Python: $($global:PYTHON)"

    if (-not (Test-Path $OC_CFG)) {
        Error "未找到 openclaw.json。请先运行 openclaw 完成初始化。"
        exit 1
    }
    Log "openclaw.json: $OC_CFG"
}

# ── Step 0.5: 备份已有 Agent 数据 ──
function Backup-Existing {
    $hasExisting = Get-ChildItem -Path $OC_HOME -Directory -Filter "workspace-*" -ErrorAction SilentlyContinue
    if ($hasExisting) {
        Info "检测到已有 Agent Workspace，自动备份中..."
        $ts = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupDir = Join-Path $OC_HOME "backups\pre-install-$ts"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

        Get-ChildItem -Path $OC_HOME -Directory -Filter "workspace-*" | ForEach-Object {
            # 跳过 Junction/ReparsePoint（符号链接可能导致复制失败）
            $item = Get-Item $_.FullName
            if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Copy-Item -Path $_.FullName -Destination (Join-Path $backupDir $_.Name) -Recurse -ErrorAction SilentlyContinue
            } else {
                # 只备份 SOUL.md 和 AGENTS.md
                $ws = $_.FullName
                $dest = Join-Path $backupDir $_.Name
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                Copy-Item (Join-Path $ws "SOUL.md") $dest -ErrorAction SilentlyContinue
                Copy-Item (Join-Path $ws "AGENTS.md") $dest -ErrorAction SilentlyContinue
            }
        }

        if (Test-Path $OC_CFG) {
            Copy-Item $OC_CFG (Join-Path $backupDir "openclaw.json")
        }
        Log "已备份到: $backupDir"
    }
}

# ── Step 1: 创建 Workspace ──
function Create-Workspaces {
    Info "创建 Agent Workspace..."

    $agents = @("taizi","zhongshu","menxia","shangshu","hubu","libu","bingbu","xingbu","gongbu","libu_hr","zaochao")
    foreach ($agent in $agents) {
        $ws = Join-Path $OC_HOME "workspace-$agent"
        New-Item -ItemType Directory -Path (Join-Path $ws "skills") -Force | Out-Null

        $soulSrc = Join-Path $REPO_DIR "agents\$agent\SOUL.md"
        $soulDst = Join-Path $ws "SOUL.md"
        if (Test-Path $soulSrc) {
            if (Test-Path $soulDst) {
                $ts = Get-Date -Format "yyyyMMdd-HHmmss"
                Copy-Item $soulDst "$soulDst.bak.$ts"
                Warn "已备份旧 SOUL.md → $soulDst.bak.$ts"
            }
            $content = (Get-Content $soulSrc -Raw) -replace "__REPO_DIR__", $REPO_DIR
            Set-Content -Path $soulDst -Value $content -Encoding UTF8
        }
        Log "Workspace 已创建: $ws"

        # 删除 OpenClaw 自动生成的 BOOTSTRAP.md（会覆盖 SOUL.md 作用）
        $bootstrap = Join-Path $ws "BOOTSTRAP.md"
        if (Test-Path $bootstrap) {
            Remove-Item $bootstrap -Force
        }

        # AGENTS.md
        $agentsMd = @"
# AGENTS.md · 工作协议

1. 接到任务先回复"已接旨"。
2. 输出必须包含：任务ID、结果、证据/文件路径、阻塞项。
3. 需要协作时，回复尚书省请求转派，不跨部直连。
4. 涉及删除/外发动作必须明确标注并等待批准。
"@
        Set-Content -Path (Join-Path $ws "AGENTS.md") -Value $agentsMd -Encoding UTF8
    }
}

# ── Step 2: 注册 Agents ──
function Register-Agents {
    Info "注册三省六部 Agents..."

    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    Copy-Item $OC_CFG "$OC_CFG.bak.sansheng-$ts"
    Log "已备份配置: $OC_CFG.bak.*"

    $pyScript = @"
import json, pathlib, sys, os

cfg_path = pathlib.Path(os.environ['USERPROFILE']) / '.openclaw' / 'openclaw.json'
cfg = json.loads(cfg_path.read_text(encoding='utf-8'))

AGENTS = [
    {"id": "taizi",    "subagents": {"allowAgents": ["zhongshu"]}},
    {"id": "zhongshu", "subagents": {"allowAgents": ["menxia", "shangshu"]}},
    {"id": "menxia",   "subagents": {"allowAgents": ["shangshu", "zhongshu"]}},
    {"id": "shangshu", "subagents": {"allowAgents": ["zhongshu", "menxia", "hubu", "libu", "bingbu", "xingbu", "gongbu", "libu_hr"]}},
    {"id": "hubu",     "subagents": {"allowAgents": ["shangshu"]}},
    {"id": "libu",     "subagents": {"allowAgents": ["shangshu"]}},
    {"id": "bingbu",   "subagents": {"allowAgents": ["shangshu"]}},
    {"id": "xingbu",   "subagents": {"allowAgents": ["shangshu"]}},
    {"id": "gongbu",   "subagents": {"allowAgents": ["shangshu"]}},
    {"id": "libu_hr",  "subagents": {"allowAgents": ["shangshu"]}},
    {"id": "zaochao",  "subagents": {"allowAgents": []}},
]

agents_cfg = cfg.setdefault('agents', {})
agents_list = agents_cfg.get('list', [])
existing_ids = {a['id'] for a in agents_list}

added = 0
for ag in AGENTS:
    ag_id = ag['id']
    ws = str(pathlib.Path(os.environ['USERPROFILE']) / f'.openclaw/workspace-{ag_id}')
    if ag_id not in existing_ids:
        entry = {'id': ag_id, 'workspace': ws, **{k:v for k,v in ag.items() if k!='id'}}
        agents_list.append(entry)
        added += 1
        print(f'  + added: {ag_id}')
    else:
        print(f'  ~ exists: {ag_id} (skipped)')

agents_cfg['list'] = agents_list

# Fix #142: clean invalid binding pattern
bindings = cfg.get('bindings', [])
for b in bindings:
    match = b.get('match', {})
    if isinstance(match, dict) and 'pattern' in match:
        del match['pattern']
        print(f'  cleaned invalid pattern from binding: {b.get("agentId", "?")}')

# 设置默认 Agent 为太子
cfg['defaultAgent'] = 'taizi'
print('  👑 默认 Agent 设为: taizi')

cfg_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'Done: {added} agents added')
"@
    & $global:PYTHON -c $pyScript
    Log "Agents 注册完成"
}

# ── Step 3: 初始化 Data ──
function Init-Data {
    Info "初始化数据目录..."
    $dataDir = Join-Path $REPO_DIR "data"
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null

    foreach ($f in @("live_status.json","agent_config.json","model_change_log.json")) {
        $fp = Join-Path $dataDir $f
        if (-not (Test-Path $fp)) { Set-Content $fp "{}" -Encoding UTF8 }
    }
    Set-Content (Join-Path $dataDir "pending_model_changes.json") "[]" -Encoding UTF8
    Log "数据目录初始化完成"
}

# ── Step 3.3: 创建 data/scripts 目录连接 (Junction) ──
function Link-Resources {
    Info "创建 data/scripts 目录连接..."
    $linked = 0
    $agents = @("taizi","zhongshu","menxia","shangshu","hubu","libu","bingbu","xingbu","gongbu","libu_hr","zaochao")
    foreach ($agent in $agents) {
        $ws = Join-Path $OC_HOME "workspace-$agent"
        New-Item -ItemType Directory -Path $ws -Force | Out-Null

        # data 目录
        $wsData = Join-Path $ws "data"
        $srcData = Join-Path $REPO_DIR "data"
        if (-not (Test-Path $wsData)) {
            cmd /c mklink /J "$wsData" "$srcData" | Out-Null
            $linked++
        } elseif (-not ((Get-Item $wsData).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $ts = Get-Date -Format "yyyyMMdd-HHmmss"
            Rename-Item $wsData "$wsData.bak.$ts"
            cmd /c mklink /J "$wsData" "$srcData" | Out-Null
            $linked++
        }

        # scripts 目录
        $wsScripts = Join-Path $ws "scripts"
        $srcScripts = Join-Path $REPO_DIR "scripts"
        if (-not (Test-Path $wsScripts)) {
            cmd /c mklink /J "$wsScripts" "$srcScripts" | Out-Null
            $linked++
        } elseif (-not ((Get-Item $wsScripts).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $ts = Get-Date -Format "yyyyMMdd-HHmmss"
            Rename-Item $wsScripts "$wsScripts.bak.$ts"
            cmd /c mklink /J "$wsScripts" "$srcScripts" | Out-Null
            $linked++
        }
    }
    Log "已创建 $linked 个目录连接 (data/scripts → 项目目录)"
}

# ── Step 3.5: 设置 Agent 间通信可见性 ──
function Setup-Visibility {
    Info "配置 Agent 间消息可见性..."
    try {
        openclaw config set tools.sessions.visibility all 2>$null
        Log "已设置 tools.sessions.visibility=all"
    } catch {
        Warn "设置 visibility 失败，请手动执行: openclaw config set tools.sessions.visibility all"
    }
}

# ── Step 5: 重启 Gateway ──
function Restart-Gateway {
    Info "重启 OpenClaw Gateway..."
    try {
        openclaw gateway restart 2>$null
        Log "Gateway 重启成功"
    } catch {
        Warn "Gateway 重启失败，请手动重启: openclaw gateway restart"
    }
}

# ── Main ──
Write-Banner
Check-Deps
Backup-Existing
Create-Workspaces
Register-Agents
Setup-Visibility
Restart-Gateway

# 以下为看板系统准备，核心功能不需要
# Init-Data
# Link-Resources

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  🎉  三省六部安装完成！                          ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "下一步："
Write-Host "  1. 配置 API Key（如尚未配置）:"
Write-Host "     openclaw agents add taizi     # 按提示输入 Anthropic API Key"
Write-Host "     .\install.ps1                 # 重新运行以同步到所有 Agent"
Write-Host ""
Write-Host "  2. 开始使用:"
Write-Host "     openclaw chat taizi           # CLI 方式与 Agent 对话"
Write-Host ""
Write-Host "  🖥️  可选 - 看板系统:  docs/getting-started.md#可选看板系统"
Write-Host ""
Warn "首次安装必须配置 API Key，否则 Agent 会报错"
Info "文档: docs/getting-started.md"
