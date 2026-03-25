# Phase 3: 同步脚本详细解读

> 从 `install.sh` 的 `first_sync()` 步骤进入，由 `run_loop.sh` 定期调用

---

## 一、整体结构

```
scripts/
│
├── file_lock.py                  # 文件锁工具（防止并发读写）
│
├── sync_from_openclaw_runtime.py # 从 OpenClaw 运行时同步任务
├── sync_agent_config.py          # 同步 Agent 配置
├── sync_officials_stats.py       # 同步官员统计数据
├── apply_model_changes.py        # 应用模型变更
├── refresh_live_data.py          # 刷新实时数据（心跳检测）
│
├── kanban_update.py              # 状态机核心（Agent 调用）
├── fetch_morning_news.py         # 获取早朝新闻
├── skill_manager.py              # 技能管理
├── utils.py                      # 工具函数
└── ...
```

---

## 二、文件锁工具 (file_lock.py)

### 2.1 为什么需要文件锁？

当多个进程同时读写同一个 JSON 文件时，可能导致数据丢失：

```
进程 A: 读取 data.json → 修改 → 写入
进程 B:    读取 data.json → 修改 → 写入
                    ↑
               数据丢失！A 的修改被 B 覆盖
```

**解决方案**：文件锁 + 原子写入

---

### 2.2 三种操作函数

```python
# 1. 原子读取（共享锁）
def atomic_json_read(path: pathlib.Path, default: Any = None) -> Any:
    """持锁读取 JSON 文件。"""
    lock_file = _lock_path(path)
    fd = os.open(str(lock_file), os.O_CREAT | os.O_RDWR)
    try:
        fcntl.flock(fd, fcntl.LOCK_SH)  # 共享锁（允许多读）
        return json.loads(path.read_text()) if path.exists() else default
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


# 2. 原子写入（排他锁 + 临时文件）
def atomic_json_write(path: pathlib.Path, data: Any) -> None:
    """原子写入 JSON 文件。"""
    lock_file = _lock_path(path)
    fd = os.open(str(lock_file), os.O_CREAT | os.O_RDWR)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)  # 排他锁
        # 写入临时文件
        tmp_fd, tmp_path = tempfile.mkstemp(dir=str(path.parent), suffix='.tmp')
        with os.fdopen(tmp_fd, 'w') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        # 原子重命名
        os.replace(tmp_path, str(path))
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


# 3. 原子更新（读 → 修改 → 写回）
def atomic_json_update(path, modifier, default=None):
    """原子地读取 → 修改 → 写回 JSON 文件。"""
    # 持排他锁后：读 → modifier(data) → 写回
```

---

### 2.3 fcntl 锁类型

| 锁类型 | 常量 | 说明 |
|--------|------|------|
| 共享锁 | `LOCK_SH` | 允许多个进程同时读，阻止写 |
| 排他锁 | `LOCK_EX` | 阻止其他进程读写 |
| 解锁 | `LOCK_UN` | 释放锁 |

---

### 2.4 原子写入原理

```
写入流程:
┌─────────────┐
│ 获取排他锁   │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│ 写入临时文件         │
│ data.tmp            │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ os.replace()        │  ← 原子操作
│ data.tmp → data.json│
└──────┬──────────────┘
       │
       ▼
┌─────────────┐
│ 释放锁      │
└─────────────┘
```

> `os.replace()` 是原子操作，即使系统崩溃也不会产生半写入的文件

---

## 三、任务同步脚本 (sync_from_openclaw_runtime.py)

### 3.1 整体作用

从 OpenClaw 运行时的 `sessions.json` 文件中提取任务信息，转换为看板格式。

```
~/.openclaw/agents/taizi/sessions/sessions.json
    │
    ▼ sync_from_openclaw_runtime.py
    │
data/tasks_source.json
```

---

### 3.2 核心函数详解

#### 状态判断函数

