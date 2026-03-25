# 三省六部代码解读计划

> **For Claude:** 这是一个代码解读计划，按模块顺序阅读代码，理解项目架构。

**Goal:** 从入口文件开始，系统理解三省六部多 Agent 协作框架的完整实现

**Architecture:** 前后端分离架构 - Python stdlib 后端 (server.py) + React 18 前端，通过 OpenClaw Runtime 运行 12 个专业 Agent

**Tech Stack:** Python 3.9+ / React 18 + TypeScript / Zustand / Vite / TailwindCSS

---

## 阅读路线图

```
Phase 1: 安装与启动
    └── install.sh → run_loop.sh → server.py
           ↓
Phase 2: 数据层
    └── file_lock.py → utils.py → kanban_update.py → refresh_live_data.py
           ↓
Phase 3: 后端 API
    └── server.py (路由) → court_discuss.py (朝堂议政)
           ↓
Phase 4: 前端
    └── api.ts → store.ts → App.tsx → 组件
           ↓
Phase 5: Agent 系统
    └── agents/*/SOUL.md → sync_from_openclaw_runtime.py
           ↓
Phase 6: 测试与验证
    └── test_*.py
```

---

## Phase 1: 安装与启动

### Task 1.1: 安装脚本解读

**Files:**
- Read: `install.sh` (完整)

**阅读重点:**

1. **依赖检查** (L28-48)
   - 检查 `openclaw` CLI
   - 检查 Python3
   - 检查 `openclaw.json` 配置文件

2. **备份机制** (L51-89)
   - 自动备份已有 workspace
   - 备份 openclaw.json 和 agents 目录

3. **Workspace 创建** (L92-120)
   - 创建 10 个 Agent workspace
   - 复制 SOUL.md 人格文件
   - 设置符号链接

4. **符号链接统一数据** (L150-180)
   - 各 workspace 的 data/ → 项目 data/
   - 各 workspace 的 scripts/ → 项目 scripts/

**关键命令:**
```bash
# 查看完整安装脚本
cat install.sh | head -200
```

---

### Task 1.2: 数据刷新循环解读

**Files:**
- Read: `scripts/run_loop.sh` (完整)

**阅读重点:**

1. **单实例保护** (L15-24)
   - PID 文件检测
   - 防止重复运行

2. **优雅退出** (L27-32)
   - 信号捕获 (SIGINT/SIGTERM)
   - 清理 PID 文件

3. **核心循环** (L70-87)
   ```
   sync_from_openclaw_runtime.py  # 同步任务数据
   sync_agent_config.py           # 同步 Agent 配置
   apply_model_changes.py         # 应用模型变更
   sync_officials_stats.py        # 同步官员统计
   refresh_live_data.py           # 汇总刷新
   ```

4. **巡检机制** (L78-84)
   - 每 120s 调用 `/api/scheduler-scan`
   - 自动重试卡住的任务

---

### Task 1.3: 后端服务入口

**Files:**
- Read: `dashboard/server.py` (L1-150)

**阅读重点:**

1. **导入与配置** (L1-46)
   ```python
   from file_lock import atomic_json_read, atomic_json_write
   from utils import validate_url, read_json, now_iso
   from court_discuss import create_session, advance_discussion
   ```

2. **路径定义**
   ```python
   BASE = pathlib.Path(__file__).parent
   DIST = BASE / 'dist'      # React 构建产物
   DATA = BASE.parent / "data"
   SCRIPTS = BASE.parent / 'scripts'
   ```

3. **安全措施** (L35-41)
   - `MAX_REQUEST_BODY = 1MB`
   - `_SAFE_NAME_RE` 防止路径遍历
   - CORS 白名单

---

## Phase 2: 数据层

### Task 2.1: 文件锁工具

**Files:**
- Read: `scripts/file_lock.py` (完整, ~100行)

**核心函数:**

```python
# 原子读取 JSON
def atomic_json_read(path: Path, default=None) -> Any

# 原子写入 JSON
def atomic_json_write(path: Path, data: Any) -> None

# 原子更新 JSON (读取-修改-写入)
def atomic_json_update(path: Path, updater: Callable) -> Any
```

**阅读重点:**
- 使用 `fcntl.flock()` 实现文件锁
- 写入临时文件后 `os.replace()` 原子重命名
- 防止多 Agent 并发写入损坏数据

---

### Task 2.2: 通用工具函数

**Files:**
- Read: `scripts/utils.py` (完整)

**核心函数:**

```python
def validate_url(url: str) -> str      # SSRF 防护
def read_json(path: Path) -> Any       # 安全读取
def now_iso() -> str                   # ISO 时间戳
```

