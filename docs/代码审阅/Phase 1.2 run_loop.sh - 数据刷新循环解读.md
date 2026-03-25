# Phase 1.2: run_loop.sh 详细解读

---

## 一、整体结构

```
run_loop.sh (88 行)
│
├── 第 1-6 行:      头部注释与用法说明
├── 第 7-13 行:     全局变量设置
│
├── 第 15-24 行:    单实例保护 (PID 锁文件)
├── 第 26-32 行:    cleanup() 优雅退出函数
├── 第 34-40 行:    rotate_log() 日志轮转函数
├── 第 42-44 行:    巡检相关变量
├── 第 46-53 行:    启动信息输出
├── 第 55-68 行:    safe_run() 安全执行函数（带超时）
│
└── 第 70-87 行:    主循环 (无限循环)
```

**一句话概括**: 这是一个后台守护进程脚本，每隔 N 秒执行数据同步，确保前端展示的数据是最新的。

---

## 二、全局变量详解 (第 7-13 行)

```bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL="${1:-15}"
LOG="/tmp/sansheng_liubu_refresh.log"
PIDFILE="/tmp/sansheng_liubu_refresh.pid"
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB
```

| 变量 | 值示例 | 含义 |
|------|--------|------|
| `SCRIPT_DIR` | `/Users/xxx/edict/scripts` | 脚本所在目录 |
| `INTERVAL` | `15` | 刷新间隔（秒），可通过参数传入 |
| `LOG` | `/tmp/sansheng_liubu_refresh.log` | 日志文件路径 |
| `PIDFILE` | `/tmp/sansheng_liubu_refresh.pid` | PID 锁文件 |
| `MAX_LOG_SIZE` | `10485760` | 日志最大 10MB |

### set -euo pipefail 详解

```bash
set -euo pipefail
```

| 选项 | 含义 |
|------|------|
| `-e` | **Exit on error** - 任何命令失败时立即退出 |
| `-u` | **Unset variables** - 使用未定义变量时报错（而不是当成空字符串） |
| `-o pipefail` | **Pipe fail** - 管道中任何命令失败，整个管道返回失败 |

**管道示例**:
```bash
# 没有 pipefail 时
false | true | echo "done"
# 返回码是 0（最后一个命令成功）
# 但实际上第一个命令失败了！

# 有 pipefail 时
set -o pipefail
false | true | echo "done"
# 返回码非 0，因为管道中有失败
```

### 参数默认值语法

```bash
INTERVAL="${1:-15}"
```

| 语法 | 含义 |
|------|------|
| `$1` | 第一个命令行参数 |
| `:-15` | 如果参数为空或未提供，使用默认值 `15` |

**示例**:
```bash
./run_loop.sh        # INTERVAL=15
./run_loop.sh 30     # INTERVAL=30
./run_loop.sh 30 60  # INTERVAL=30, SCAN_INTERVAL=60
```

---

## 三、单实例保护 (第 15-24 行)

```bash
if [[ -f "$PIDFILE" ]]; then
  OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "❌ 已有实例运行中 (PID=$OLD_PID)，退出"
    exit 1
  fi
  rm -f "$PIDFILE"
fi
echo $$ > "$PIDFILE"
```

**作用**: 防止同时运行多个 `run_loop.sh` 实例，避免数据冲突

### 命令详解

| 命令 | 含义 |
|------|------|
| `[[ -f "$PIDFILE" ]]` | 检查 PID 文件是否存在 |
| `cat "$PIDFILE" 2>/dev/null` | 读取文件内容，错误丢弃 |
| `kill -0 "$OLD_PID"` | **不真正发送信号**，只检查进程是否存在 |
| `$$` | 当前脚本的进程 ID (PID) |

### kill -0 原理

```bash
kill -0 12345  # 检查 PID 12345 是否存在
# 返回 0 → 进程存在
# 返回非 0 → 进程不存在
```

> `kill -0` 是一个特殊信号，它不实际发送任何信号给进程，只是检查进程是否存在

### 执行流程图

