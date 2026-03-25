# Phase 5: 数据层解读

## 一、整体结构

```
data/
├── schema.json              # 核心配置：状态、角色、字段定义
├── tasks.json               # 任务列表（持久化存储）
├── tasks_source.json        # 外部任务源（优先级高于 tasks.json）
├── live_status.json         # 实时看板数据（前端消费）
├── officials_stats.json     # Agent 统计（Token、成本）
├── sync_status.json         # 同步状态
├── pending_model_changes.json  # 待应用的模型变更
├── model_change_log.json    # 模型变更历史
└── morning_brief.json       # 早朝简报（钦天监生成）
```

---

## 二、schema.json - 核心配置文件

### 文件位置
`data/schema.json`

### 完整内容解析

```json
{
  "meta": {
    "title": "军机处",        // 项目名称
    "ownerTitle": "皇上",      // 最高决策者称呼
    "version": "v3"            // 配置版本
  },
  "states": ["Pending", "Taizi", "Zhongshu", "Menxia", "Assigned", "Next", "Doing", "Review", "Done", "Blocked", "Cancelled"],
  "stateFlow": "Pending → Taizi → Zhongshu → Menxia → Assigned → Doing → Review → Done",
  "terminalStates": ["Done", "Cancelled"],
  "roles": {
    "taizi": "太子",
    "zhongshu": "中书省",
    "menxia": "门下省",
    "shangshu": "尚书省",
    "hubu": "户部",
    "libu": "礼部",
    "bingbu": "兵部",
    "xingbu": "刑部",
    "gongbu": "工部",
    "libu_hr": "吏部",
    "zaochao": "钦天监"
  },
  "taskFields": ["id", "title", "official", "org", "state", "now", "eta", "block", "output", "ac", "flow_log", "updatedAt", "todos", "progress_log"]
}
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `meta.title` | string | 项目显示名称："军机处" |
| `meta.ownerTitle` | string | 皇上称呼，用于 UI 显示 |
| `meta.version` | string | 配置版本，便于迁移 |
| `states` | array | **11 种任务状态**，完整生命周期 |
| `stateFlow` | string | 标准流转路径（可视化字符串） |
| `terminalStates` | array | 终态，进入后不再流转 |
| `roles` | object | **11 个 Agent 角色映射** |
| `taskFields` | array | 任务对象的标准字段列表 |

---

## 三、任务状态机

### 状态流转图

```
┌─────────┐
│ Pending │ ← 初始状态（外部系统导入）
└────┬────┘
     │ 皇上发旨
     ▼
┌─────────┐
│  Taizi  │ ← 太子接旨、分拣
└────┬────┘
     │ 转交中书省
     ▼
┌──────────┐
│ Zhongshu │ ← 中书省起草方案
└────┬─────┘
     │ 提交审议
     ▼
┌─────────┐
│ Menxia  │ ← 门下省审议
└────┬────┘
     │ 准奏
     ▼
┌──────────┐
│ Assigned │ ← 尚书省派发
└────┬─────┘
     │ 六部接令
     ▼
┌─────────┐     ┌─────────┐
│  Doing  │ ←──→│ Blocked │ ← 遇到阻塞
└────┬────┘     └─────────┘
     │ 完成执行
     ▼
┌─────────┐
│ Review  │ ← 可选：代码审查
└────┬────┘
     │ 通过
     ▼
┌─────────┐
│  Done   │ ← 终态
└─────────┘

        ┌────────────┐
        │ Cancelled  │ ← 终态（任意状态可取消）
        └────────────┘
