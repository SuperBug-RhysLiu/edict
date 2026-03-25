
# Phase 2: 前端代码详细解读

---

## 一、整体结构

```
edict/frontend/
│
├── index.html              # HTML 入口（13 行）
├── src/
│   ├── main.tsx            # React 入口（11 行）
│   ├── App.tsx             # 主应用组件（102 行）
│   ├── store.ts            # Zustand 状态管理（459 行）
│   ├── api.ts              # API 调用层（433 行）
│   ├── index.css           # 全局样式（674 行）
│   │
│   └── components/         # UI 组件
│       ├── EdictBoard.tsx      # 旨意看板
│       ├── MonitorPanel.tsx    # 省部调度
│       ├── OfficialPanel.tsx   # 官员总览
│       ├── ModelConfig.tsx     # 模型配置
│       ├── SkillsConfig.tsx    # 技能配置
│       ├── SessionsPanel.tsx   # 小任务
│       ├── MemorialPanel.tsx   # 奏折阁
│       ├── TemplatePanel.tsx   # 旨库
│       ├── MorningPanel.tsx    # 天下要闻
│       ├── CourtDiscussion.tsx # 朝堂议政
│       ├── CourtCeremony.tsx   # 朝堂仪式动画
│       ├── TaskModal.tsx       # 任务详情弹窗
│       ├── ConfirmDialog.tsx   # 确认对话框
│       └── Toaster.tsx         # Toast 提示
│
├── package.json            # 依赖配置
├── vite.config.ts          # Vite 构建配置
├── tailwind.config.js      # Tailwind CSS 配置
└── tsconfig.json           # TypeScript 配置
```

---

## 二、技术栈详解

### 依赖分析 (package.json)

```json
{
  "dependencies": {
    "react": "^18.3.1",        // UI 框架
    "react-dom": "^18.3.1",    // React DOM 渲染
    "zustand": "^4.5.5",       // 轻量级状态管理
    "lucide-react": "^0.460.0", // 图标库
    "clsx": "^2.1.1"           // CSS 类名合并工具
  },
  "devDependencies": {
    "typescript": "^5.6.3",    // TypeScript
    "vite": "^6.0.1",          // 构建工具（极快）
    "tailwindcss": "^3.4.15",  // CSS 框架
    "@vitejs/plugin-react": "^4.3.4" // Vite React 插件
  }
}
```

| 技术 | 作用 | 为什么选它 |
|------|------|-----------|
| **React 18** | UI 组件化 | 生态成熟，组件复用 |
| **Zustand** | 状态管理 | 比 Redux 简单，无 boilerplate |
| **Vite** | 构建工具 | 比 Webpack 快 10 倍 |
| **Tailwind CSS** | 样式 | 原子化 CSS，开发快 |
| **TypeScript** | 类型检查 | 减少运行时错误 |

---

## 三、入口文件详解

### 3.1 index.html（HTML 入口）

```html
<!DOCTYPE html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <link rel="icon" type="image/svg+xml" href="/vite.svg" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>三省六部 · Edict Dashboard</title>
  </head>
  <body>
    <div id="root"></div>                    <!-- React 挂载点 -->
    <script type="module" src="/src/main.tsx"></script>  <!-- 入口脚本 -->
  </body>
</html>
```

| 元素 | 作用 |
|------|------|
| `<div id="root">` | React 应用的挂载容器 |
| `type="module"` | 使用 ES6 模块语法 |
| `viewport` | 移动端适配 |

---

### 3.2 main.tsx（React 入口）

```tsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
```

**逐行解析**:

| 行号 | 代码 | 含义 |
|------|------|------|
| 1 | `import React from 'react'` | 导入 React（JSX 需要） |
| 2 | `import ReactDOM from 'react-dom/client'` | 导入 React 18 的新渲染 API |
| 3 | `import App from './App'` | 导入主应用组件 |
| 4 | `import './index.css'` | 导入全局样式 |
| 6 | `ReactDOM.createRoot(...)` | React 18 新 API，支持并发特性 |
| 7 | `<React.StrictMode>` | 严格模式，开发时检查潜在问题 |
| 8 | `<App />` | 渲染主应用组件 |