```python
def state_from_session(age_ms, aborted):
    """根据会话年龄和是否中断判断状态"""
    if aborted:
        return 'Blocked'
    if age_ms <= 2 * 60 * 1000:      # 2 分钟内
        return 'Doing'
    if age_ms <= 60 * 60 * 1000:     # 1 小时内
        return 'Review'
    return 'Next'                     # 超过 1 小时
```

| 条件 | 状态 | 含义 |
|------|------|------|
| `aborted=True` | `Blocked` | 上次运行中断，需要人工介入 |
| `age < 2min` | `Doing` | 正在执行 |
| `age < 1hour` | `Review` | 等待审查 |
| `age > 1hour` | `Next` | 待执行 |

---

#### 官员识别函数

```python
def detect_official(agent_id):
    """将 agent_id 映射为（角色，部门）"""
    mapping = {
        'taizi':    ('储君', '太子'),
        'zhongshu': ('中书令', '中书省'),
        'menxia':   ('侍中', '门下省'),
        'shangshu': ('尚书令', '尚书省'),
        'hubu':     ('户部尚书', '户部'),
        'libu':     ('礼部尚书', '礼部'),
        'bingbu':   ('兵部尚书', '兵部'),
        'xingbu':   ('刑部尚书', '刑部'),
        'gongbu':   ('工部尚书', '工部'),
        'libu_hr':  ('吏部尚书', '吏部'),
        'zaochao':  ('钦天监', '钦天监'),
    }
    return mapping.get(agent_id, ('尚书令', '尚书省'))
```

---

#### 任务构建函数

```python
def build_task(agent_id, session_key, row, now_ms):
    """从 sessions.json 中的一行构建任务对象"""
    return {
        'id': f"OC-{agent_id}-{session_id[:8]}",  # 任务 ID
        'title': title,                           # 任务标题
        'official': official,                     # 官员角色
        'org': org,                               # 所属部门
        'state': state,                           # 当前状态
        'now': latest_act,                        # 当前进展
        'eta': ms_to_str(updated_at),            # 预计完成时间
        'block': '上次运行中断' if aborted else '无',
        'output': session_file,                   # 输出文件路径
        'activity': load_activity(session_file),  # 活动记录
        'sourceMeta': {...}                       # 元数据
    }
```

---

### 3.3 任务过滤逻辑

```python
# 过滤掉非活跃的系统会话
filtered_tasks = []
one_day_ago = now_ms - 24 * 3600 * 1000

for t in tasks:
    # 1. 始终保留 JJC 任务
    if str(t['id']).startswith('JJC'):
        filtered_tasks.append(t)
        continue

    # 2. 排除超过 24 小时的
    if updated < one_day_ago:
        continue

    # 3. 排除纯后台任务（除非报错）
    if '定时任务' in title or '子任务' in title:
        if t.get('state') != 'Blocked':
            continue

    # 4. 只保留活跃状态
    if state not in ('Doing', 'Review', 'Blocked'):
        continue

    filtered_tasks.append(t)
```

---