```
┌──────────────────────────┐
│ PID 文件存在？            │
└────────────┬─────────────┘
             │
       ┌─────┴─────┐
       ▼           ▼
      是           否
       │           │
       ▼           │
┌──────────────────┴───┐
│ kill -0 检查旧进程    │
│ 是否仍在运行？        │
└──────────┬───────────┘
           │
     ┌─────┴─────┐
     ▼           ▼
   是            否
     │           │
     ▼           ▼
┌──────────┐  ┌─────────────┐
│ 报错退出  │  │ 删除旧 PID   │
│ exit 1   │  │ 文件         │
└──────────┘  └──────┬──────┘
                     │
                     ▼
              ┌─────────────┐
              │ 写入当前 PID │
              │ 到 PID 文件  │
              └─────────────┘
```

---

## 四、优雅退出 cleanup() (第 26-32 行)

```bash
cleanup() {
  echo "$(date '+%H:%M:%S') [loop] 收到退出信号，清理中..." >> "$LOG"
  rm -f "$PIDFILE"
  exit 0
}
trap cleanup SIGINT SIGTERM EXIT
```

**作用**: 当脚本被终止时（Ctrl+C、kill 命令等），自动清理 PID 文件

### trap 命令详解

```bash
trap cleanup SIGINT SIGTERM EXIT
```

| 信号 | 触发条件 |
|------|----------|
| `SIGINT` | 用户按 **Ctrl+C** |
| `SIGTERM` | 收到 `kill` 命令（默认信号） |
| `EXIT` | 脚本正常退出（无论什么原因） |

**执行流程**:
```
用户按 Ctrl+C
      │
      ▼
┌─────────────────────┐
│ 系统发送 SIGINT 信号 │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ trap 捕获信号        │
│ 调用 cleanup()      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ cleanup() 执行：     │
│ 1. 写日志           │
│ 2. 删除 PID 文件    │
│ 3. exit 0          │
└─────────────────────┘
```

---

## 五、日志轮转 rotate_log() (第 34-40 行)

```bash
rotate_log() {
  if [[ -f "$LOG" ]] && (( $(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null || echo 0) > MAX_LOG_SIZE )); then
    mv "$LOG" "${LOG}.1"
    echo "$(date '+%H:%M:%S') [loop] 日志已轮转" > "$LOG"
  fi
}
```

**作用**: 当日志文件超过 10MB 时，自动归档并创建新日志

### stat 命令详解

```bash
stat -f%z "$LOG"   # macOS 语法，获取文件大小（字节）
stat -c%s "$LOG"   # Linux 语法，获取文件大小（字节）
```

| 平台 | 命令 | 说明 |
|------|------|------|
| macOS | `stat -f%z file` | `-f` 格式，`%z` = 文件大小 |
| Linux | `stat -c%s file` | `-c` 格式，`%s` = 文件大小 |

### 为什么要写两遍 stat？

```bash
stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null || echo 0
```

- 先尝试 macOS 语法
- 如果失败（返回非 0），尝试 Linux 语法
- 如果还失败，返回 0

> 这样脚本在 macOS 和 Linux 上都能运行

### 日志轮转过程

```
轮转前:
/tmp/sansheng_liubu_refresh.log  (12MB)

轮转后:
/tmp/sansheng_liubu_refresh.log.1  (12MB, 旧日志)
/tmp/sansheng_liubu_refresh.log    (新日志, 只有 1 行)
```

---

## 六、安全执行 safe_run() (第 55-68 行)

```bash
safe_run() {
  local script="$1"
  if command -v timeout &>/dev/null; then
    timeout "$SCRIPT_TIMEOUT" python3 "$script" >> "$LOG" 2>&1 || {
      local rc=$?
      if [[ $rc -eq 124 ]]; then
        echo "$(date '+%H:%M:%S') [loop] ⚠️ 脚本超时(${SCRIPT_TIMEOUT}s): $script" >> "$LOG"
      fi
    }
  else
    python3 "$script" >> "$LOG" 2>&1 || true
  fi
}
```

**作用**: 执行 Python 脚本，带超时保护，防止某个脚本卡死导致整个循环停止

### timeout 命令详解

```bash
timeout 30 python3 slow_script.py
```

| 行为 | 说明 |
|------|------|
| 正常完成 | 返回脚本自己的退出码 |
| 超过 30 秒 | 强制终止，返回 **124** |

### 返回码含义

| 返回码 | 含义 |
|--------|------|
| `0` | 成功 |
| `1-125` | 命令自己的错误码 |
| `124` | **超时**（timeout 特有） |
| `126` | 命令不可执行 |
| `127` | 命令未找到 |
| `128+N` | 被信号 N 终止 |