**React 17 vs 18 对比**:
```tsx
// React 17（旧）
ReactDOM.render(<App />, document.getElementById('root'))

// React 18（新）
ReactDOM.createRoot(document.getElementById('root')!).render(<App />)
```

> 新 API 支持并发渲染（Concurrent Rendering），性能更好

---

### 3.3 App.tsx（主应用组件）

```tsx
import { useEffect } from 'react';
import { useStore, TAB_DEFS, startPolling, stopPolling } from './store';
import EdictBoard from './components/EdictBoard';
// ... 其他组件导入

export default function App() {
  const activeTab = useStore((s) => s.activeTab);       // 当前选中的 Tab
  const setActiveTab = useStore((s) => s.setActiveTab); // 设置 Tab 的函数
  const liveStatus = useStore((s) => s.liveStatus);     // 实时状态数据
  const countdown = useStore((s) => s.countdown);       // 刷新倒计时
  const loadAll = useStore((s) => s.loadAll);           // 刷新所有数据

  useEffect(() => {
    startPolling();           // 组件挂载时开始轮询
    return () => stopPolling(); // 组件卸载时停止轮询
  }, []);

  // 计算统计数据
  const tasks = liveStatus?.tasks || [];
  const edicts = tasks.filter(isEdict);
  const activeEdicts = edicts.filter((t) => !isArchived(t));

  // Tab 徽章计数
  const tabBadge = (key: string): string => {
    if (key === 'edicts') return String(activeEdicts.length);
    if (key === 'sessions') return String(tasks.filter((t) => !isEdict(t)).length);
    // ...
  };

  return (
    <div className="wrap">
      {/* 头部 */}
      <div className="hdr">...</div>

      {/* Tab 导航 */}
      <div className="tabs">
        {TAB_DEFS.map((t) => (
          <div key={t.key} className={`tab ${activeTab === t.key ? 'active' : ''}`}
               onClick={() => setActiveTab(t.key)}>
            {t.icon} {t.label}
            {tabBadge(t.key) && <span className="tbadge">{tabBadge(t.key)}</span>}
          </div>
        ))}
      </div>

      {/* 面板内容 - 根据当前 Tab 显示不同组件 */}
      {activeTab === 'edicts' && <EdictBoard />}
      {activeTab === 'court' && <CourtDiscussion />}
      {activeTab === 'monitor' && <MonitorPanel />}
      {/* ... 其他面板 */}

      {/* 弹窗层 */}
      <TaskModal />
      <Toaster />
      <CourtCeremony />
    </div>
  );
}
```

**关键概念**:

| 概念 | 说明 |
|------|------|
| `useStore((s) => s.xxx)` | Zustand 的状态选择器，只订阅需要的状态 |
| `useEffect` | React 副作用 Hook，处理轮询等 |
| 条件渲染 | `{activeTab === 'edicts' && <EdictBoard />}` |

---

## 四、状态管理详解（store.ts）

### 4.1 Zustand 核心概念

```tsx
import { create } from 'zustand';

interface AppStore {
  // 状态
  liveStatus: LiveStatus | null;
  activeTab: TabKey;

  // 操作
  setActiveTab: (tab: TabKey) => void;
  loadAll: () => Promise<void>;
}

export const useStore = create<AppStore>((set, get) => ({
  // 初始状态
  liveStatus: null,
  activeTab: 'edicts',

  // 操作实现
  setActiveTab: (tab) => set({ activeTab: tab }),

  loadAll: async () => {
    const data = await api.liveStatus();
    set({ liveStatus: data });
  },
}));
```

**Zustand vs Redux 对比**:

