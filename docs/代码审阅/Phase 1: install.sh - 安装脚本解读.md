# Phase 1: install.sh 详细解读

---

## 一、整体结构

```
install.sh (420 行)
│
├── 第 1-26 行:     头部设置 (Shebang、变量、工具函数)
│
├── 第 28-48 行:    check_deps()        —— 检查依赖
├── 第 51-89 行:    backup_existing()   —— 备份已有数据
├── 第 92-121 行:   create_workspaces() —— 创建 Agent 工作空间
├── 第 124-186 行:  register_agents()   —— 注册 Agent 到配置文件
├── 第 189-236 行:  init_data()         —— 初始化数据文件
├── 第 239-290 行:  link_resources()    —— 创建符号链接
├── 第 293-301 行:  setup_visibility()  —— 配置通信可见性
├── 第 304-342 行:  sync_auth()         —— 同步 API Key
├── 第 345-367 行:  build_frontend()    —— 构建前端
├── 第 370-379 行:  first_sync()        —— 首次数据同步
├── 第 382-389 行:  restart_gateway()   —— 重启网关
│
└── 第 391-419 行:  主流程 (依次调用上述函数)
```

---

## 二、头部设置详解 (第 1-26 行)

### 第 1 行: Shebang

```bash
#!/bin/bash
```

| 符号 | 含义 |
|------|------|
| `#!` | Shebang，告诉系统用什么程序执行这个脚本 |
| `/bin/bash` | 使用 Bash 解释器 |

> **作用**: 当你运行 `./install.sh` 时，系统知道用 `/bin/bash` 来执行它

---

### 第 5 行: 错误时退出

```bash
set -e
```

| 命令 | 含义 |
|------|------|
| `set -e` | 任何命令返回非零状态码（失败）时，立即退出脚本 |

> **为什么需要**: 防止某个步骤失败后继续执行，造成数据损坏

**举例**:
```bash
# 如果没有 set -e
mkdir /root/some-dir    # 这个会失败（权限不足）
cp file.txt /root/some-dir/  # 这个也会失败，但脚本继续跑
# 最后显示"安装成功" —— 但其实没成功！

# 有了 set -e
mkdir /root/some-dir    # 失败 → 脚本立即停止，报错
```

---

### 第 7-9 行: 核心路径变量

```bash
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OC_HOME="$HOME/.openclaw"
OC_CFG="$OC_HOME/openclaw.json"
```

| 变量 | 值示例 | 含义 |
|------|--------|------|
| `REPO_DIR` | `/Users/xxx/edict` | 项目根目录（脚本所在目录） |
| `OC_HOME` | `/Users/xxx/.openclaw` | OpenClaw 安装目录 |
| `OC_CFG` | `/Users/xxx/.openclaw/openclaw.json` | OpenClaw 配置文件 |

**逐层拆解 `REPO_DIR`**:
```bash
"${BASH_SOURCE[0]}"           # 当前脚本的路径，如: ./install.sh
dirname "${BASH_SOURCE[0]}"   # 取目录部分，如: .
cd "$(dirname ...)"           # 切换到该目录
pwd                           # 获取绝对路径，如: /Users/xxx/edict
```

> **为什么这么写**: 确保无论你在哪个目录运行 `./install.sh`，`REPO_DIR` 都指向项目根目录

---

### 第 11 行: 颜色代码

```bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
```

| 变量 | ANSI 码 | 效果 |
|------|---------|------|
| `RED` | `\033[0;31m` | 红色文字 |
| `GREEN` | `\033[0;32m` | 绿色文字 |
| `YELLOW` | `\033[1;33m` | 黄色加粗 |
| `BLUE` | `\033[0;34m` | 蓝色文字 |
| `NC` | `\033[0m` | No Color，重置颜色 |

**使用方式**:
```bash
echo -e "${GREEN}✅ 成功${NC}"   # 输出绿色的 "✅ 成功"
echo -e "${RED}❌ 失败${NC}"     # 输出红色的 "❌ 失败"
```