### || { ... } 语法

```bash
timeout 30 python3 "$script" || {
  local rc=$?
  if [[ $rc -eq 124 ]]; then
    echo "超时了"
  fi
}
```

| 语法 | 含义 |
|------|------|
| `||` | 前面的命令失败时执行后面 |
| `$?` | 上一个命令的退出码 |
| `local rc=$?` | 保存退出码到局部变量 |

### 为什么最后有 || true？

```bash
python3 "$script" >> "$LOG" 2>&1 || true
```

- 如果 `python3` 失败，`|| true` 让整体返回 0
- 这样脚本不会因为 `set -e` 而意外退出

---

## 七、主循环详解 (第 70-87 行)

```bash
while true; do
  rotate_log
  safe_run "$SCRIPT_DIR/sync_from_openclaw_runtime.py"
  safe_run "$SCRIPT_DIR/sync_agent_config.py"
  safe_run "$SCRIPT_DIR/apply_model_changes.py"
  safe_run "$SCRIPT_DIR/sync_officials_stats.py"
  safe_run "$SCRIPT_DIR/refresh_live_data.py"

  # 定期巡检：检测卡住的任务并自动重试
  SCAN_COUNTER=$((SCAN_COUNTER + INTERVAL))
  if (( SCAN_COUNTER >= SCAN_INTERVAL )); then
    SCAN_COUNTER=0
    curl -s -X POST http://127.0.0.1:7891/api/scheduler-scan \
      -H 'Content-Type: application/json' -d '{"thresholdSec":180}' >> "$LOG" 2>&1 || true
  fi

  sleep "$INTERVAL"
done
```

### 5 个同步脚本的作用

| 脚本 | 作用 |
|------|------|
| `sync_from_openclaw_runtime.py` | 从 OpenClaw 运行时同步 Agent 状态 |
| `sync_agent_config.py` | 同步 Agent 配置（模型、参数等） |
| `apply_model_changes.py` | 应用模型变更请求 |
| `sync_officials_stats.py` | 同步官员（Agent）统计数据 |
| `refresh_live_data.py` | 刷新实时数据（任务、状态等） |

### 巡检机制

```bash
SCAN_COUNTER=$((SCAN_COUNTER + INTERVAL))
if (( SCAN_COUNTER >= SCAN_INTERVAL )); then
  SCAN_COUNTER=0
  curl -s -X POST http://127.0.0.1:7891/api/scheduler-scan \
    -H 'Content-Type: application/json' -d '{"thresholdSec":180}' >> "$LOG" 2>&1 || true
fi
```

**逻辑**:
1. 每次循环，`SCAN_COUNTER` 增加 `INTERVAL`（默认 15 秒）
2. 当累计达到 `SCAN_INTERVAL`（默认 120 秒）时：
   - 重置计数器
   - 调用 `/api/scheduler-scan` 接口
   - 检测卡住超过 180 秒的任务并自动重试

### curl 命令详解

```bash
curl -s -X POST http://127.0.0.1:7891/api/scheduler-scan \
  -H 'Content-Type: application/json' \
  -d '{"thresholdSec":180}'
```

| 选项 | 含义 |
|------|------|
| `-s` | 静默模式，不显示进度条 |
| `-X POST` | 使用 POST 方法 |
| `-H '...'` | 添加请求头 |
| `-d '...'` | 请求体数据 |

---