| 特性 | Zustand | Redux |
|------|---------|-------|
| 代码量 | ~50 行 | ~200 行 |
| Boilerplate | 无 | actions, reducers, types |
| Provider | 不需要 | 需要 `<Provider>` |
| 学习曲线 | 低 | 高 |

---

### 4.2 状态结构

```tsx
interface AppStore {
  // ── 数据 ──
  liveStatus: LiveStatus | null;      // 实时状态（任务、同步状态）
  agentConfig: AgentConfig | null;    // Agent 配置（模型、技能）
  changeLog: ChangeLogEntry[];        // 模型变更日志
  officialsData: OfficialsData | null; // 官员统计
  agentsStatusData: AgentsStatusData | null; // Agent 运行状态
  morningBrief: MorningBrief | null;  // 早朝要闻

  // ── UI 状态 ──
  activeTab: TabKey;                  // 当前 Tab
  edictFilter: 'active' | 'archived' | 'all'; // 旨意过滤
  modalTaskId: string | null;         // 当前查看的任务 ID
  countdown: number;                  // 刷新倒计时（秒）
  toasts: Toast[];                    // Toast 消息列表

  // ── 操作 ──
  setActiveTab: (tab: TabKey) => void;
  loadLive: () => Promise<void>;
  loadAll: () => Promise<void>;
  toast: (msg: string, type?: 'ok' | 'err') => void;
}
```

---

### 4.3 轮询机制

```tsx
let _cdTimer: ReturnType<typeof setInterval> | null = null;

export function startPolling() {
  if (_cdTimer) return;  // 防止重复启动
  useStore.getState().loadAll();  // 立即加载一次

  _cdTimer = setInterval(() => {
    const s = useStore.getState();
    const cd = s.countdown - 1;  // 倒计时减 1

    if (cd <= 0) {
      s.setCountdown(5);  // 重置为 5 秒
      s.loadAll();        // 刷新数据
    } else {
      s.setCountdown(cd);
    }
  }, 1000);  // 每秒执行一次
}

export function stopPolling() {
  if (_cdTimer) {
    clearInterval(_cdTimer);
    _cdTimer = null;
  }
}
```

**轮询流程图**:
```
startPolling()
    │
    ├─► 立即 loadAll()
    │
    └─► setInterval(1秒)
            │
            ├─► countdown = countdown - 1
            │
            └─► if countdown <= 0:
                    │
                    ├─► countdown = 5
                    └─► loadAll()
```

---

## 五、API 层详解（api.ts）

### 5.1 通用请求函数

```tsx
const API_BASE = import.meta.env.VITE_API_URL || '';

// GET 请求
async function fetchJ<T>(url: string): Promise<T> {
  const res = await fetch(url, { cache: 'no-store' });
  if (!res.ok) throw new Error(String(res.status));
  return res.json();
}

// POST 请求
async function postJ<T>(url: string, data: unknown): Promise<T> {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });
  return res.json();
}
```

| 函数 | 用途 | 示例 |
|------|------|------|
| `fetchJ<T>` | GET 请求，返回 JSON | `api.liveStatus()` |
| `postJ<T>` | POST 请求，发送 JSON | `api.setModel('taizi', 'gpt-4')` |

---

### 5.2 API 接口定义

```tsx
export const api = {
  // ── 核心数据 ──
  liveStatus: () => fetchJ<LiveStatus>(`${API_BASE}/api/live-status`),
  agentConfig: () => fetchJ<AgentConfig>(`${API_BASE}/api/agent-config`),
  officialsStats: () => fetchJ<OfficialsData>(`${API_BASE}/api/officials-stats`),
  morningBrief: () => fetchJ<MorningBrief>(`${API_BASE}/api/morning-brief`),

  // ── 操作类 ──
  setModel: (agentId: string, model: string) =>
    postJ<ActionResult>(`${API_BASE}/api/set-model`, { agentId, model }),

  taskAction: (taskId: string, action: string, reason: string) =>
    postJ<ActionResult>(`${API_BASE}/api/task-action`, { taskId, action, reason }),

  // ── 朝堂议政 ──
  courtDiscussStart: (topic: string, officials: string[]) =>
    postJ<CourtDiscussResult>(`${API_BASE}/api/court-discuss/start`, { topic, officials }),
};
```

