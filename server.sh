#!/usr/bin/env bash

# ==============================================================================
# 📖 TurboFieldfareServer 管理脚本
#
# 常用命令:
#    - 启动服务: ./server.sh start   (或直接 ./server.sh)
#    - 停止服务: ./server.sh stop
#    - 重启服务: ./server.sh restart
#    - 运行状态: ./server.sh status
#    - 实时日志: ./server.sh logs    (按 Ctrl + C 退出查看)
#    - 帮助信息: ./server.sh help
#
# ⚙️ TurboFieldfareServer 运行配置区
# ==============================================================================

# 1. 监听端口 (默认: 1235)
PORT=1235

# 2. 最大上下文长度 (支持: 4096, 8192, 16384, 32768, 65536)
#    - 16384 (16K): 默认值，日常多轮图文对话与低内存占用平衡
#    - 32768 (32K): 推荐值，适合长文本分析与大量图片输入
#    - 65536 (64K): 极限值，适合超长代码库/长文档深度分析
MAX_CONTEXT=32768

# 3. 专家缓存槽位数 (每层保留专家数，支持: 8, 16, 24, 32)
#    - 16: 默认值 (约占 2 GB 内存)
#    - 24: 推荐值 (约占 3~3.5 GB 内存，大幅减少磁盘读取)
#    - 32: 最大缓存 (约占 4~4.5 GB 内存，极高内存命中率，最少磁盘 I/O)
EXPERT_CACHE_SLOTS=24

# 4. 专家缓存淘汰策略 (支持: lfu, lru)
EXPERT_CACHE_POLICY="lfu"

# 5. 分块 Prompt 预热 (支持: on, off；开启后显著加速 Prompt/图片处理)
PREFILL="on"

# 6. Prefill 分块大小 (支持: 32, 64, 128, 256, auto)
#    - auto (或 256): 推荐值 (v0.7.2+)，服务端自动上限 256，长 Prompt 预热提速 ~16%，仅多占 ~16MB 显存
PREFILL_CHUNK_TOKENS="auto"

# 7. 视觉模块常驻策略 (支持: on-demand 按需调度, keep-ready 始终常驻显存)
VISION_RESIDENCY="on-demand"

# 8. KV 缓存复用模式 (支持: single-prefix 开启单前缀复用, off 关闭)
PROMPT_CACHE_MODE="single-prefix"

# 9. 路径与本体配置 (默认指向用户主目录下的本体 ~/turbo-fieldfare)
TURBO_DIR="${TURBO_FIELDFARE_DIR:-$HOME/turbo-fieldfare}"
PROJECT_DIR="$TURBO_DIR"
MODEL_PATH="$PROJECT_DIR/scratch/gemma4.gturbo"
LOG_FILE="$HOME/Library/Logs/turbo-fieldfare.log"
PID_FILE="/tmp/turbo_fieldfare_server.pid"
BINARY="$PROJECT_DIR/.build/release/TurboFieldfareServer"
OFFICIAL_REPO_URL="https://github.com/drumih/turbo-fieldfare.git"

# ==============================================================================

# 检查进程是否真实存活
is_running() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# 确保本体项目存在 (支持新 Mac 一键克隆)
ensure_repo() {
    if [ ! -d "$TURBO_DIR/.git" ]; then
        echo "⚠️  未在 $TURBO_DIR 检测到 TurboFieldfare 仓库。"
        echo "🌐 正在从官方源自动克隆到: $TURBO_DIR ..."
        mkdir -p "$TURBO_DIR"
        git clone "$OFFICIAL_REPO_URL" "$TURBO_DIR"
        if [ $? -ne 0 ]; then
            echo "❌ 克隆官方仓库失败，请检查网络连接。"
            exit 1
        fi
        echo "✅ 克隆完成！"
    fi
}