---

### 第 13-26 行: 工具函数

```bash
banner() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
  ...
}

log()   { echo -e "${GREEN}✅ $1${NC}"; }      # 成功日志
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }    # 警告日志
error() { echo -e "${RED}❌ $1${NC}"; }        # 错误日志
info()  { echo -e "${BLUE}ℹ️  $1${NC}"; }      # 信息日志
```

| 函数 | 用途 | 示例调用 |
|------|------|----------|
| `banner()` | 打印大标题 | `banner` |
| `log()` | 成功消息（绿色✅） | `log "安装完成"` |
| `warn()` | 警告消息（黄色⚠️） | `warn "配置不存在"` |
| `error()` | 错误消息（红色❌） | `error "未找到依赖"` |
| `info()` | 信息消息（蓝色ℹ️） | `info "正在安装..."` |

---

## 三、各方法详解

---

### 方法 1: check_deps() —— 依赖检查

**位置**: 第 28-48 行

**作用**: 检查系统是否安装了必要的软件

```bash
check_deps() {
  info "检查依赖..."

  # 1. 检查 openclaw 命令是否存在
  if ! command -v openclaw &>/dev/null; then
    error "未找到 openclaw CLI。请先安装 OpenClaw: https://openclaw.ai"
    exit 1
  fi
  log "OpenClaw CLI: $(openclaw --version 2>/dev/null || echo 'OK')"

  # 2. 检查 python3 命令是否存在
  if ! command -v python3 &>/dev/null; then
    error "未找到 python3"
    exit 1
  fi
  log "Python3: $(python3 --version)"

  # 3. 检查 openclaw.json 配置文件是否存在
  if [ ! -f "$OC_CFG" ]; then
    error "未找到 openclaw.json。请先运行 openclaw 完成初始化。"
    exit 1
  fi
  log "openclaw.json: $OC_CFG"
}
```

**命令详解**:

| 命令 | 含义 |
|------|------|
| `command -v openclaw` | 检查 `openclaw` 命令是否在 PATH 中 |
| `&>/dev/null` | 把标准输出和错误都丢掉（静默检查） |
| `! command -v` | 如果命令**不存在** |
| `exit 1` | 退出脚本，返回状态码 1（表示失败） |
| `[ ! -f "$OC_CFG" ]` | 如果文件**不存在** |

**执行流程图**:
```
开始
  │
  ▼
┌─────────────────────┐
│ openclaw 命令存在？  │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     ▼           ▼
   是            否
     │           │
     ▼           ▼
  继续检查    报错退出 (exit 1)
     │
     ▼
┌─────────────────────┐
│ python3 命令存在？   │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     ▼           ▼
   是            否
     │           │
     ▼           ▼
  继续检查    报错退出
     │
     ▼
┌─────────────────────┐
│ openclaw.json 存在？ │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     ▼           ▼
   是            否
     │           │
     ▼           ▼
  检查通过    报错退出
```

---

### 方法 2: backup_existing() —— 备份已有数据

**位置**: 第 51-89 行

**作用**: 如果已有 Agent Workspace，先备份再覆盖

```bash
backup_existing() {
  AGENTS_DIR="$OC_HOME"
  BACKUP_DIR="$OC_HOME/backups/pre-install-$(date +%Y%m%d-%H%M%S)"
  HAS_EXISTING=false

  # 检查是否有已存在的 workspace
  for d in "$AGENTS_DIR"/workspace-*/; do
    if [ -d "$d" ]; then
      HAS_EXISTING=true
      break
    fi
  done

  if $HAS_EXISTING; then
    info "检测到已有 Agent Workspace，自动备份中..."
    mkdir -p "$BACKUP_DIR"

    # 备份所有 workspace 目录
    for d in "$AGENTS_DIR"/workspace-*/; do
      if [ -d "$d" ]; then
        ws_name=$(basename "$d")
        cp -R "$d" "$BACKUP_DIR/$ws_name"
      fi
    done
    ...
  fi
}
```