---

### 5.3 类型定义（部分）

```tsx
// 任务类型
export interface Task {
  id: string;           // 任务 ID，如 "JJC-20260319-001"
  title: string;        // 任务标题
  state: string;        // 状态：Inbox, Taizi, Zhongshu, ...
  org: string;          // 当前执行部门
  now: string;          // 当前进展描述
  eta: string;          // 预计完成时间
  block: string;        // 阻塞项
  ac: string;           // 验收标准
  output: string;       // 输出内容
  heartbeat: Heartbeat; // 心跳状态
  flow_log: FlowEntry[];// 流转记录
  todos: TodoItem[];    // 待办列表
}

// 心跳状态
export interface Heartbeat {
  status: 'active' | 'warn' | 'stalled' | 'unknown' | 'idle';
  label: string;
}

// 流转记录
export interface FlowEntry {
  at: string;      // 时间
  from: string;    // 来源状态
  to: string;      // 目标状态
  remark: string;  // 备注
}
```

---

## 六、业务常量详解

### 6.1 流水线定义（PIPE）

```tsx
export const PIPE = [
  { key: 'Inbox',    dept: '皇上',   icon: '👑', action: '下旨' },
  { key: 'Taizi',    dept: '太子',   icon: '🤴', action: '分拣' },
  { key: 'Zhongshu', dept: '中书省', icon: '📜', action: '起草' },
  { key: 'Menxia',   dept: '门下省', icon: '🔍', action: '审议' },
  { key: 'Assigned', dept: '尚书省', icon: '📮', action: '派发' },
  { key: 'Doing',    dept: '六部',   icon: '⚙️', action: '执行' },
  { key: 'Review',   dept: '尚书省', icon: '🔎', action: '汇总' },
  { key: 'Done',     dept: '回奏',   icon: '✅', action: '完成' },
] as const;
```

**流程图**:
```
皇上下旨 → 太子分拣 → 中书省起草 → 门下省审议
    ↓
尚书省派发 → 六部执行 → 尚书省汇总 → 回奏完成
```

### 6.2 部门颜色映射

```tsx
export const DEPT_COLOR: Record<string, string> = {
  '太子': '#e8a040',    // 橙色
  '中书省': '#a07aff',  // 紫色
  '门下省': '#6a9eff',  // 蓝色
  '尚书省': '#6aef9a',  // 绿色
  '礼部': '#f5c842',    // 金色
  '户部': '#ff9a6a',    // 橙红
  '兵部': '#ff5270',    // 红色
  '刑部': '#cc4444',    // 深红
  '工部': '#44aaff',    // 天蓝
  '吏部': '#9b59b6',    // 紫色
};
```

### 6.3 Tab 定义

```tsx
export const TAB_DEFS = [
  { key: 'edicts',    label: '旨意看板', icon: '📜' },
  { key: 'court',     label: '朝堂议政', icon: '🏛️' },
  { key: 'monitor',   label: '省部调度', icon: '🔌' },
  { key: 'officials', label: '官员总览', icon: '👔' },
  { key: 'models',    label: '模型配置', icon: '🤖' },
  { key: 'skills',    label: '技能配置', icon: '🎯' },
  { key: 'sessions',  label: '小任务',   icon: '💬' },
  { key: 'memorials', label: '奏折阁',   icon: '📜' },
  { key: 'templates', label: '旨库',     icon: '📋' },
  { key: 'morning',   label: '天下要闻', icon: '🌅' },
];
```

---

## 七、组件渲染流程图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           App 组件渲染流程                                   │
└─────────────────────────────────────────────────────────────────────────────┘