start() {
    if is_running; then
        echo "⚠️  TurboFieldfareServer 已经在后台运行中 (PID: $(cat "$PID_FILE"), 端口: $PORT)"
        exit 0
    fi

    # 1. 确保本体目录存在
    ensure_repo

    # 2. 前置检查：模型文件是否存在
    if [ ! -e "$MODEL_PATH" ]; then
        echo "❌ 错误: 未找到模型文件/目录: $MODEL_PATH"
        echo "💡 请先在本体目录下载模型权重，例如执行:"
        echo "   cd $TURBO_DIR && swift run -c release TurboFieldfareRepack --output scratch/gemma4.gturbo"
        exit 1
    fi

    # 2. 确保日志所在目录存在
    mkdir -p "$(dirname "$LOG_FILE")"

    # 3. 检查二进制是否存在，若无则自动编译
    if [ ! -f "$BINARY" ]; then
        echo "📦 正在编译发布版本 TurboFieldfareServer..."
        (cd "$PROJECT_DIR" && swift build -c release --product TurboFieldfareServer)
        if [ $? -ne 0 ] || [ ! -f "$BINARY" ]; then
            echo "❌ 编译失败，请检查编译输出与环境设置。"
            exit 1
        fi
    fi

    echo "🚀 正在后台启动 TurboFieldfare 服务..."
    echo "   ├─ 端口: $PORT"
    echo "   ├─ 上下文: $MAX_CONTEXT"
    echo "   ├─ 专家缓存槽位: $EXPERT_CACHE_SLOTS (策略: $EXPERT_CACHE_POLICY)"
    echo "   ├─ Prefill 分块: $PREFILL_CHUNK_TOKENS"
    echo "   └─ 模型路径: $MODEL_PATH"

    nohup "$BINARY" \
        --model "$MODEL_PATH" \
        --port "$PORT" \
        --max-context "$MAX_CONTEXT" \
        --expert-cache-slots "$EXPERT_CACHE_SLOTS" \
        --expert-cache-policy "$EXPERT_CACHE_POLICY" \
        --prefill "$PREFILL" \
        --prefill-chunk-tokens "$PREFILL_CHUNK_TOKENS" \
        --vision-residency "$VISION_RESIDENCY" \
        --prompt-cache-mode "$PROMPT_CACHE_MODE" > "$LOG_FILE" 2>&1 &

    local pid=$!
    echo "$pid" > "$PID_FILE"
    
    # 等待并探测进程就绪
    echo -n "⏳ 等待服务初始化..."
    local waited=0
    local ready=0
    while [ $waited -lt 10 ]; do
        sleep 1
        waited=$((waited + 1))
        echo -n "."
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        # 尝试通过 HTTP 探针确认就绪
        if curl -s -m 1 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
            ready=1
            break
        fi
    done
    echo ""

    if is_running; then
        echo "✅ 服务启动成功！"
        echo "📍 API Base URL: http://127.0.0.1:$PORT/v1"
        echo "📄 运行日志: $LOG_FILE"
        echo "🧪 测试命令:"
        echo "   curl http://127.0.0.1:$PORT/v1/chat/completions \\"
        echo "     -H 'Content-Type: application/json' \\"
        echo "     -d '{\"model\":\"gemma-4-26b-a4b-it\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}'"
    else
        echo "❌ 服务未能正常运行，请查看最后 20 行日志排查错误:"
        echo "----------------------------------------"
        tail -n 20 "$LOG_FILE"
        echo "----------------------------------------"
        rm -f "$PID_FILE"
        exit 1
    fi
}

stop() {
    local pid=""
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null)
    fi

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "🛑 正在停止 TurboFieldfareServer (PID: $pid)..."
        kill "$pid" 2>/dev/null
        
        # 优雅等待最多 5 秒
        local count=0
        while kill -0 "$pid" 2>/dev/null && [ $count -lt 10 ]; do
            sleep 0.5
            count=$((count + 1))
        done

        if kill -0 "$pid" 2>/dev/null; then
            echo "⚠️  服务未在预期内退出，正在强制终止 (kill -9)..."
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$PID_FILE"
        echo "✅ 服务已成功停止。"
        return
    fi

    # 兜底清理可能失联的残留进程
    if pgrep -f "$BINARY" >/dev/null 2>&1; then
        echo "🛑 正在清理残留的 TurboFieldfareServer 进程..."
        pkill -f "$BINARY" 2>/dev/null
        sleep 1
        echo "✅ 残留进程已清理。"
    else
        echo "⚠️  未发现正在运行的 TurboFieldfareServer 服务。"
    fi
    rm -f "$PID_FILE"
}

status() {
    if is_running; then
        local pid
        pid=$(cat "$PID_FILE")
        echo "🟢 TurboFieldfareServer 正在运行中 (PID: $pid)"
        echo "   ├─ 端口: $PORT"
        echo "   ├─ 上下文容量: $MAX_CONTEXT"
        echo "   ├─ 专家缓存槽位: $EXPERT_CACHE_SLOTS ($EXPERT_CACHE_POLICY)"
        echo "   ├─ Prefill 分块: $PREFILL_CHUNK_TOKENS"
        echo "   └─ API 接口: http://127.0.0.1:$PORT/v1"
        
        # 尝试进行健康检查
        if curl -s -m 2 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
            echo "   └─ 健康状态: 响应正常 (HTTP 200)"
        else
            echo "   └─ 健康状态: 启动中或正在加载权重..."
        fi
    else
        echo "🔴 TurboFieldfareServer 未在运行"
    fi
}

logs() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "⚠️  日志文件尚不存在: $LOG_FILE"
        exit 0
    fi
    echo "📋 正在跟踪实时运行日志: $LOG_FILE (按 Ctrl + C 退出)..."
    tail -f "$LOG_FILE"
}

help() {
    echo "📖 TurboFieldfareServer 管理脚本使用说明:"
    echo "   $0 start    - 启动后台服务 (默认)"
    echo "   $0 stop     - 优雅停止服务"
    echo "   $0 restart  - 重启服务"
    echo "   $0 status   - 查看当前运行状态与健康检查"
    echo "   $0 logs     - 查看实时输出日志"
    echo "   $0 help     - 显示本帮助信息"
}

case "${1:-start}" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 1; start ;;
    status)  status ;;
    logs)    logs ;;
    help|--help|-h) help ;;
    *)       
        echo "⚠️  未知指令: $1"
        help
        exit 1
        ;;
esac
