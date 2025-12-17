#!/bin/sh
# ============================================================
# Xray + Tor 安装脚本 (FreeBSD / serv00 / hostuno 无root版)
# 特点: 用户级安装，无需root权限
# ============================================================

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 目录配置
HOME_DIR="$HOME"
INSTALL_DIR="$HOME_DIR/xray-tor"
BIN_DIR="$INSTALL_DIR/bin"
CONFIG_DIR="$INSTALL_DIR/config"
LOG_DIR="$INSTALL_DIR/logs"
TOR_DATA_DIR="$INSTALL_DIR/tor-data"
PID_DIR="$INSTALL_DIR/run"

# 默认端口 (serv00需要在面板开放)
DEFAULT_XRAY_PORT=10086
TOR_SOCKS_PORT=19050
TOR_DNS_PORT=15353

log_info() { echo "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo "${RED}[ERROR]${NC} $1"; }
log_step() { echo "${CYAN}[STEP]${NC} $1"; }

# 检测系统架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        amd64|x86_64) 
            XRAY_ARCH="64"
            TOR_ARCH="amd64"
            ;;
        aarch64|arm64)
            XRAY_ARCH="arm64-v8a"
            TOR_ARCH="arm64"
            ;;
        *)
            log_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    log_info "架构: $ARCH"
}

# 创建目录结构
create_directories() {
    log_step "创建目录结构..."
    mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$TOR_DATA_DIR" "$PID_DIR"
    chmod 700 "$TOR_DATA_DIR"
}