## 八、完整执行流程图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        run_loop.sh 执行流程                                  │
└─────────────────────────────────────────────────────────────────────────────┘

                    ┌─────────────────┐
                    │     启动        │
                    └────────┬────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │  单实例保护检查               │
              │  - 检查 PID 文件             │
              │  - 如果有旧进程，退出        │
              │  - 写入当前 PID              │
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │  注册退出信号处理            │
              │  trap cleanup SIGINT/TERM   │
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │  输出启动信息                │
              │  - 间隔、日志路径等          │
              └──────────────┬───────────────┘
                             │
                             ▼
        ┌─────────────────────────────────────────────┐
        │               主循环 (while true)            │
        │                                             │
        │   ┌─────────────────────────────────────┐   │
        │   │ 1. rotate_log() 日志轮转检查        │   │
        │   └─────────────────┬───────────────────┘   │
        │                     │                       │
        │                     ▼                       │
        │   ┌─────────────────────────────────────┐   │
        │   │ 2. safe_run sync_from_openclaw     │   │
        │   │    (同步 OpenClaw 运行时状态)       │   │
        │   └─────────────────┬───────────────────┘   │
        │                     │                       │
        │                     ▼                       │
        │   ┌─────────────────────────────────────┐   │
        │   │ 3. safe_run sync_agent_config      │   │
        │   │    (同步 Agent 配置)                │   │
        │   └─────────────────┬───────────────────┘   │
        │                     │                       │
        │                     ▼                       │
        │   ┌─────────────────────────────────────┐   │
        │   │ 4. safe_run apply_model_changes    │   │
        │   │    (应用模型变更)                   │   │
        │   └─────────────────┬───────────────────┘   │
        │                     │                       │
        │                     ▼                       │
        │   ┌─────────────────────────────────────┐   │
        │   │ 5. safe_run sync_officials_stats   │   │
        │   │    (同步官员统计)                   │   │
        │   └──────���──────────┬───────────────────┘   │
        │                     │                       │
        │                     ▼                       │
        │   ┌─────────────────────────────────────┐   │
        │   │ 6. safe_run refresh_live_data      │   │
        │   │    (刷新实时数据)                   │   │
        │   └─────────────────┬───────────────────┘   │
        │                     │                       │
        │                     ▼                       │
        │   ┌─────────────────────────────────────┐   │
        │   │ 7. 巡检计数器 += INTERVAL          │   │
        │   │    如果 >= SCAN_INTERVAL:          │   │
        │   │    - 重置计数器                     │   │
        │   │    - 调用 /api/scheduler-scan      │   │
        │   └─────────────────┬───────────────────┘   │
        │                     │                       │
        │                     ▼                       │
        │   ┌─────────────────────────────────────┐   │
        │   │ 8. sleep $INTERVAL (默认 15 秒)    │   │
        │   └─────────────────┬───────────────────┘   │
        │                     │                       │
        │                     └──────► 回到循环顶部   │
        │                                             │
        └─────────────────────────────────────────────┘

                    ┌─────────────────┐
                    │ 收到退出信号    │
                    │ (Ctrl+C/kill)  │
                    └────────┬────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │  cleanup() 执行              │
              │  1. 写退出日志               │
              │  2. 删除 PID 文件            │
              │  3. exit 0                  │
              └──────────────────────────────┘
```

---

## 九、核心要点总结

| 概念 | 说明 |
|------|------|
| **守护进程** | 后台持续运行的进程，定期执行任务 |
| **单实例保护** | 通过 PID 文件防止重复运行 |
| **优雅退出** | 收到终止信号时自动清理资源 |
| **日志轮转** | 防止日志文件无限增长 |
| **超时保护** | 使用 `timeout` 命令防止子脚本卡死 |
| **巡检机制** | 定期检测卡住的任务并自动恢复 |

---

## 十、关键命令速查表

| 命令 | 含义 |
|------|------|
| `set -euo pipefail` | 严格模式：出错退出、未定义变量报错、管道失败传递 |
| `${1:-15}` | 参数默认值：如果 $1 为空则使用 15 |
| `kill -0 $PID` | 检查进程是否存在（不发送信号） |
| `trap func SIGINT` | 捕获信号，执行清理函数 |
| `stat -f%z file` | macOS 获取文件大小 |
| `stat -c%s file` | Linux 获取文件大小 |
| `timeout 30 cmd` | 30 秒超时执行命令 |
| `$?` | 上一个命令的退出码 |
| `$((a + b))` | Bash 算术运算 |
| `(( x >= y ))` | Bash 算术比较 |
| `curl -s -X POST` | 静默发送 POST 请求 |

---

## 十一、使用方式

```bash
# 默认配置（15秒刷新，120秒巡检）
./run_loop.sh

# 自定义刷新间隔（30秒刷新）
./run_loop.sh 30

# 自定义刷新和巡检间隔（30秒刷新，60秒巡检）
./run_loop.sh 30 60

# 后台运行
nohup ./run_loop.sh &

# 停止运行
kill $(cat /tmp/sansheng_liubu_refresh.pid)
# 或直接按 Ctrl+C（如果在前台运行）
```
