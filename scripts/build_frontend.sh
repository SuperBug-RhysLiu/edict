#!/bin/bash
# ══════════════════════════════════════════════════════════════
# 三省六部 · React 前端构建脚本
# ══════════════════════════════════════════════════════════════
# 用法: bash scripts/build_frontend.sh
#
# 前置要求:
#   - Node.js 18+
#   - npm
#
# 输出:
#   dashboard/dist/ - 构建产物
# ══════════════════════════════════════════════════════════════

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  🏗️  三省六部 · 前端构建                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# 检查 Node.js
if ! command -v node &>/dev/null; then
    warn "未找到 Node.js"
    echo ""
    echo "请先安装 Node.js 18+:"
    echo "  macOS:  brew install node"
    echo "  或访问: https://nodejs.org/"
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    warn "Node.js 版本过低 (当前: v$(node -v)，需要: 18+)"
    exit 1
fi

info "Node.js 版本: $(node -v)"

# 检查前端目录
FRONTEND_DIR="$REPO_DIR/edict/frontend"
if [ ! -f "$FRONTEND_DIR/package.json" ]; then
    warn "未找到 edict/frontend/package.json"
    exit 1
fi

# 安装依赖
info "安装 npm 依赖..."
cd "$FRONTEND_DIR"
npm install --silent 2>/dev/null || npm install

# 构建
info "构建 React 应用..."
npm run build 2>/dev/null

# 检查构建结果
cd "$REPO_DIR"
if [ -f "$REPO_DIR/dashboard/dist/index.html" ]; then
    echo ""
    log "前端构建完成！"
    echo ""
    echo "构建产物: dashboard/dist/"
    echo ""
    echo "启动看板:"
    echo "  python3 dashboard/server.py"
    echo "  open http://127.0.0.1:7891"
else
    warn "前端构建可能失败，请检查控制台输出"
    exit 1
fi
