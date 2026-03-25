# Phase 4: server.py 详细解读

> 从 `install.sh` 的 `restart_gateway()` 步骤进入，作为 API 服务运行

---

## 一、整体结构

```
dashboard/server.py (~2100 行)
│
├── 第 1-65 行:      头部设置（导入、常量、MIME 类型）
│
├── 第 67-92 行:     CORS 和任务持久化函数
│
├── 第 95-208 行:    任务操作函数
│                     ├── handle_task_action()    # 停止/取消/恢复任务
│                     ├── handle_archive_task()   # 归档任务
│                     └── update_task_todos()     # 更新待办
│
├── 第 210-475 行:   技能管理函数
│                     ├── read_skill_content()    # 读取技能内容
│                     ├── add_skill_to_agent()    # 添加本地技能
│                     ├── add_remote_skill()      # 添加远程技能
│                     ├── get_remote_skills_list()# 列出远程技能
│                     ├── update_remote_skill()   # 更新远程技能
│                     └── remove_remote_skill()   # 移除远程技能
│
├── 第 531-648 行:   任务创建和审议函数
│                     ├── handle_create_task()    # 创建新任务（下旨）
│                     └── handle_review_action()  # 门下省御批
│
├── 第 651-853 行:   Agent 状态检测函数
│                     ├── _check_gateway_alive()  # 检测 Gateway 进程
│                     ├── _check_agent_process()  # 检测 Agent 进程
│                     ├── get_agents_status()     # 获取所有 Agent 状态
│                     └── wake_agent()            # 唤醒 Agent
│
├── 第 886-1191 行:  调度器函数（_scheduler_*）
│                     ├── _ensure_scheduler()     # 初始化调度器
│                     ├── handle_scheduler_scan() # 扫描停滞任务
│                     ├── handle_scheduler_retry()# 重试
│                     ├── handle_scheduler_escalate() # 升级
│                     └── handle_scheduler_rollback() # 回滚
│
├── 第 1621-1862 行: 任务活动追踪
│                     └── get_task_activity()     # 获取任务实时进展
│
├── 第 1865-2056 行: 状态推进和派发
│                     ├── dispatch_for_state()    # 自动派发 Agent
│                     └── handle_advance_state()  # 手动推进状态
│
└── 第 2059-... 行:  HTTP Handler 类
                      └── class Handler            # 处理 HTTP 请求
```

---

## 二、API 端点总览

| 端点 | 方法 | 作用 |
|------|------|------|
| `/api/live-status` | GET | 获取实时状态（任务、心跳） |
| `/api/agent-config` | GET | 获取 Agent 配置 |
| `/api/officials-stats` | GET | 获取官员统计 |
| `/api/morning-brief` | GET | 获取早朝要闻 |
| `/api/agents-status` | GET | 获取 Agent 在线状态 |
| `/api/set-model` | POST | 设置 Agent 模型 |
| `/api/task-action` | POST | 任务操作（停止/取消/恢复） |
| `/api/review-action` | POST | 门下省御批（准奏/封驳） |
| `/api/advance-state` | POST | 手动推进状态 |
| `/api/create-task` | POST | 创建新任务（下旨） |
| `/api/scheduler-scan` | POST | 扫描停滞任务 |
| `/api/agent-wake` | POST | 唤醒 Agent |
| `/api/skill-content/:agent/:skill` | GET | 获取技能内容 |
| `/api/add-skill` | POST | 添加技能 |
| `/api/court-discuss/*` | POST | 朝堂议政相关 |

---

## 三、核心功能详解

### 3.1 任务操作 (handle_task_action)

```python
def handle_task_action(task_id, action, reason):
    """Stop/cancel/resume a task from the dashboard."""
    tasks = load_tasks()
    task = next((t for t in tasks if t.get('id') == task_id), None)

    if action == 'stop':
        task['state'] = 'Blocked'
        task['block'] = reason or '皇上叫停'
        task['now'] = f'⏸️ 已暂停：{reason}'

    elif action == 'cancel':
        task['state'] = 'Cancelled'
        task['block'] = reason or '皇上取消'

    elif action == 'resume':
        task['state'] = task.get('_prev_state', 'Doing')
        task['block'] = '无'

    # 记录流转日志
    task.setdefault('flow_log', []).append({
        'at': now_iso(),
        'from': '皇上',
        'to': task.get('org', ''),
        'remark': f'{"⏸️ 叫停" if action == "stop" else "🚫 取消"}：{reason}'
    })

    save_tasks(tasks)
```

| action | 状态变化 | 用途 |
|--------|----------|------|
| `stop` | → `Blocked` | 暂停任务，等待人工介入 |
| `cancel` | → `Cancelled` | 取消任务 |
| `resume` | → 之前的状态 | 恢复执行 |