### 3.4 执行流程图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    sync_from_openclaw_runtime.py 执行流程                    │
└─────────────────────────────────────────────────────────────────────────────���

                    ┌─────────────────┐
                    │     main()      │
                    └────────┬────────┘
                             │
                             ▼
        ┌─────────────────────────────────────────────┐
        │  遍历 ~/.openclaw/agents/*/sessions/       │
        │  读取 sessions.json                         │
        └────────────────────┬────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │  对每个 session:              │
              │  - 提取 agent_id              │
              │  - 计算 age_ms                │
              │  - 判断 state                 │
              │  - 加载 activity              │
              │  - build_task()               │
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │  合并其他任务源:              │
              │  - mission_control_tasks.json│
              │  - manual_parallel_tasks.json│
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │  过滤任务:                    │
              │  - 排除超过 24 小时的         │
              │  - 排除非活跃的后台任务       │
              │  - 只保留 Doing/Review/Blocked│
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │  合并已有 JJC 旨意任务        │
              │  (不覆盖皇上下旨记录)         │
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │  写入 data/tasks_source.json │
              │  写入 data/sync_status.json  │
              └──────────────────────────────┘
```

---

## 四、Agent 配置同步 (sync_agent_config.py)

### 4.1 整体作用

从 `~/.openclaw/openclaw.json` 读取 Agent 配置，转换为前端可用的格式。

```
~/.openclaw/openclaw.json
    │
    ▼ sync_agent_config.py
    │
data/agent_config.json
```

---

### 4.2 Agent 元数据定义

```python
ID_LABEL = {
    'taizi':    {'label': '太子',   'role': '太子',     'duty': '飞书消息分拣与回奏',  'emoji': '🤴'},
    'zhongshu': {'label': '中书省', 'role': '中书令',   'duty': '起草任务令与优先级',  'emoji': '📜'},
    'menxia':   {'label': '门下省', 'role': '侍中',     'duty': '审议与退回机制',      'emoji': '🔍'},
    'shangshu': {'label': '尚书省', 'role': '尚书令',   'duty': '派单与升级裁决',      'emoji': '📮'},
    'libu':     {'label': '礼部',   'role': '礼部尚书', 'duty': '文档/汇报/规范',      'emoji': '📝'},
    'hubu':     {'label': '户部',   'role': '户部尚书', 'duty': '资源/预算/成本',      'emoji': '💰'},
    'bingbu':   {'label': '兵部',   'role': '兵部尚书', 'duty': '应急与巡检',          'emoji': '⚔️'},
    'xingbu':   {'label': '刑部',   'role': '刑部尚书', 'duty': '合规/审计/红线',      'emoji': '⚖️'},
    'gongbu':   {'label': '工部',   'role': '工部尚书', 'duty': '工程交付与自动化',    'emoji': '🔧'},
    'libu_hr':  {'label': '吏部',   'role': '吏部尚书', 'duty': '人事/培训/Agent管理',  'emoji': '👔'},
    'zaochao':  {'label': '钦天监', 'role': '朝报官',   'duty': '每日新闻采集与简报',  'emoji': '📰'},
}
```

---

### 4.3 技能发现

```python
def get_skills(workspace: str):
    """扫描 workspace/skills/ 目录，提取技能信息"""
    skills_dir = pathlib.Path(workspace) / 'skills'
    skills = []

    if skills_dir.exists():
        for d in sorted(skills_dir.iterdir()):
            if d.is_dir():
                md = d / 'SKILL.md'
                desc = ''
                if md.exists():
                    # 读取 SKILL.md 第一行作为描述
                    for line in md.read_text().splitlines():
                        line = line.strip()
                        if line and not line.startswith('#'):
                            desc = line[:100]
                            break
                skills.append({
                    'name': d.name,
                    'path': str(md),
                    'exists': md.exists(),
                    'description': desc
                })
    return skills
```

---

### 4.4 输出结构

```json
{
  "generatedAt": "2026-03-20 14:30:00",
  "defaultModel": "anthropic/claude-sonnet-4-6",
  "knownModels": [...],
  "dispatchChannel": "feishu",
  "agents": [
    {
      "id": "taizi",
      "label": "太子",
      "role": "太子",
      "duty": "飞书消息分拣与回奏",
      "emoji": "🤴",
      "model": "anthropic/claude-sonnet-4-6",
      "workspace": "/Users/xxx/.openclaw/workspace-taizi",
      "skills": [...],
      "allowAgents": ["zhongshu"]
    },
    ...
  ]
}
```

---

### 4.5 附加功能：自动部署

```python
def deploy_soul_files():
    """将项目 agents/xxx/SOUL.md 部署到运行时 workspace"""
    for proj_name, runtime_id in _SOUL_DEPLOY_MAP.items():
        src = BASE / 'agents' / proj_name / 'SOUL.md'
        dst = pathlib.Path.home() / f'.openclaw/workspace-{runtime_id}/soul.md'
        if src.exists() and src.read_text() != dst.read_text():
            dst.write_text(src.read_text())

def sync_scripts_to_workspaces():
    """将项目 scripts/ 同步到各 workspace"""
    for proj_name, runtime_id in _SOUL_DEPLOY_MAP.items():
        ws_scripts = pathlib.Path.home() / f'.openclaw/workspace-{runtime_id}/scripts'
        for src_file in scripts_src.iterdir():
            # 只同步 .py 和 .sh 文件
            if src_file.suffix in ('.py', '.sh'):
                dst_file = ws_scripts / src_file.name
                dst_file.write_bytes(src_file.read_bytes())
```

---

## 五、官员统计同步 (sync_officials_stats.py)

### 5.1 整体作用

统计各 Agent 的 Token 消耗、任务完成数、成本等。

```
~/.openclaw/agents/*/sessions/sessions.json
    │
    ▼ sync_officials_stats.py
    │