**阅读重点:**
- `validate_url()` 禁止内网 IP (127.0.0.1, 10.x, 172.16-31, 192.168.x)

---

### Task 2.3: 看板 CLI 工具

**Files:**
- Read: `scripts/kanban_update.py` (L1-200)

**命令清单:**

| 命令 | 用途 |
|------|------|
| `create` | 新建任务 (收旨时) |
| `state` | 更新状态 |
| `flow` | 添加流转记录 |
| `done` | 完成任务 |
| `todo` | 添加/更新子任务 |
| `progress` | 实时进展汇报 |

**状态机定义** (L180-220):
```python
_VALID_TRANSITIONS = {
    'Inbox': ['Taizi'],
    'Taizi': ['Zhongshu', 'Done'],
    'Zhongshu': ['Menxia'],
    'Menxia': ['Assigned', 'Zhongshu'],  # 封驳回中书
    'Assigned': ['Doing', 'Next'],
    'Doing': ['Review', 'Blocked'],
    # ...
}
```

---

### Task 2.4: 数据刷新脚本

**Files:**
- Read: `scripts/refresh_live_data.py` (完整)

**数据流:**
```
tasks_source.json  ──┐
agent_config.json   ──┼──► live_status.json
officials_stats.json ──┘
```

**输出结构:**
```json
{
  "tasks": [...],
  "syncStatus": { "ok": true, "checkedAt": "..." }
}
```

---

## Phase 3: 后端 API

### Task 3.1: API 路由总览

**Files:**
- Read: `dashboard/server.py` (L400-600)

**API 端点分类:**

| 类别 | 端点 | 功能 |
|------|------|------|
| **数据** | `/api/live-status` | 实时状态 |
| | `/api/tasks` | 任务列表 |
| | `/api/agent-config` | Agent 配置 |
| **操作** | `/api/task-action` | 叫停/取消/恢复 |
| | `/api/set-model` | 切换模型 |
| | `/api/review-action` | 准奏/封驳 |
| **调度** | `/api/scheduler-scan` | 巡检卡住任务 |
| | `/api/scheduler-retry` | 重试 |
| | `/api/scheduler-escalate` | 升级 |
| **Skills** | `/api/add-remote-skill` | 添加远程 Skill |
| | `/api/remote-skills-list` | 列出远程 Skills |

---

### Task 3.2: 任务调度器

**Files:**
- Read: `dashboard/server.py` (L200-400)

**核心函数:**

```python
def dispatch_for_state(task_id, task, state, trigger='auto')
    """根据状态派发任务到对应 Agent"""

def _scheduler_scan(task, stalled_sec)
    """检测卡住的任务，自动重试/升级/回滚"""
```

**调度策略:**
1. 重试 (retryCount < 3)
2. 升级 (通知上级 Agent)
3. 回滚 (恢复到上一状态)

---

### Task 3.3: 朝堂议政引擎

**Files:**
- Read: `dashboard/court_discuss.py` (完整)

**核心流程:**

```
create_session(topic, officials)
      ↓
advance_discussion(session_id, user_message?, decree?)
      ↓  (多轮)
conclude_session(session_id)
```

**关键数据结构:**
```python
OFFICIAL_PROFILES = {
    'zhongshu': {'name': '中书令', 'style': '稳重缜密'},
    'menxia': {'name': '侍中', 'style': '严谨挑剔'},
    'hubu': {'name': '户部尚书', 'style': '精打细算'},
    # ...
}
```

---

## Phase 4: 前端

### Task 4.1: API 客户端

**Files:**
- Read: `edict/frontend/src/api.ts` (完整)

**阅读重点:**

1. **通用请求函数**
   ```typescript
   async function fetchJ<T>(url: string): Promise<T>
   async function postJ<T>(url: string, data: unknown): Promise<T>
   ```

2. **类型定义** (L112-433)
   - `Task` - 任务结构
   - `LiveStatus` - 实时状态
   - `AgentConfig` - Agent 配置
   - `CourtDiscussResult` - 朝堂议政结果

---

### Task 4.2: 状态管理

**Files:**
- Read: `edict/frontend/src/store.ts` (L1-200)

**阅读重点:**

1. **Pipeline 定义** (L21-35)
   ```typescript
   export const PIPE = [
     { key: 'Inbox', dept: '皇上', icon: '👑' },
     { key: 'Taizi', dept: '太子', icon: '🤴' },
     { key: 'Zhongshu', dept: '中书省', icon: '📜' },
     // ...
   ]
   ```

2. **Tab 定义** (L88-99)
   - 10 个功能面板