---

### 3.2 任务创建 (handle_create_task)

```python
def handle_create_task(title, org='中书省', priority='normal', ...):
    """从看板创建新任务（圣旨模板下旨）。"""

    # 1. 标题校验
    if len(title) < 6:
        return {'ok': False, 'error': '标题过短'}
    if title.lower() in _JUNK_TITLES:  # '好', 'ok', '测试' 等
        return {'ok': False, 'error': '不是有效旨意'}

    # 2. 生成任务 ID: JJC-YYYYMMDD-NNN
    today = datetime.datetime.now().strftime('%Y%m%d')
    task_id = f'JJC-{today}-{seq:03d}'

    # 3. 创建任务（起点：太子分拣）
    new_task = {
        'id': task_id,
        'title': title,
        'org': '太子',
        'state': 'Taizi',
        'now': '等待太子接旨分拣',
        'flow_log': [{
            'at': now_iso(),
            'from': '皇上',
            'to': '太子',
            'remark': f'下旨：{title}'
        }],
    }

    tasks.insert(0, new_task)
    save_tasks(tasks)

    # 4. 自动派发给太子
    dispatch_for_state(task_id, new_task, 'Taizi')

    return {'ok': True, 'taskId': task_id}
```

**任务 ID 格式**:
- `JJC-20260320-001` → 2026年3月20日第1道旨意
- `OC-taizi-abc12345` → OpenClaw 运行时会话

---

### 3.3 门下省审议 (handle_review_action)

```python
def handle_review_action(task_id, action, comment=''):
    """门下省御批：准奏/封驳。"""

    if action == 'approve':
        if task['state'] == 'Menxia':
            task['state'] = 'Assigned'
            task['now'] = '门下省准奏，移交尚书省派发'
        else:  # Review
            task['state'] = 'Done'
            task['now'] = '御批通过，任务完成'

    elif action == 'reject':
        round_num = (task.get('review_round') or 0) + 1
        task['review_round'] = round_num
        task['state'] = 'Zhongshu'
        task['now'] = f'封驳退回中书省修订（第{round_num}轮）'
```

| action | 状态变化 | 含义 |
|--------|----------|------|
| `approve` | Menxia → Assigned | 准奏，派发执行 |
| `approve` | Review → Done | 御批准奏，任务完成 |
| `reject` | → Zhongshu | 封驳，退回中书省修订 |

---

### 3.4 Agent 状态检测 (get_agents_status)

```python
def get_agents_status():
    """获取所有 Agent 的在线状态。"""

    gateway_alive = _check_gateway_alive()      # pgrep openclaw-gateway
    gateway_probe = _check_gateway_probe()      # HTTP 请求 127.0.0.1:18789

    for dept in _AGENT_DEPTS:
        agent_id = dept['id']
        has_workspace = _check_agent_workspace(agent_id)
        last_ts, sess_count, is_busy = _get_agent_session_status(agent_id)
        process_alive = _check_agent_process(agent_id)

        # 状态判定
        if not has_workspace:
            status = 'unconfigured'
        elif not gateway_alive:
            status = 'offline'
        elif process_alive or is_busy:
            status = 'running'
        else:
            status = 'idle'
```

**状态判定逻辑**:

```
┌──────────────────────────┐
│ workspace 存在？          │
└────────────┬─────────────┘
             │
       ┌─────┴─────┐
       ▼           ▼
      否           是
       │           │
       ▼           ▼
  unconfigured  ┌──────────────────┐
               │ Gateway 进程存在？ │
               └────────┬─────────┘
                        │
                  ┌─────┴─────┐
                  ▼           ▼
                 否           是
                  │           │
                  ▼           ▼
              offline    ┌─────────────────┐
                         │ Agent 进程活跃？  │
                         └────────┬────────┘
                                  │
                            ┌─────┴─────┐
                            ▼           ▼
                           是           否
                            │           │
                            ▼           ▼
                        running       idle
```

---

### 3.5 调度器扫描 (handle_scheduler_scan)

```python
def handle_scheduler_scan(threshold_sec=600):
    """扫描停滞任务，自动处理。"""

    for task in tasks:
        if state in _TERMINAL_STATES:  # Done, Cancelled
            continue
        if state == 'Blocked':
            continue

        # 计算停滞时间
        stalled_sec = now - last_progress_time
        if stalled_sec < threshold_sec:
            continue  # 未超时，跳过

        # 重试逻辑
        if retry_count < max_retry:
            # 触发自动重试
            dispatch_for_state(task_id, task, state, trigger='taizi-scan-retry')
            continue

        # 升级逻辑
        if escalation_level < 2:
            # 升级到门下省或尚书省协调
            wake_agent('menxia' if level == 0 else 'shangshu', msg)
            continue

        # 回滚逻辑
        if auto_rollback:
            # 回滚到上个稳定状态
            task['state'] = snapshot['state']
            dispatch_for_state(task_id, task, snap_state)
```