**命令详解**:

| 命令 | 含义 |
|------|------|
| `$(date +%Y%m%d-%H%M%S)` | 生成时间戳，如 `20260319-143052` |
| `for d in "$AGENTS_DIR"/workspace-*/; do` | 遍历所有匹配的目录 |
| `[ -d "$d" ]` | 检查是否是目录 |
| `basename "$d"` | 取路径的最后一部分（目录名） |
| `cp -R` | 递归复制（复制整个目录） |
| `mkdir -p` | 创建目录（-p 表示如果父目录不存在也创建） |

**备份目录结构**:
```
~/.openclaw/backups/
└── pre-install-20260319-143052/
    ├── workspace-taizi/
    ├── workspace-zhongshu/
    ├── openclaw.json
    └── agents/
```

---

### 方法 3: create_workspaces() —— 创建工作空间

**位置**: 第 92-121 行

**作用**: 为每个 Agent 创建独立的工作目录，并复制人格文件

```bash
create_workspaces() {
  info "创建 Agent Workspace..."

  # 定义 10 个 Agent
  AGENTS=(taizi zhongshu menxia shangshu hubu libu bingbu xingbu gongbu libu_hr zaochao)

  for agent in "${AGENTS[@]}"; do
    ws="$OC_HOME/workspace-$agent"
    mkdir -p "$ws/skills"

    # 复制 SOUL.md（人格文件）
    if [ -f "$REPO_DIR/agents/$agent/SOUL.md" ]; then
      if [ -f "$ws/SOUL.md" ]; then
        # 已存在的 SOUL.md，先备份再覆盖
        cp "$ws/SOUL.md" "$ws/SOUL.md.bak.$(date +%Y%m%d-%H%M%S)"
        warn "已备份旧 SOUL.md → $ws/SOUL.md.bak.*"
      fi
      # 用 sed 替换路径占位符
      sed "s|__REPO_DIR__|$REPO_DIR|g" "$REPO_DIR/agents/$agent/SOUL.md" > "$ws/SOUL.md"
    fi
    log "Workspace 已创建: $ws"
  done

  # 创建通用工作协议文件
  for agent in "${AGENTS[@]}"; do
    cat > "$OC_HOME/workspace-$agent/AGENTS.md" << 'AGENTS_EOF'
# AGENTS.md · 工作协议
1. 接到任务先回复"已接旨"。
2. 输出必须包含：任务ID、结果、证据/文件路径、阻塞项。
...
AGENTS_EOF
  done
}
```

**命令详解**:

| 命令 | 含义 |
|------|------|
| `AGENTS=(taizi zhongshu ...)` | 定义 Bash 数组 |
| `"${AGENTS[@]}"` | 展开数组的所有元素 |
| `mkdir -p "$ws/skills"` | 创建目录，`-p` 自动创建父目录 |
| `sed "s\|__REPO_DIR__\|$REPO_DIR\|g"` | 文本替换，把 `__REPO_DIR__` 替换成实际路径 |
| `cat > file << 'EOF'` | Here Document，把多行文本写入文件 |

**10 个 Agent 说明**:

| ID | 中文名 | 角色 |
|----|--------|------|
| `taizi` | 太子 | 消息分拣 |
| `zhongshu` | 中书省 | 规划中枢 |
| `menxia` | 门下省 | 审核封驳 |
| `shangshu` | 尚书省 | 调度派发 |
| `hubu` | 户部 | 数据资源 |
| `libu` | 礼部 | 文档规范 |
| `bingbu` | 兵部 | 工程实现 |
| `xingbu` | 刑部 | 合规审计 |
| `gongbu` | 工部 | 基础设施 |
| `libu_hr` | 吏部 | 人事管理 |
| `zaochao` | 早朝官 | 情报播报 |