# 下载 Xray
download_xray() {
    log_step "下载 Xray..."
    
    # 获取最新版本
    XRAY_VERSION=$(fetch -qo - "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/' || echo "1.8.24")
    
    XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-freebsd-${XRAY_ARCH}.zip"
    
    log_info "下载 Xray v${XRAY_VERSION}..."
    
    cd /tmp
    rm -f Xray-freebsd-*.zip xray geoip.dat geosite.dat
    
    if command -v fetch >/dev/null 2>&1; then
        fetch -o xray.zip "$XRAY_URL" || { log_error "下载失败"; exit 1; }
    elif command -v curl >/dev/null 2>&1; then
        curl -L -o xray.zip "$XRAY_URL" || { log_error "下载失败"; exit 1; }
    else
        log_error "需要 fetch 或 curl"
        exit 1
    fi
    
    unzip -o xray.zip xray geoip.dat geosite.dat
    mv xray "$BIN_DIR/"
    mv geoip.dat geosite.dat "$CONFIG_DIR/" 2>/dev/null || true
    chmod +x "$BIN_DIR/xray"
    rm -f xray.zip
    
    log_info "Xray 安装完成: $BIN_DIR/xray"
}

# 下载预编译的 Tor (或提供编译指导)
download_tor() {
    log_step "配置 Tor..."
    
    # 尝试使用系统 tor (如果可用)
    if command -v tor >/dev/null 2>&1; then
        TOR_BIN=$(command -v tor)
        log_info "使用系统 Tor: $TOR_BIN"
        return
    fi
    
    # 尝试下载预编译版本
    TOR_BIN="$BIN_DIR/tor"
    
    # Tor Browser 包含静态编译的 tor
    log_warn "系统没有 Tor，尝试下载..."
    
    # 使用 Tor 项目的 expert bundle
    TOR_VERSION="13.0.9"
    
    cd /tmp
    
    # 尝试从多个源下载
    TOR_DOWNLOAD_SUCCESS=0
    
    # 方法1: 尝试使用系统包管理器安装到用户目录
    if command -v pkg >/dev/null 2>&1; then
        log_info "尝试通过 pkg 检查 tor..."
        # serv00 可能允许某些包
    fi
    
    # 方法2: 从源码编译 (作为备选)
    if [ ! -f "$TOR_BIN" ]; then
        log_warn "无法自动下载 Tor，请手动安装:"
        echo ""
        echo "选项1 - 联系管理员安装 tor"
        echo "选项2 - 从源码编译:"
        echo "  cd /tmp"
        echo "  fetch https://www.torproject.org/dist/tor-0.4.8.10.tar.gz"
        echo "  tar xzf tor-0.4.8.10.tar.gz"
        echo "  cd tor-0.4.8.10"
        echo "  ./configure --prefix=$INSTALL_DIR --disable-asciidoc"
        echo "  make && make install"
        echo ""
        echo "选项3 - 使用现有的 Tor SOCKS 代理:"
        read -p "输入现有 Tor SOCKS 地址 (如 127.0.0.1:9050，留空跳过): " EXISTING_TOR
        
        if [ -n "$EXISTING_TOR" ]; then
            # 解析地址和端口
            TOR_HOST=$(echo "$EXISTING_TOR" | cut -d: -f1)
            TOR_SOCKS_PORT=$(echo "$EXISTING_TOR" | cut -d: -f2)
            USE_EXTERNAL_TOR=1
            log_info "使用外部 Tor: $TOR_HOST:$TOR_SOCKS_PORT"
            return
        fi
        
        # 创建一个假的 tor 脚本提示用户
        cat > "$TOR_BIN" << 'TORWRAP'
#!/bin/sh
echo "Tor 未安装，请按照说明手动安装"
exit 1
TORWRAP
        chmod +x "$TOR_BIN"
        TOR_NOT_INSTALLED=1
    fi
}

# 配置 Tor
configure_tor() {
    log_step "生成 Tor 配置..."
    
    if [ "$USE_EXTERNAL_TOR" = "1" ]; then
        log_info "使用外部 Tor，跳过本地配置"
        return
    fi
    
    cat > "$CONFIG_DIR/torrc" << EOF
# Tor 配置 (用户级)
SocksPort 127.0.0.1:${TOR_SOCKS_PORT}
DNSPort 127.0.0.1:${TOR_DNS_PORT}
DataDirectory ${TOR_DATA_DIR}
Log notice file ${LOG_DIR}/tor.log
AutomapHostsOnResolve 1
AutomapHostsSuffixes .onion
# 禁用需要特权的功能
AvoidDiskWrites 1
EOF

    log_info "Tor 配置: $CONFIG_DIR/torrc"
}

# 生成 UUID
generate_uuid() {
    # FreeBSD 方式
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        # 手动生成
        od -x /dev/urandom | head -1 | awk '{print $2$3"-"$4"-"$5"-"$6"-"$7$8$9}'
    fi
}

# 配置 Xray
configure_xray() {
    log_step "配置 Xray..."
    
    echo ""
    echo "${CYAN}=== Xray 配置 ===${NC}"
    
    # 端口 (serv00 需要在面板开放)
    echo "${YELLOW}注意: serv00/hostuno 需要在控制面板开放端口!${NC}"
    read -p "Xray 端口 [默认 $DEFAULT_XRAY_PORT]: " XRAY_PORT
    XRAY_PORT=${XRAY_PORT:-$DEFAULT_XRAY_PORT}
    
    # 协议
    echo "协议: 1) VLESS  2) VMess  3) Shadowsocks"
    read -p "选择 [1-3, 默认 1]: " PROTO
    PROTO=${PROTO:-1}
    
    # 路由模式
    echo "路由: 1) 智能分流(.onion走Tor)  2) 全流量走Tor"
    read -p "选择 [1-2, 默认 1]: " MODE
    MODE=${MODE:-1}
    
    USER_UUID=$(generate_uuid)
    
    # 获取服务器IP
    SERVER_IP=$(fetch -qo - https://ifconfig.me 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
    
    # TOR 地址
    if [ "$USE_EXTERNAL_TOR" = "1" ]; then
        TOR_ADDR="$TOR_HOST"
        TOR_PORT="$TOR_SOCKS_PORT"
    else
        TOR_ADDR="127.0.0.1"
        TOR_PORT="$TOR_SOCKS_PORT"
    fi
    
    # 构建入站配置
    case $PROTO in
        1)
            PROTO_NAME="VLESS"
            INBOUND="{\"port\":$XRAY_PORT,\"protocol\":\"vless\",\"settings\":{\"clients\":[{\"id\":\"$USER_UUID\"}],\"decryption\":\"none\"},\"streamSettings\":{\"network\":\"tcp\"}}"
            ;;
        2)
            PROTO_NAME="VMess"
            INBOUND="{\"port\":$XRAY_PORT,\"protocol\":\"vmess\",\"settings\":{\"clients\":[{\"id\":\"$USER_UUID\",\"alterId\":0}]},\"streamSettings\":{\"network\":\"ws\",\"wsSettings\":{\"path\":\"/ws\"}}}"
            ;;
        3)
            PROTO_NAME="Shadowsocks"
            SS_PASS=$(head -c 16 /dev/urandom | base64 | head -c 22)
            INBOUND="{\"port\":$XRAY_PORT,\"protocol\":\"shadowsocks\",\"settings\":{\"method\":\"2022-blake3-aes-128-gcm\",\"password\":\"$SS_PASS\",\"network\":\"tcp,udp\"}}"
            USER_UUID="$SS_PASS"
            ;;
    esac
    
    # 构建路由规则
    if [ "$MODE" = "2" ]; then
        RULES="[{\"type\":\"field\",\"network\":\"tcp,udp\",\"outboundTag\":\"tor-out\"}]"
        MODE_NAME="全流量Tor"
    else
        RULES="[{\"type\":\"field\",\"domain\":[\"regexp:\\\\.onion$\"],\"outboundTag\":\"tor-out\"},{\"type\":\"field\",\"network\":\"tcp,udp\",\"outboundTag\":\"direct\"}]"
        MODE_NAME="智能分流"
    fi
    
    # 生成配置文件
    cat > "$CONFIG_DIR/xray.json" << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "${LOG_DIR}/xray-access.log",
    "error": "${LOG_DIR}/xray-error.log"
  },
  "inbounds": [$INBOUND],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "tor-out", "protocol": "socks", "settings": {"servers": [{"address": "$TOR_ADDR", "port": $TOR_PORT}]}},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": $RULES
  }
}
EOF

    # 保存连接信息
    cat > "$CONFIG_DIR/connection.txt" << EOF