```

### 状态说明

| 状态 | 含义 | 触发条件 |
|------|------|----------|
| `Pending` | 待处理 | 外部系统同步创建 |
| `Taizi` | 太子处理中 | 皇上发旨 |
| `Zhongshu` | 中书省规划中 | 太子转交 |
| `Menxia` | 门下省审议中 | 中书省提交 |
| `Assigned` | 已派发 | 门下准奏 |
| `Next` | 待执行 | 优先队列 |
| `Doing` | 执行中 | 六部接令 |
| `Review` | 审查中 | 执行完成待验收 |
| `Done` | 已完成 | 终态 |
| `Blocked` | 阻塞 | 遇到依赖/资源问题 |
| `Cancelled` | 已取消 | 终态 |

---

## 四、任务对象结构

### 标准 Task 对象

```json
{
  "id": "JJC-20260320-001",           // 任务ID：军机处-日期-序号
  "title": "优化前端性能",              // 任务标题
  "official": "gongbu",                // 当前负责人（Agent ID）
  "org": "工部",                       // 所属部门
  "state": "Doing",                    // 当前状态
  "now": "正在重构组件",                // 当前动态
  "eta": "2026-03-21",                 // 预计完成时间
  "block": null,                       // 阻塞原因（如有）
  "output": "/path/to/result.md",      // 产出文件路径
  "ac": "通过所有测试",                 // 验收标准
  "flow_log": [                        // 流转日志
    {"from": "太子", "to": "中书省", "at": "2026-03-20 10:00", "remark": "旨意传达"}
  ],
  "updatedAt": "2026-03-20T15:30:00Z", // 最后更新时间
  "todos": [                           // 子任务列表
    {"id": 1, "title": "需求分析", "status": "completed"}
  ],
  "progress_log": [                    // 进展日志
    {"at": "2026-03-20 14:00", "msg": "开始分析代码"}
  ],
  "heartbeat": {                       // 心跳状态（refresh_live_data 生成）
    "status": "active",
    "label": "🟢 活跃 5分钟前",
    "ageSec": 300
  },
  "outputMeta": {                      // 产出文件元信息
    "exists": true,
    "lastModified": "2026-03-20 16:00:00"
  }
}
```

### 字段用途

| 字段 | 类型 | 用途 |
|------|------|------|
| `id` | string | **全局唯一标识**，格式 `JJC-YYYYMMDD-NNN` |
| `title` | string | 任务标题（太子概括） |
| `official` | string | 当前负责人 agent_id |
| `org` | string | 部门中文名（用于 UI 显示） |
| `state` | string | 当前状态（必须属于 `states` 列表） |
| `now` | string | 当前动态描述（实时更新） |
| `eta` | string | 预计完成时间 |
| `block` | string | 阻塞原因（仅 Blocked 状态） |
| `output` | string | 产出文件路径 |
| `ac` | string | Acceptance Criteria（验收标准） |
| `flow_log` | array | **流转历史**，记录每次状态变更 |
| `updatedAt` | string | ISO 8601 时间戳 |
| `todos` | array | 子任务清单（支持进度追踪） |
| `progress_log` | array | 进展日志（思考过程记录） |
| `heartbeat` | object | 心跳状态（系统生成，非持久化） |
| `outputMeta` | object | 产出文件元信息（系统生成） |

---

## 五、live_status.json - 前端数据源

### 生成方式
由 `scripts/refresh_live_data.py` 定时刷新

### 结构

```json
{
  "generatedAt": "2026-03-20 16:30:00",
  "taskSource": "tasks_source.json",
  "officials": [...],          // Agent 列表（来自 officials_stats.json）
  "tasks": [...],              // 任务列表（带 heartbeat、outputMeta）
  "history": [...],            // 最近完成任务
  "metrics": {
    "officialCount": 11,
    "todayDone": 5,
    "totalDone": 128,
    "inProgress": 3,
    "blocked": 1
  },
  "syncStatus": {...},         // 同步状态
  "health": {                  // 健康度
    "syncOk": true,
    "syncLatencyMs": 150,
    "missingFieldCount": 0
  }
}
```

### 消费者
- 前端 `api.ts` 通过 `/api/live-status` 获取
- React 组件通过 Zustand store 订阅

---

## 六、心跳机制

### 实现位置
`scripts/refresh_live_data.py` 第 43-65 行

### 逻辑

```python
# 对 Doing/Assigned/Review 状态的任务计算活跃度
if t.get('state') in ('Doing', 'Assigned', 'Review'):
    age_sec = (now - updated_at).total_seconds()

    if age_sec < 180:          # 3 分钟内
        status = 'active'      # 🟢 活跃
    elif age_sec < 600:        # 10 分钟内
        status = 'warn'        # 🟡 可能停滞
    else:
        status = 'stalled'     # 🔴 已停滞
```

### 心跳状态

| 状态 | 阈值 | 图标 | 含义 |
|------|------|------|------|
| `active` | < 3 分钟 | 🟢 | Agent 正在活跃工作 |
| `warn` | 3-10 分钟 | 🟡 | 可能停滞，需关注 |
| `stalled` | > 10 分钟 | 🔴 | 已停滞，需要干预 |
| `unknown` | 无时间戳 | ⚪ | 无法判断 |

---

## 七、数据流转图

```
┌─────────────────────────────────────────────────────────────┐
│                     外部系统（OpenClaw）                      │
└───────────────────────────┬─────────────────────────────────┘
                            │ sync_from_openclaw_runtime.py
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    tasks_source.json                        │
│              （外部系统同步的任务源，优先级最高）                │
└───────────────────────────┬─────────────────────────────────┘
                            │ refresh_live_data.py
                            │ (fallback 到 tasks.json)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    live_status.json                         │
│                   （前端 API 数据源）                         │
└───────────────────────────┬─────────────────────────────────┘
                            │ HTTP GET /api/live-status
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      React 前端                              │
│            （Zustand Store → Components）                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 八、核心要点

| 要点 | 说明 |
|------|------|
| **任务 ID 格式** | `JJC-YYYYMMDD-NNN`（军机处-日期-当天序号） |
| **11 种状态** | 覆盖完整任务生命周期 |
| **11 个角色** | 太子 + 三省 + 六部 + 钦天监 |
| **心跳检测** | 3/10 分钟阈值，自动标注停滞任务 |
| **数据优先级** | `tasks_source.json` > `tasks.json` |
| **原子写入** | 所有 JSON 操作通过 `file_lock.py` 保证并发安全 |
| **看板命令** | 所有操作必须通过 `kanban_update.py` CLI，禁止直接改文件 |

---

## 九、相关文件

| 文件 | 用途 |
|------|------|
| [data/schema.json](data/schema.json) | 核心配置 |
| [scripts/file_lock.py](scripts/file_lock.py) | 原子 JSON 操作 |
| [scripts/kanban_update.py](scripts/kanban_update.py) | 看板命令 CLI |
| [scripts/refresh_live_data.py](scripts/refresh_live_data.py) | 心跳检测 + 数据刷新 |