3. **轮询机制** (L400-430)
   ```typescript
   setInterval(() => {
     if (countdown <= 0) {
       loadAll();  // 刷新所有数据
       setCountdown(5);
     }
   }, 1000);
   ```

---

### Task 4.3: 根组件

**Files:**
- Read: `edict/frontend/src/App.tsx` (完整)

**组件结构:**
```
App
├── Header (同步状态 + 刷新按钮)
├── Tabs (10 个面板切换)
└── Panels (条件渲染)
    ├── EdictBoard
    ├── CourtDiscussion
    ├── MonitorPanel
    └── ...
```

---

### Task 4.4: 核心组件

**Files:**
- Read: `edict/frontend/src/components/EdictBoard.tsx` (看板)
- Read: `edict/frontend/src/components/CourtDiscussion.tsx` (朝堂议政)
- Read: `edict/frontend/src/components/TaskModal.tsx` (任务详情)

**阅读重点:**
- EdictBoard: Kanban 列表渲染
- CourtDiscussion: LLM 驱动的多角色讨论
- TaskModal: 任务详情弹窗 + 操作按钮

---

## Phase 5: Agent 系统

### Task 5.1: Agent 人格定义

**Files:**
- Read: `agents/taizi/SOUL.md` (太子 - 消息分拣)
- Read: `agents/zhongshu/SOUL.md` (中书省 - 规划)
- Read: `agents/menxia/SOUL.md` (门下省 - 审核)
- Read: `agents/shangshu/SOUL.md` (尚书省 - 调度)

**SOUL.md 结构:**
```markdown
# 角色设定
- 名称、职位、性格

# 职责边界
- 负责什么、不负责什么

# 工作流程
- 接收任务 → 处理 → 输出

# 输出规范
- 格式要求、数据清洗
```

---

### Task 5.2: Agent 数据同步

**Files:**
- Read: `scripts/sync_from_openclaw_runtime.py` (完整)

**同步流程:**
```
~/.openclaw/workspace-{agent}/
├── sessions/*.jsonl     ──► 解析 Agent 活动
└── SOUL.md              ──► 读取人格

        ↓

data/tasks_source.json   ──► 更新任务状态
```

---

### Task 5.3: 官员统计同步

**Files:**
- Read: `scripts/sync_officials_stats.py` (完整)

**统计维度:**
- Token 消耗 (in/out/cache)
- 费用 (CNY/USD)
- 任务完成数
- 活跃度评分

---

## Phase 6: 测试

### Task 6.1: 看板测试

**Files:**
- Read: `tests/test_kanban.py` (完整)

**测试用例:**
- `test_create` - 创建任务
- `test_state` - 状态更新
- `test_flow` - 流转记录
- `test_done` - 完成任务
- `test_progress_log_capped` - 日志截断

---

### Task 6.2: 端到端测试

**Files:**
- Read: `tests/test_e2e_kanban.py` (完整)

**测试流程:**
1. 启动服务器
2. 创建任务
3. 执行状态流转
4. 验证 API 响应
5. 清理

---

## 附录: 快速定位

| 需求 | 文件 |
|------|------|
| 了解安装流程 | `install.sh` |
| 了解数据刷新 | `scripts/run_loop.sh` |
| 了解 API 端点 | `dashboard/server.py` L400-600 |
| 了解状态机 | `scripts/kanban_update.py` L180-220 |
| 了解任务派发 | `dashboard/server.py` L200-400 |
| 了解朝堂议政 | `dashboard/court_discuss.py` |
| 了解前端状态 | `edict/frontend/src/store.ts` |
| 了解 Agent 人格 | `agents/*/SOUL.md` |
| 了解文件锁 | `scripts/file_lock.py` |

---

## 阅读建议

1. **先宏观后微观**: 先理解整体数据流，再深入具体实现
2. **跟踪数据**: 从 `data/*.json` 反推代码逻辑
3. **运行调试**: `python3 dashboard/server.py` 启动后用浏览器 DevTools 观察 API 调用
4. **阅读日志**: `/tmp/sansheng_liubu_refresh.log` 了解后台同步行为

---

**阅读顺序总结:**

```
1. install.sh          # 了解项目如何初始化
2. run_loop.sh         # 了解后台如何运行
3. file_lock.py        # 理解并发安全基础
4. kanban_update.py    # 理解状态机核心
5. server.py           # 理解 API 层
6. court_discuss.py    # 理解朝堂议政
7. api.ts + store.ts   # 理解前端状态
8. agents/*/SOUL.md    # 理解 Agent 人格
9. test_*.py           # 验证理解
```