===== Xray + Tor 连接信息 =====
协议: $PROTO_NAME
服务器: $SERVER_IP
端口: $XRAY_PORT
UUID/密码: $USER_UUID
路由模式: $MODE_NAME
Tor SOCKS: $TOR_ADDR:$TOR_PORT
==============================
EOF

    echo ""
    echo "${GREEN}配置完成!${NC}"
    cat "$CONFIG_DIR/connection.txt"
}

# 创建启动脚本
create_start_script() {
    log_step "创建管理脚本..."
    
    cat > "$BIN_DIR/xray-tor" << SCRIPT
#!/bin/sh
# Xray + Tor 管理脚本

INSTALL_DIR="$INSTALL_DIR"
BIN_DIR="$BIN_DIR"
CONFIG_DIR="$CONFIG_DIR"
LOG_DIR="$LOG_DIR"
PID_DIR="$PID_DIR"
TOR_BIN="${TOR_BIN:-$BIN_DIR/tor}"
USE_EXTERNAL_TOR="${USE_EXTERNAL_TOR:-0}"

start_tor() {
    if [ "\$USE_EXTERNAL_TOR" = "1" ]; then
        echo "使用外部 Tor，无需启动"
        return 0
    fi
    
    if [ -f "\$PID_DIR/tor.pid" ] && kill -0 \$(cat "\$PID_DIR/tor.pid") 2>/dev/null; then
        echo "Tor 已在运行"
        return 0
    fi
    
    echo "启动 Tor..."
    "\$TOR_BIN" -f "\$CONFIG_DIR/torrc" &
    echo \$! > "\$PID_DIR/tor.pid"
    sleep 5
    echo "Tor 已启动"
}

start_xray() {
    if [ -f "\$PID_DIR/xray.pid" ] && kill -0 \$(cat "\$PID_DIR/xray.pid") 2>/dev/null; then
        echo "Xray 已在运行"
        return 0
    fi
    
    echo "启动 Xray..."
    "\$BIN_DIR/xray" run -config "\$CONFIG_DIR/xray.json" > "\$LOG_DIR/xray.log" 2>&1 &
    echo \$! > "\$PID_DIR/xray.pid"
    sleep 2
    echo "Xray 已启动"
}

stop_tor() {
    if [ -f "\$PID_DIR/tor.pid" ]; then
        kill \$(cat "\$PID_DIR/tor.pid") 2>/dev/null
        rm -f "\$PID_DIR/tor.pid"
        echo "Tor 已停止"
    fi
}

stop_xray() {
    if [ -f "\$PID_DIR/xray.pid" ]; then
        kill \$(cat "\$PID_DIR/xray.pid") 2>/dev/null
        rm -f "\$PID_DIR/xray.pid"
        echo "Xray 已停止"
    fi
}

status() {
    echo "=== 服务状态 ==="
    if [ -f "\$PID_DIR/xray.pid" ] && kill -0 \$(cat "\$PID_DIR/xray.pid") 2>/dev/null; then
        echo "Xray: 运行中 (PID: \$(cat \$PID_DIR/xray.pid))"
    else
        echo "Xray: 已停止"
    fi
    
    if [ "\$USE_EXTERNAL_TOR" = "1" ]; then
        echo "Tor: 外部 ($TOR_ADDR:$TOR_PORT)"
    elif [ -f "\$PID_DIR/tor.pid" ] && kill -0 \$(cat "\$PID_DIR/tor.pid") 2>/dev/null; then
        echo "Tor: 运行中 (PID: \$(cat \$PID_DIR/tor.pid))"
    else
        echo "Tor: 已停止"
    fi
}

case "\$1" in
    start)
        start_tor
        start_xray
        ;;
    stop)
        stop_xray
        stop_tor
        ;;
    restart)
        stop_xray
        stop_tor
        sleep 2
        start_tor
        start_xray
        ;;
    status)
        status
        ;;
    log)
        tail -50 "\$LOG_DIR/xray.log" 2>/dev/null
        ;;
    tor-log)
        tail -50 "\$LOG_DIR/tor.log" 2>/dev/null
        ;;
    info)
        cat "\$CONFIG_DIR/connection.txt" 2>/dev/null
        ;;
    test)
        echo "测试 Tor 连接..."
        if command -v curl >/dev/null 2>&1; then
            curl -s --socks5-hostname 127.0.0.1:$TOR_SOCKS_PORT https://check.torproject.org/api/ip
        else
            fetch -qo - --socks5-hostname 127.0.0.1:$TOR_SOCKS_PORT https://check.torproject.org/api/ip 2>/dev/null || echo "需要 curl"
        fi
        ;;
    *)
        echo "用法: xray-tor {start|stop|restart|status|log|tor-log|info|test}"
        ;;