data/officials_stats.json
```

---

### 5.2 模型定价表

```python
MODEL_PRICING = {
    'anthropic/claude-sonnet-4-6':  {'in':3.0, 'out':15.0, 'cr':0.30, 'cw':3.75},
    'anthropic/claude-opus-4-5':    {'in':15.0,'out':75.0, 'cr':1.50, 'cw':18.75},
    'anthropic/claude-haiku-3-5':   {'in':0.8, 'out':4.0,  'cr':0.08, 'cw':1.0},
    'openai/gpt-4o':                {'in':2.5, 'out':10.0, 'cr':1.25, 'cw':0},
    ...
}
```

| 字段 | 含义 | 单位 |
|------|------|------|
| `in` | 输入 Token 价格 | 美元/百万 Token |
| `out` | 输出 Token 价格 | 美元/百万 Token |
| `cr` | 缓存读取价格 | 美元/百万 Token |
| `cw` | 缓存写入价格 | 美元/百万 Token |

---

### 5.3 成本计算

```python
def calc_cost(s, model):
    """计算成本（美元）"""
    p = MODEL_PRICING.get(model, MODEL_PRICING['anthropic/claude-sonnet-4-6'])
    usd = (s['tokens_in']/1e6*p['in'] + s['tokens_out']/1e6*p['out']
         + s['cache_read']/1e6*p['cr'] + s['cache_write']/1e6*p['cw'])
    return round(usd, 4)
```

---

### 5.4 功绩评分

```python
def main():
    for off in OFFICIALS:
        # 计算功绩分数
        merit_score = (
            ts['tasks_done'] * 10 +           # 每完成一个任务 +10 分
            ts['flow_participations'] * 2 +   # 每次流程参与 +2 分
            min(ss['sessions'], 20)           # 会话数（最多 20 分）
        )
```

---

### 5.5 输出结构

```json
{
  "generatedAt": "2026-03-20 14:30:00",
  "officials": [
    {
      "id": "taizi",
      "label": "太子",
      "role": "太子",
      "emoji": "🤴",
      "rank": "储君",
      "model": "anthropic/claude-sonnet-4-6",
      "model_short": "claude-sonnet-4-6",
      "tokens_in": 12345,
      "tokens_out": 6789,
      "cache_read": 5000,
      "cache_write": 1000,
      "cost_usd": 0.15,
      "cost_cny": 1.09,
      "sessions": 42,
      "messages": 128,
      "tasks_done": 15,
      "tasks_active": 2,
      "flow_participations": 30,
      "merit_score": 214,
      "merit_rank": 1,
      "heartbeat": {"status": "active", "label": "🟢 活跃 1分钟前"}
    },
    ...
  ],
  "totals": {
    "tokens_total": 100000,
    "cost_usd": 1.50,
    "cost_cny": 10.88,
    "tasks_done": 50
  },
  "top_official": "太子"
}
```

---

## 六、模型变更应用 (apply_model_changes.py)

### 6.1 整体作用

从前端发起的模型变更请求，应用到 `openclaw.json` 并重启 Gateway。

```
前端 → POST /api/set-model
    │
    ▼
