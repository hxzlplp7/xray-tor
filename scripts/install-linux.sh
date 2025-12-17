#!/bin/bash
# ============================================================
# Xray + Tor 一键安装脚本 (Linux VPS 版)
# 支持: Debian/Ubuntu, CentOS/RHEL/Fedora, Arch Linux
# 功能: 普通网站走Xray, 暗网走Tor, 或全流量走Tor
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置变量
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_LOG_DIR="/var/log/xray"
TOR_CONFIG_DIR="/etc/tor"
XRAY_BIN="/usr/local/bin/xray"
MANAGEMENT_SCRIPT="/usr/local/bin/xray-tor"
DEFAULT_XRAY_PORT=10086
DEFAULT_TOR_SOCKS_PORT=9050

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "需要 root 权限，请使用 sudo"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    else
        OS="unknown"
    fi
    log_info "系统: $OS"
}

detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) XRAY_ARCH="64" ;;
        aarch64) XRAY_ARCH="arm64-v8a" ;;
        *) log_error "不支持: $ARCH"; exit 1 ;;
    esac
}

install_dependencies() {
    log_step "安装依赖..."
    case $OS in
        ubuntu|debian)
            apt-get update -y && apt-get install -y curl wget unzip jq tor netcat-openbsd
            ;;
        centos|rhel|fedora|rocky)
            dnf install -y epel-release 2>/dev/null || yum install -y epel-release
            dnf install -y curl wget unzip jq tor nmap-ncat 2>/dev/null || yum install -y curl wget unzip jq tor nmap-ncat
            ;;
        arch) pacman -Sy --noconfirm curl wget unzip jq tor gnu-netcat ;;
    esac
}

install_xray() {
    log_step "安装 Xray..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    mkdir -p "$XRAY_CONFIG_DIR" "$XRAY_LOG_DIR"
}

configure_tor() {
    log_step "配置 Tor..."
    cat > "$TOR_CONFIG_DIR/torrc" << 'EOF'
SocksPort 127.0.0.1:9050
DNSPort 127.0.0.1:5353
AutomapHostsOnResolve 1
AutomapHostsSuffixes .onion
Log notice file /var/log/tor/notices.log
EOF
    mkdir -p /var/log/tor
    chown -R tor:tor /var/log/tor 2>/dev/null || chown -R debian-tor:debian-tor /var/log/tor 2>/dev/null || true
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || head -c 32 /dev/urandom | xxd -p | sed 's/\(..\{8\}\)\(..\{4\}\)\(..\{4\}\)\(..\{4\}\)\(..\)/\1-\2-\3-\4-\5/'
}