esac
SCRIPT

    chmod +x "$BIN_DIR/xray-tor"
    
    # 添加到 PATH
    SHELL_RC="$HOME/.profile"
    if [ -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bashrc"
    elif [ -f "$HOME/.zshrc" ]; then
        SHELL_RC="$HOME/.zshrc"
    fi
    
    if ! grep -q "$BIN_DIR" "$SHELL_RC" 2>/dev/null; then
        echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$SHELL_RC"
        log_info "已添加 $BIN_DIR 到 PATH"
    fi
    
    log_info "管理脚本: $BIN_DIR/xray-tor"
}

# 创建 cron 任务保持运行
setup_cron() {
    log_step "配置 cron 保活..."
    
    # 创建保活脚本
    cat > "$BIN_DIR/keepalive.sh" << KEEPALIVE
#!/bin/sh
# 检查并重启服务

PID_DIR="$PID_DIR"
BIN_DIR="$BIN_DIR"

# 检查 Xray
if [ ! -f "\$PID_DIR/xray.pid" ] || ! kill -0 \$(cat "\$PID_DIR/xray.pid") 2>/dev/null; then
    "\$BIN_DIR/xray-tor" start >/dev/null 2>&1
fi
KEEPALIVE
    chmod +x "$BIN_DIR/keepalive.sh"
    
    # 添加 cron 任务
    CRON_JOB="*/5 * * * * $BIN_DIR/keepalive.sh"
    
    (crontab -l 2>/dev/null | grep -v "keepalive.sh"; echo "$CRON_JOB") | crontab -
    
    log_info "已添加 cron 任务 (每5分钟检查)"
}

# 显示完成信息
show_completion() {
    echo ""
    echo "${GREEN}============================================${NC}"
    echo "${GREEN}      安装完成!${NC}"
    echo "${GREEN}============================================${NC}"
    echo ""
    echo "${CYAN}目录结构:${NC}"
    echo "  安装目录: $INSTALL_DIR"
    echo "  配置文件: $CONFIG_DIR/xray.json"
    echo "  日志目录: $LOG_DIR"
    echo ""
    echo "${CYAN}管理命令:${NC}"
    echo "  $BIN_DIR/xray-tor start    - 启动服务"
    echo "  $BIN_DIR/xray-tor stop     - 停止服务"
    echo "  $BIN_DIR/xray-tor status   - 查看状态"
    echo "  $BIN_DIR/xray-tor info     - 查看连接信息"
    echo ""
    echo "${YELLOW}重要提示:${NC}"
    echo "  1. 在 serv00/hostuno 面板开放端口: $XRAY_PORT"
    echo "  2. 重新登录 SSH 使 PATH 生效，或运行: source $SHELL_RC"
    if [ "$TOR_NOT_INSTALLED" = "1" ]; then
        echo "  3. ${RED}Tor 未安装，请按上述说明手动安装${NC}"
    fi
    echo ""
    echo "${GREEN}立即启动:${NC} $BIN_DIR/xray-tor start"
    echo ""
}

# 主函数
main() {
    echo ""
    echo "${CYAN}============================================${NC}"
    echo "${CYAN}  Xray + Tor 安装 (FreeBSD/serv00/hostuno)${NC}"
    echo "${CYAN}============================================${NC}"
    echo ""
    
    detect_arch
    create_directories
    download_xray
    download_tor
    configure_tor
    configure_xray
    create_start_script
    setup_cron
    show_completion
}

main "$@"