data/pending_model_changes.json
    │
    ▼ apply_model_changes.py
    │
~/.openclaw/openclaw.json
    │
    ▼
openclaw gateway restart
```

---

### 6.2 变更流程

```python
def main():
    # 1. 读取待处理的变更
    pending = rj(PENDING, [])
    if not pending:
        return

    # 2. 应用变更到 openclaw.json
    for change in pending:
        ag_id = change['agentId']
        new_model = change['model']
        for ag in agents_list:
            if ag.get('id') == ag_id:
                old = ag.get('model', default_model)
                if new_model == default_model:
                    ag.pop('model', None)  # 使用默认值
                else:
                    ag['model'] = new_model
                applied.append({...})

    # 3. 备份并写入
    shutil.copy2(OPENCLAW_CFG, bak_path)
    atomic_json_write(OPENCLAW_CFG, cfg)

    # 4. 重启 Gateway
    subprocess.run(['openclaw', 'gateway', 'restart'])

    # 5. 如果重启失败，回滚
    if restart_failed:
        shutil.copy2(bak_path, OPENCLAW_CFG)
```

---

### 6.3 流程图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        apply_model_changes.py 执行流程                       │
└─────────────────────────────────────────────────────────────────────────────┘

                    ┌─────────────────────┐
                    │ pending_model_changes│
                    │    .json 存在？      │
                    └──────────┬──────────┘
                               │
                         ┌─────┴─────┐
                         ▼           ▼
                        是           否
                         │           │
                         ▼           └──► 退出
              ┌──────────────────────┐
              │ 读取 openclaw.json   │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ 遍历 pending 变更    │
              │ 修改 agents.list     │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ 备份 openclaw.json   │
              │ 写入新配置           │
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ openclaw gateway     │
              │ restart              │
              └──────────┬───────────┘
                         │
                   ┌─────┴─────┐
                   ▼           ▼
                 成功         失败
                   │           │
                   ▼           ▼
              ┌─────────┐  ┌─────────────┐
              │ 清空    │  │ 回滚配置    │
              │ pending │  │ 从备份恢复  │
              └─────────┘  └─────────────┘
```

---

## 七、实时数据刷新 (refresh_live_data.py)

### 7.1 整体作用

整合所有数据源，生成 `live_status.json` 供前端轮询。

```
data/tasks_source.json
data/officials_stats.json
data/sync_status.json
    │
    ▼ refresh_live_data.py
    │
data/live_status.json
```

---

### 7.2 心跳检测

```python
def main():
    now_ts = datetime.datetime.now(datetime.timezone.utc)

    for t in tasks:
        if t.get('state') in ('Doing', 'Assigned', 'Review'):
            # 计算任务最后更新到现在的时间差
            age_sec = (now_ts - updated_dt).total_seconds()

            if age_sec < 180:  # 3 分钟内
                t['heartbeat'] = {'status': 'active', 'label': f'🟢 活跃 {int(age_sec//60)}分钟前'}
            elif age_sec < 600:  # 10 分钟内
                t['heartbeat'] = {'status': 'warn', 'label': f'🟡 可能停滞 {int(age_sec//60)}分钟前'}
            else:  # 超过 10 分钟
                t['heartbeat'] = {'status': 'stalled', 'label': f'🔴 已停滞 {int(age_sec//60)}分钟'}
```

| 时间差 | 状态 | 颜色 |
|--------|------|------|
| < 3 分钟 | `active` | 🟢 绿色 |
| 3-10 分钟 | `warn` | 🟡 黄色 |
| > 10 分钟 | `stalled` | 🔴 红色 |