App()
  │
  ├─► useStore 订阅状态
  │     ├─► activeTab
  │     ├─► liveStatus
  │     └─► countdown
  │
  ├─► useEffect 启动轮询
  │     └─► startPolling()
  │           └─► 每 5 秒 loadAll()
  │
  └─► return JSX
        │
        ├─► <div className="hdr">          // 头部
        │     ├─► Logo + 同步状态
        │     └─► 刷新按钮 + 倒计时
        │
        ├─► <div className="tabs">         // Tab 导航
        │     └─► TAB_DEFS.map(...)
        │
        ├─► 面板内容（根据 activeTab）
        │     ├─► 'edicts'   → <EdictBoard />
        │     ├─► 'court'    → <CourtDiscussion />
        │     ├─► 'monitor'  → <MonitorPanel />
        │     ├─�� 'officials'→ <OfficialPanel />
        │     ├─► 'models'   → <ModelConfig />
        │     └─► ...
        │
        └─► 弹窗层
              ├─► <TaskModal />      // 任务详情
              ├─► <Toaster />        // Toast 消息
              └─► <CourtCeremony />  // 仪式动画
```

---

## 八、数据流向图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              数据流向                                        │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────┐      HTTP GET       ┌──────────────┐
│   前端       │ ──────────────────► │  server.py   │
│  (React)     │                     │  (Port 7891) │
│              │ ◄────────────────── │              │
│              │      JSON           │              │
└──────┬───────┘                     └──────┬───────┘
       │                                    │
       │ useStore                           │ 读取
       │                                    │
       ▼                                    ▼
┌──────────────┐                     ┌──────────────┐
│  Zustand     │                     │  data/*.json │
│   Store      │                     │              │
│              │                     │ ├─ tasks_source.json
│ ├─ liveStatus│                     │ ├─ live_status.json
│ ├─ agentConfig│                    │ ├─ agent_config.json
│ └─ ...       │                     │ └─ ...       │
└──────┬───────┘                     └──────────────┘
       │
       │ 订阅渲染
       │
       ▼
┌──────────────┐
│  UI 组件     │
│              │
│ ├─ EdictBoard
│ ├─ MonitorPanel
│ └─ ...       │
└──────────────┘
```

---

## 九、核心要点总结

| 概念 | 说明 |
|------|------|
| **React 18** | 使用 `createRoot` API，支持并发特性 |
| **Zustand** | 轻量级状态管理，无 Provider，代码简洁 |
| **HTTP 轮询** | 每 5 秒请求一次 `/api/live-status`，无 WebSocket |
| **条件渲染** | 根据 `activeTab` 显示不同面板组件 |
| **TypeScript** | 完整类型定义，减少运行时错误 |
| **原子化 CSS** | 使用 Tailwind + 自定义 CSS 变量 |
| **模块化组件** | 每个 Tab 对应一个独立组件 |

---

## 十、关键技术点速查

| 技术 | 用途 | 文件 |
|------|------|------|
| `createRoot` | React 18 渲染 | main.tsx |
| `useStore(selector)` | Zustand 状态订阅 | App.tsx, 各组件 |
| `useEffect` | 副作用处理 | App.tsx (轮询) |
| `fetchJ<T>` | 泛型 GET 请求 | api.ts |
| `postJ<T>` | 泛型 POST 请求 | api.ts |
| `Record<K, V>` | TypeScript 对象类型 | store.ts, api.ts |
| `as const` | 常量断言 | store.ts (PIPE) |

---

## 十一、NPM 命令说明

```bash
# 开发模式（热更新）
npm run dev
# 启动 Vite 开发服务器，访问 http://localhost:5173

# 构建生产版本
npm run build
# 1. tsc -b    → TypeScript 类型检查
# 2. vite build → 打包到 dist/

# 预览生产构建
npm run preview
# 启动静态文件服务器，预览构建结果
```

| 命令 | 作用 |
|------|------|
| `npm run dev` | 启动开发服务器，支持热更新 |
| `npm run build` | 构建生产版本，输出到 `dist/` |
| `npm run preview` | 本地预览生产构建 |