configure_xray() {
    log_step "配置 Xray..."
    
    read -p "Xray 端口 [默认 $DEFAULT_XRAY_PORT]: " XRAY_PORT
    XRAY_PORT=${XRAY_PORT:-$DEFAULT_XRAY_PORT}
    
    echo "选择协议: 1) VLESS  2) VMess  3) Shadowsocks"
    read -p "选择 [1-3, 默认 1]: " PROTO
    PROTO=${PROTO:-1}
    
    echo "路由模式: 1) 智能分流(.onion走Tor)  2) 全流量走Tor"
    read -p "选择 [1-2, 默认 1]: " MODE
    MODE=${MODE:-1}
    
    USER_UUID=$(generate_uuid)
    SERVER_IP=$(curl -s ifconfig.me || echo "YOUR_IP")
    
    # 生成配置
    if [ "$PROTO" = "1" ]; then
        PROTO_NAME="VLESS"
        INBOUND='{"port":'$XRAY_PORT',"protocol":"vless","settings":{"clients":[{"id":"'$USER_UUID'"}],"decryption":"none"},"streamSettings":{"network":"tcp"}}'
    elif [ "$PROTO" = "2" ]; then
        PROTO_NAME="VMess"
        INBOUND='{"port":'$XRAY_PORT',"protocol":"vmess","settings":{"clients":[{"id":"'$USER_UUID'","alterId":0}]},"streamSettings":{"network":"ws","wsSettings":{"path":"/xray"}}}'
    else
        PROTO_NAME="Shadowsocks"
        SS_PASS=$(head -c 16 /dev/urandom | base64)
        INBOUND='{"port":'$XRAY_PORT',"protocol":"shadowsocks","settings":{"method":"2022-blake3-aes-128-gcm","password":"'$SS_PASS'","network":"tcp,udp"}}'
        USER_UUID="$SS_PASS"
    fi
    
    if [ "$MODE" = "2" ]; then
        RULES='[{"type":"field","network":"tcp,udp","outboundTag":"tor-out"}]'
        MODE_NAME="全流量Tor"
    else
        RULES='[{"type":"field","domain":["regexp:\\.onion$"],"outboundTag":"tor-out"},{"type":"field","network":"tcp,udp","outboundTag":"direct"}]'
        MODE_NAME="智能分流"
    fi
    
    cat > "$XRAY_CONFIG_DIR/config.json" << EOF
{
  "log":{"loglevel":"warning"},
  "inbounds":[$INBOUND],
  "outbounds":[
    {"tag":"direct","protocol":"freedom"},
    {"tag":"tor-out","protocol":"socks","settings":{"servers":[{"address":"127.0.0.1","port":9050}]}},
    {"tag":"block","protocol":"blackhole"}
  ],
  "routing":{"domainStrategy":"AsIs","rules":$RULES},
  "dns":{"servers":[{"address":"127.0.0.1","port":5353,"domains":["regexp:\\.onion$"]},"8.8.8.8"]}
}
EOF

    # 保存连接信息
    cat > "$XRAY_CONFIG_DIR/info.txt" << EOF
协议: $PROTO_NAME | 服务器: $SERVER_IP | 端口: $XRAY_PORT | UUID/密码: $USER_UUID | 模式: $MODE_NAME
EOF
    echo -e "${GREEN}配置完成! 信息保存在 $XRAY_CONFIG_DIR/info.txt${NC}"
    cat "$XRAY_CONFIG_DIR/info.txt"
}

setup_services() {
    log_step "启动服务..."
    systemctl daemon-reload
    systemctl enable tor xray
    systemctl restart tor && sleep 3 && systemctl restart xray
    echo -e "${GREEN}Xray: $(systemctl is-active xray) | Tor: $(systemctl is-active tor)${NC}"
}

create_manager() {
    cat > "$MANAGEMENT_SCRIPT" << 'MANAGER'
#!/bin/bash
case "$1" in
  status) systemctl status xray tor --no-pager ;;
  restart) systemctl restart tor && sleep 2 && systemctl restart xray && echo "已重启" ;;
  stop) systemctl stop xray tor && echo "已停止" ;;
  start) systemctl start tor && sleep 2 && systemctl start xray && echo "已启动" ;;
  log) journalctl -u xray -n 50 --no-pager ;;
  tor-log) tail -50 /var/log/tor/notices.log 2>/dev/null || journalctl -u tor -n 50 ;;
  info) cat /usr/local/etc/xray/info.txt 2>/dev/null ;;
  test) curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip | jq . ;;
  switch)
    CFG="/usr/local/etc/xray/config.json"
    echo "1) 智能分流  2) 全Tor"
    read -p "选择: " m
    if [ "$m" = "2" ]; then
      jq '.routing.rules=[{"type":"field","network":"tcp,udp","outboundTag":"tor-out"}]' "$CFG" > /tmp/x.json && mv /tmp/x.json "$CFG"
    else
      jq '.routing.rules=[{"type":"field","domain":["regexp:\\.onion$"],"outboundTag":"tor-out"},{"type":"field","network":"tcp,udp","outboundTag":"direct"}]' "$CFG" > /tmp/x.json && mv /tmp/x.json "$CFG"
    fi
    systemctl restart xray && echo "已切换"
    ;;
  *) echo "用法: xray-tor {status|restart|stop|start|log|tor-log|info|test|switch}" ;;
esac
MANAGER
    chmod +x "$MANAGEMENT_SCRIPT"
    log_info "管理命令: xray-tor"
}

main() {
    echo -e "${CYAN}=== Xray + Tor 安装 (Linux) ===${NC}"
    check_root
    detect_os
    detect_arch
    install_dependencies
    install_xray
    configure_tor
    configure_xray
    setup_services
    create_manager
    echo -e "${GREEN}安装完成! 使用 'xray-tor' 管理服务${NC}"
}

main "$@"