**停滞处理流程**:

```
任务停滞超过阈值 (如 600 秒)
    │
    ▼
┌─────────────────────┐
│ 重试次数 < 最大重试？ │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     ▼           ▼
    是           否
     │           │
     ▼           ▼
 自动重试    ┌─────────────────┐
             │ 升级等级 < 2？   │
             └────────┬────────┘
                      │
                ┌─────┴─────┐
                ▼           ▼
               是           否
                │           │
                ▼           ▼
           升级到门下省   自动回滚
           或尚书省协调   到稳定状态
```

---

### 3.6 自动派发 (dispatch_for_state)

```python
def dispatch_for_state(task_id, task, new_state, trigger='state-transition'):
    """推进后自动派发对应 Agent（后台异步）。"""

    # 状态 → Agent 映射
    agent_id = _STATE_AGENT_MAP.get(new_state)
    # {'Taizi': 'taizi', 'Zhongshu': 'zhongshu', 'Menxia': 'menxia', ...}

    # 构造派发消息
    msg = f'📜 皇上旨意需要你处理\n任务ID: {task_id}\n旨意: {title}'

    # 后台异步派发
    def _do_dispatch():
        cmd = ['openclaw', 'agent', '--agent', agent_id, '-m', msg,
               '--deliver', '--channel', 'feishu', '--timeout', '300']
        result = subprocess.run(cmd, capture_output=True, timeout=310)
        if result.returncode == 0:
            log.info(f'✅ {task_id} 自动派发成功 → {agent_id}')

    threading.Thread(target=_do_dispatch, daemon=True).start()
```

---

## 四、状态流转图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              任务状态流转                                    │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌─────────┐
                              │  皇上   │
                              └────┬────┘
                                   │ 下旨
                                   ▼
                            ┌────────────┐
                      ┌─────│   Taizi    │◀─────────────────────┐
                      │     │   太子     │                       │
                      │     └─────┬──────┘                       │
                      │           │ 分拣                         │
                      │           ▼                              │
                      │     ┌────────────┐                       │
                      │     │  Zhongshu  │◀─────┐                │
                      │     │   中书省   │      │                │
                      │     └─────┬──────┘      │                │
                      │           │ 起草        │ 封驳           │
                      │           ▼             │ (reject)       │
                      │     ┌────────────┐      │                │
                      │     │   Menxia   │──────┘                │
                      │     │   门下省   │                       │
                      │     └─────┬──────┘                       │
                      │           │ 准奏 (approve)               │
                      │           ▼                              │
                      │     ┌────────────┐                       │
                      │     │  Assigned  │                       │
                      │     │   尚书省   │                       │
                      │     └─────┬──────┘                       │
                      │           │ 派发                         │
                      │           ▼                              │
                      │     ┌────────────┐                       │
                      │     │   Doing    │                       │
                      │     │    六部    │                       │
                      │     └─────┬──────┘                       │
                      │           │ 执行完成                     │
                      │           ▼                              │
                      │     ┌────────────┐                       │
                      │     │   Review   │                       │
                      │     │   尚书省   │                       │
                      │     └─────┬──────┘                       │
                      │           │ 汇总                         │
                      │           ▼                              │
                      │     ┌────────────┐                       │
                      └────▶│    Done    │───────────────────────┘
                            │    完成    │
                            └────────────┘

特殊状态:
┌─────────┐     ┌────────────┐     ┌────────────┐
│ Blocked │     │ Cancelled  │     │    Next    │
│  阻塞   │     │   已取消   │     │   待执行   │
└─────────┘     └────────────┘     └────────────┘
```

---

## 五、HTTP Handler 类

### 5.1 基本结构

```python
class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        # 只记录 4xx/5xx 错误
        if status.startswith('4') or status.startswith('5'):
            log.warning(...)

    def do_OPTIONS(self):
        # CORS 预检请求
        self.send_response(200)
        cors_headers(self)

    def do_GET(self):
        # 路由分发
        if path == '/api/live-status':
            self.send_json(read_json(DATA / 'live_status.json'))
        elif path == '/api/agent-config':
            self.send_json(read_json(DATA / 'agent_config.json'))
        # ...

    def do_POST(self):
        # 解析请求体
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        data = json.loads(body)

        # 路由分发
        if path == '/api/set-model':
            result = handle_set_model(data['agentId'], data['model'])
        elif path == '/api/create-task':
            result = handle_create_task(**data)
        # ...