**创建的目录结构**:
```
~/.openclaw/
├── workspace-taizi/
│   ├── skills/         # 技能目录
│   ├── SOUL.md         # 人格定义
│   └── AGENTS.md       # 工作协议
├── workspace-zhongshu/
│   ├── skills/
│   ├── SOUL.md
│   └── AGENTS.md
└── ... (共 10 个 workspace)
```

---

### 方法 4: register_agents() —— 注册 Agent

**位置**: 第 124-186 行

**作用**: 将 10 个 Agent 的信息写入 `openclaw.json` 配置文件

```bash
register_agents() {
  info "注册三省六部 Agents..."

  # 备份配置文件
  cp "$OC_CFG" "$OC_CFG.bak.sansheng-$(date +%Y%m%d-%H%M%S)"

  # 使用 Python 处理 JSON（Bash 处理 JSON 太麻烦）
  python3 << 'PYEOF'
import json, pathlib, sys

cfg_path = pathlib.Path.home() / '.openclaw' / 'openclaw.json'
cfg = json.loads(cfg_path.read_text())

# 定义 Agent 列表和权限矩阵
AGENTS = [
  {"id": "taizi",    "subagents": {"allowAgents": ["zhongshu"]}},
  {"id": "zhongshu", "subagents": {"allowAgents": ["menxia", "shangshu"]}},
  {"id": "menxia",   "subagents": {"allowAgents": ["shangshu", "zhongshu"]}},
  {"id": "shangshu", "subagents": {"allowAgents": ["zhongshu", "menxia", "hubu", "libu", "bingbu", "xingbu", "gongbu", "libu_hr"]}},
  {"id": "hubu",     "subagents": {"allowAgents": ["shangshu"]}},
  ...
]

# 读取已有配置
agents_cfg = cfg.setdefault('agents', {})
agents_list = agents_cfg.get('list', [])
existing_ids = {a['id'] for a in agents_list}

# 添加新 Agent
added = 0
for ag in AGENTS:
    ag_id = ag['id']
    ws = str(pathlib.Path.home() / f'.openclaw/workspace-{ag_id}')
    if ag_id not in existing_ids:
        entry = {'id': ag_id, 'workspace': ws, **{k:v for k,v in ag.items() if k!='id'}}
        agents_list.append(entry)
        added += 1
        print(f'  + added: {ag_id}')
    else:
        print(f'  ~ exists: {ag_id} (skipped)')

agents_cfg['list'] = agents_list
cfg_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2))
PYEOF

  log "Agents 注册完成"
}
```

**命令详解**:

| 命令 | 含义 |
|------|------|
| `python3 << 'PYEOF'` | Here Document，把 PYEOF 之间的内容传给 Python |
| `json.loads()` | 解析 JSON 字符串 |
| `cfg.setdefault('agents', {})` | 如果没有 `agents` 键，就创建一个空字典 |
| `pathlib.Path.home()` | 获取用户主目录 |

**生成的 openclaw.json 片段**:
```json
{
  "agents": {
    "list": [
      {
        "id": "taizi",
        "workspace": "/Users/xxx/.openclaw/workspace-taizi",
        "subagents": {
          "allowAgents": ["zhongshu"]
        }
      },
      {
        "id": "zhongshu",
        "workspace": "/Users/xxx/.openclaw/workspace-zhongshu",
        "subagents": {
          "allowAgents": ["menxia", "shangshu"]
        }
      },
      ...
    ]
  }
}
```

---

### 方法 5: link_resources() —— 符号链接

**位置**: 第 239-290 行

**作用**: 让所有 Agent 的 `data/` 和 `scripts/` 指向项目目录，确保数据一致