---

### 7.3 输出结构

```json
{
  "generatedAt": "2026-03-20 14:30:00",
  "taskSource": "tasks_source.json",
  "officials": [...],
  "tasks": [
    {
      "id": "JJC-20260320-001",
      "title": "代码审查",
      "state": "Doing",
      "org": "兵部",
      "heartbeat": {"status": "active", "label": "🟢 活跃 1分钟前"},
      ...
    }
  ],
  "metrics": {
    "officialCount": 11,
    "todayDone": 5,
    "totalDone": 120,
    "inProgress": 3,
    "blocked": 1
  },
  "syncStatus": {"ok": true, "durationMs": 42},
  "health": {
    "syncOk": true,
    "syncLatencyMs": 42,
    "missingFieldCount": 0
  }
}
```

---

## 八、数据流向总览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              同步脚本数据流向                                │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────┐
│ ~/.openclaw/        │
│ ├─ openclaw.json    │──────────────────────────────────────────────┐
│ └─ agents/          │                                              │
│     └─ */sessions/  │                                              │
│         └─ sessions │───┐                                          │
└─────────────────────┘   │                                          │
                          │                                          │
                          ▼                                          ▼
          ┌─────────────────────────────┐      ┌─────────────────────────────┐
          │ sync_from_openclaw_runtime  │      │    sync_agent_config.py     │
          └──────────────┬──────────────┘      └──────────────┬──────────────┘
                         │                                     │
                         ▼                                     ▼
          ┌─────────────────────────────┐      ┌─────────────────────────────┐
          │   data/tasks_source.json    │      │   data/agent_config.json    │
          └──────────────┬──────────────┘      └──────────────┬──────────────┘
                         │                                     │
                         │         ┌───────────────────────────┘
                         │         │
                         ▼         ▼
          ┌─────────────────────────────────────────────────────┐
          │              sync_officials_stats.py                │
          └──────────────────────────┬──────────────────────────┘
                                     │
                                     ▼
          ┌─────────────────────────────────────────────────────┐
          │              data/officials_stats.json              │
          └──────────────────────────┬──────────────────────────┘
                                     │
                                     ▼
          ┌─────────────────────────────────────────────────────┐
          │               refresh_live_data.py                  │
          │   (整合 tasks + officials + sync_status)            │
          └──────────────────────────┬──────────────────────────┘
                                     │
                                     ▼
          ┌─────────────────────────────────────────────────────┐
          │               data/live_status.json                 │
          │               (前端轮询此文件)                       │
          └─────────────────────────────────────────────────────┘
```

---

## 九、核心要点总结

| 概念 | 说明 |
|------|------|
| **文件锁** | `fcntl.flock` 防止多进程并发读写 |
| **原子写入** | 临时文件 + `os.replace()` 保证数据完整性 |
| **任务状态** | Doing → Review → Next，根据时间自动判断 |
| **心跳检测** | 根据最后更新时间判断任务是否停滞 |
| **模型变更** | 前端请求 → pending → 应用 → 重启 Gateway |
| **功绩评分** | tasks_done * 10 + flow_participations * 2 |

---

## 十、Python 关键语法速查

| 语法 | 含义 |
|------|------|
| `pathlib.Path(__file__).parent` | 获取当前脚本所在目录 |
| `path.read_text()` | 读取文件内容（字符串） |
| `path.exists()` | 检查文件/目录是否存在 |
| `json.loads()` | 解析 JSON 字符串 |
| `json.dumps(data, ensure_ascii=False, indent=2)` | 格式化 JSON |
| `datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')` | 格式化时间 |
| `subprocess.run(['cmd', 'arg'], capture_output=True)` | 执行命令 |
| `shutil.copy2(src, dst)` | 复制文件（保留元数据） |
| `os.replace(tmp, dst)` | 原子重命名 |
| `tempfile.mkstemp()` | 创建临时文件 |