```

---

### 5.2 CORS 处理

```python
def cors_headers(h):
    req_origin = h.headers.get('Origin', '')
    if ALLOWED_ORIGIN:
        origin = ALLOWED_ORIGIN
    elif req_origin in _DEFAULT_ORIGINS:
        origin = req_origin
    else:
        origin = 'http://127.0.0.1:7891'

    h.send_header('Access-Control-Allow-Origin', origin)
    h.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    h.send_header('Access-Control-Allow-Headers', 'Content-Type')
```

**允许的来源**:
```python
_DEFAULT_ORIGINS = {
    'http://127.0.0.1:7891',   # 生产环境
    'http://localhost:7891',
    'http://127.0.0.1:5173',   # Vite 开发服务器
    'http://localhost:5173',
}
```

---

## 六、安全措施

### 6.1 输入校验

```python
# 防止路径遍历攻击
_SAFE_NAME_RE = re.compile(r'^[a-zA-Z0-9_\-\u4e00-\u9fff]+$')

if not _SAFE_NAME_RE.match(agent_id):
    return {'ok': False, 'error': f'agent_id 非法'}

# 路径必须在允许的目录内
allowed_roots = (OCLAW_HOME.resolve(), BASE.parent.resolve())
if not any(str(skill_path).startswith(str(root)) for root in allowed_roots):
    return {'ok': False, 'error': '路径不在允许的目录范围内'}
```

### 6.2 URL 校验

```python
# 远程技能只允许 HTTPS
if not validate_url(source_url, allowed_schemes=('https',)):
    return {'ok': False, 'error': 'URL 无效或不安全（仅支持 HTTPS）'}
```

### 6.3 请求体大小限制

```python
MAX_REQUEST_BODY = 1 * 1024 * 1024  # 1 MB
```

---

## 七、数据流向图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           server.py 数据流向                                 │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────┐      HTTP GET/POST     ┌──────────────────┐
│   前端       │ ──────────────────────►│   server.py      │
│  (React)     │                        │  (Port 7891)     │
│              │ ◄────────────────────── │                  │
│              │      JSON Response      └────────┬─────────┘
└──────────────┘                                  │
                                                  │
                    ┌─────────────────────────────┼─────────────────────────────┐
                    │                             │                             │
                    ▼                             ▼                             ▼
          ┌─────────────────┐          ┌─────────────────┐          ┌─────────────────┐
          │ data/*.json     │          │ openclaw CLI    │          │ court_discuss   │
          │                 │          │                 │          │    .py          │
          │ ├─ tasks_source │          │ agent --agent   │          │                 │
          │ ├─ live_status  │          │ gateway restart │          │ 朝堂议政逻辑    │
          │ ├─ agent_config │          │                 │          │                 │
          │ └─ ...          │          └─────────────────┘          └─────────────────┘
          └─────────────────┘
                    │
                    ▲
                    │ atomic_json_read/write
                    │
          ┌─────────────────┐
          │   file_lock.py  │
          │   (文件锁)       │
          └─────────────────┘
```

---

## 八、核心要点总结

| 概念 | 说明 |
|------|------|
| **HTTP Server** | 使用 Python 标准库 `http.server`，端口 7891 |
| **CORS** | 只允许 localhost 访问，防止跨站攻击 |
| **任务状态机** | Taizi → Zhongshu → Menxia → Assigned → Doing → Review → Done |
| **自动派发** | 状态推进后自动调用 `openclaw agent` 派发给对应 Agent |
| **调度器** | 扫描停滞任务，自动重试 → 升级 → 回滚 |
| **文件锁** | 所有 JSON 读写都使用 `atomic_json_*` 函数 |

---

## 九、Python 关键语法速查

| 语法 | 含义 |
|------|------|
| `BaseHTTPRequestHandler` | Python 内置 HTTP 请求处理器基类 |
| `self.rfile.read(n)` | 读取请求体（n 字节） |
| `self.wfile.write(data)` | 写入响应体 |
| `self.send_response(200)` | 发送状态码 |
| `self.send_header('K', 'V')` | 发送响应头 |
| `threading.Thread(target=fn, daemon=True).start()` | 启动守护线程 |
| `subprocess.run(cmd, capture_output=True, timeout=30)` | 执行命令 |
| `json.loads(body)` | 解析 JSON 字符串 |
| `json.dumps(data, ensure_ascii=False)` | 序列化为 JSON |

---

## 十、启动命令

```bash
# 默认端口 7891
python3 dashboard/server.py

# 自定义端口
python3 dashboard/server.py --port 8080

# 允许跨域
python3 dashboard/server.py --cors http://localhost:3000
```