```bash
link_resources() {
  info "创建 data/scripts 软链接以确保 Agent 数据一致..."

  AGENTS=(taizi zhongshu menxia shangshu hubu libu bingbu xingbu gongbu libu_hr zaochao)
  LINKED=0

  for agent in "${AGENTS[@]}"; do
    ws="$OC_HOME/workspace-$agent"
    mkdir -p "$ws"

    # 软链接 data 目录
    ws_data="$ws/data"
    if [ -L "$ws_data" ]; then
      : # 已是软链接，跳过
    elif [ -d "$ws_data" ]; then
      # 已有 data 目录（非符号链接），备份后替换
      mv "$ws_data" "${ws_data}.bak.$(date +%Y%m%d-%H%M%S)"
      ln -s "$REPO_DIR/data" "$ws_data"
      LINKED=$((LINKED + 1))
    else
      ln -s "$REPO_DIR/data" "$ws_data"
      LINKED=$((LINKED + 1))
    fi

    # 软链接 scripts 目录（同理）
    ...
  done

  log "已创建 $LINKED 个软链接"
}
```

**命令详解**:

| 命令 | 含义 |
|------|------|
| `ln -s source target` | 创建符号链接（软链接） |
| `[ -L "$ws_data" ]` | 检查是否是符号链接 |
| `[ -d "$ws_data" ]` | 检查是否是目录 |
| `LINKED=$((LINKED + 1))` | Bash 算术运算，自增 |

**为什么需要符号链接？**

```
❌ 没有符号链接时：
~/.openclaw/workspace-taizi/data/tasks_source.json      ← 太子读写这个
~/.openclaw/workspace-zhongshu/data/tasks_source.json   ← 中书省读写这个
# 两个文件不同步！数据不一致！

✅ 有符号链接后：
~/.openclaw/workspace-taizi/data/    ──┐
~/.openclaw/workspace-zhongshu/data/ ──┼──► /path/to/edict/data/tasks_source.json
~/.openclaw/workspace-hubu/data/     ──┘
# 所有 Agent 读写同一个文件！
```

---

### 方法 6: sync_auth() —— 同步 API Key

**位置**: 第 304-342 行

**作用**: 把一个 Agent 的 API Key 复制到所有 Agent

```bash
sync_auth() {
  info "同步 API Key 到所有 Agent..."

  # 找到 main agent 的 auth-profiles.json
  MAIN_AUTH="$OC_HOME/agents/main/agent/auth-profiles.json"
  if [ ! -f "$MAIN_AUTH" ]; then
    MAIN_AUTH=$(find "$OC_HOME/agents" -name auth-profiles.json -maxdepth 3 2>/dev/null | head -1)
  fi

  if [ -z "$MAIN_AUTH" ] || [ ! -f "$MAIN_AUTH" ]; then
    warn "未找到已有的 auth-profiles.json"
    return
  fi

  # 复制到所有 Agent
  AGENTS=(taizi zhongshu ...)
  SYNCED=0
  for agent in "${AGENTS[@]}"; do
    AGENT_DIR="$OC_HOME/agents/$agent/agent"
    mkdir -p "$AGENT_DIR"
    cp "$MAIN_AUTH" "$AGENT_DIR/auth-profiles.json"
    SYNCED=$((SYNCED + 1))
  done

  log "API Key 已同步到 $SYNCED 个 Agent"
}
```

**命令详解**:

| 命令 | 含义 |
|------|------|
| `find ... -name auth-profiles.json` | 查找文件 |
| `-maxdepth 3` | 最多搜索 3 层子目录 |
| `2>/dev/null` | 把错误信息丢掉 |
| `head -1` | 取第一行结果 |
| `[ -z "$MAIN_AUTH" ]` | 检查变量是否为空字符串 |

---

## 四、安装流程图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           install.sh 执行流程                                │
└─────────────────────────────────────────────────────────────────────────────┘

                    ┌─────────────┐
                    │   开始      │
                    └──────┬──────┘
                           │
                           ▼
                ┌──────────────────────┐
                │  banner() 显示标题   │
                └──────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────────┐
              │  check_deps() 检查依赖     │
              │  - openclaw CLI           │
              │  - python3                │
              │  - openclaw.json          │
              └────────────┬───────────────┘
                           │
                           ▼
              ┌────────────────────────────┐
              │  backup_existing() 备份    │
              │  - 检测已有 workspace      │
              │  - 备份到 backups/         │
              └────────────┬───────────────┘
                           │
                           ▼
        ┌──────────────────────────────────────────────┐
        │  create_workspaces() 创建工作空间            │
        │  - 创建 10 个 workspace-{agent} 目录         │
        │  - 复制 SOUL.md（人格文件）                   │
        │  - 创建 AGENTS.md（工作协议）                 │
        └────────────────────┬─────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────────────────┐
        │  register_agents() 注册 Agent                │
        │  - 写入 openclaw.json                        │
        │  - 配置权限矩阵 (allowAgents)                │
        └────────────────────┬─────────────────────────┘
                           │
                           ▼
              ┌────────────────────────────┐
              │  init_data() 初始化数据    │
              │  - data/tasks_source.json  │
              │  - data/live_status.json   │
              │  - data/agent_config.json  │
              └────────────┬───────────────┘
                           │
                           ▼
        ┌──────────────────────────────────────────────┐
        │  link_resources() 创建符号链接               │
        │  - workspace-*/data → 项目 data/            │
        │  - workspace-*/scripts → 项目 scripts/      │
        └────────────────────┬─────────────────────────┘
                           │
                           ▼
              ┌────────────────────────────┐
              │  setup_visibility() 通信   │
              │  设置 Agent 间消息可见性   │
              └────────────┬───────────────┘
                           │
                           ▼
              ┌────────────────────────────┐
              │  sync_auth() 同步 API Key  │
              │  复制到所有 Agent          │
              └────────────┬───────────────┘
                           │
                           ▼
              ┌────────────────────────────┐
              │  build_frontend() 构建前端 │
              │  npm install && npm build  │
              └────────────┬───────────────┘
                           │
                           ▼
              ┌────────────────────────────┐
              │  first_sync() 首次同步     │
              │  执行数据同步脚本          │
              └────────────┬───────────────┘
                           │
                           ▼
              ┌────────────────────────────┐
              │  restart_gateway() 重启    │
              │  使配置生效                │
              └────────────┬───────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   安装完成   │
                    └─────────────┘
```

---

## 五、核心要点总结

| 概念 | 说明 |
|------|------|
| **Workspace** | 每个 Agent 独立的工作目录 `~/.openclaw/workspace-{id}` |
| **SOUL.md** | Agent 人格定义文件，定义角色、职责、工作流程 |
| **AGENTS.md** | 工作协议，定义 Agent 输出规范 |
| **权限矩阵** | `subagents.allowAgents` 控制 Agent 间通信权限 |
| **符号链接** | 所有 Agent 共享同一份 data/ 和 scripts/ |
| **openclaw.json** | OpenClaw 主配置，存储 Agent 注册信息 |

---

## 六、关键 Bash 命令速查表

| 命令 | 含义 |
|------|------|
| `set -e` | 任何命令失败时立即退出脚本 |
| `command -v xxx` | 检查 xxx 命令是否存在 |
| `&>/dev/null` | 丢弃标准输出和错误 |
| `[ -f file ]` | 检查文件是否存在 |
| `[ -d dir ]` | 检查��录是否存在 |
| `[ -L link ]` | 检查是否是符号链接 |
| `[ -z "$var" ]` | 检查变量是否为空 |
| `mkdir -p` | 创建目录（包括父目录） |
| `cp -R` | 递归复制 |
| `ln -s src dst` | 创建符号链接 |
| `basename path` | 取路径的最后一部分 |
| `dirname path` | 取路径的目录部分 |
| `sed "s\|old\|new\|g"` | 全局替换文本 |
| `cat > file << 'EOF'` | Here Document 写入文件 |
