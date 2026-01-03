#!/bin/bash
# ============================================================
# Xray + Tor 一键安装脚本 (Linux VPS 版)
# 支持: Debian/Ubuntu, CentOS/RHEL/Fedora, Arch Linux
# 功能: 普通网站走Xray, 暗网走Tor, 或全流量走Tor
# 特点: 直接下载二进制文件，无需包管理器
# ============================================================

# 不使用 set -e，手动处理错误以提高兼容性

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置变量
INSTALL_DIR="/usr/local/xray-tor"
BIN_DIR="$INSTALL_DIR/bin"
CONFIG_DIR="$INSTALL_DIR/config"
LOG_DIR="$INSTALL_DIR/logs"
TOR_DATA_DIR="$INSTALL_DIR/tor-data"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_LOG_DIR="/var/log/xray"
TOR_CONFIG_DIR="/etc/tor"
DEFAULT_XRAY_PORT=10086
TOR_SOCKS_PORT=9050
TOR_DNS_PORT=5353

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
        x86_64|amd64)
            XRAY_ARCH="64"
            TOR_ARCH="linux-x86_64"
            ;;
        aarch64|arm64)
            XRAY_ARCH="arm64-v8a"
            TOR_ARCH="linux-aarch64"
            ;;
        armv7l)
            XRAY_ARCH="arm32-v7a"
            TOR_ARCH="linux-armhf"
            ;;
        *)
            log_error "不支持: $ARCH"
            exit 1
            ;;
    esac
    log_info "架构: $ARCH -> Xray: $XRAY_ARCH, Tor: $TOR_ARCH"
}

create_directories() {
    log_step "创建目录结构..."
    mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$TOR_DATA_DIR"
    mkdir -p "$XRAY_CONFIG_DIR" "$XRAY_LOG_DIR" /var/log/tor
    chmod 700 "$TOR_DATA_DIR"
}

fix_dns() {
    log_step "检查 DNS 配置..."
    
    # 修复 hostname 解析问题
    HOSTNAME=$(hostname)
    if ! grep -q "$HOSTNAME" /etc/hosts 2>/dev/null; then
        echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
        log_info "已修复 hostname 解析: $HOSTNAME"
    fi
    
    # 检查 DNS 是否工作
    if ! ping -c 1 -W 3 google.com &>/dev/null && ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        log_warn "DNS 可能有问题，尝试修复..."
        # 备份并添加公共 DNS
        cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
        cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
EOF
        log_info "已添加公共 DNS"
    fi
}

install_dependencies() {
    log_step "检查基础依赖..."
    
    # 修复 DNS
    fix_dns
    
    # curl 或 wget (必需)
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        log_info "安装 curl..."
        case $OS in
            ubuntu|debian) apt-get update -y 2>/dev/null; apt-get install -y curl 2>/dev/null || true ;;
            centos|rhel|fedora|rocky) dnf install -y curl 2>/dev/null || yum install -y curl 2>/dev/null || true ;;
            arch) pacman -Sy --noconfirm curl 2>/dev/null || true ;;
        esac
    fi
    
    # 再次检查，如果还是没有则报错
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        log_error "无法安装 curl 或 wget，请手动安装后重试"
        exit 1
    fi
    
    # unzip (必需)
    if ! command -v unzip &>/dev/null; then
        log_info "安装 unzip..."
        case $OS in
            ubuntu|debian) apt-get install -y unzip 2>/dev/null || true ;;
            centos|rhel|fedora|rocky) dnf install -y unzip 2>/dev/null || yum install -y unzip 2>/dev/null || true ;;
            arch) pacman -Sy --noconfirm unzip 2>/dev/null || true ;;
        esac
    fi
    
    if ! command -v unzip &>/dev/null; then
        log_error "无法安装 unzip，请手动安装后重试"
        exit 1
    fi
    
    # jq - 直接下载二进制文件 (可选，用于 switch 功能)
    if ! command -v jq &>/dev/null; then
        log_info "下载 jq 二进制..."
        JQ_ARCH="jq-linux-amd64"
        case $ARCH in
            aarch64|arm64) JQ_ARCH="jq-linux-arm64" ;;
            armv7l) JQ_ARCH="jq-linux-armhf" ;;
        esac
        
        JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.7.1/${JQ_ARCH}"
        
        if command -v curl &>/dev/null; then
            curl -sL "$JQ_URL" -o /usr/local/bin/jq 2>/dev/null && chmod +x /usr/local/bin/jq
        else
            wget -qO /usr/local/bin/jq "$JQ_URL" 2>/dev/null && chmod +x /usr/local/bin/jq
        fi
        
        if command -v jq &>/dev/null; then
            log_info "jq 安装成功"
        else
            log_warn "jq 安装失败，switch 功能将不可用（不影响主功能）"
        fi
    fi
}

download_xray() {
    log_step "下载 Xray..."
    
    # 获取最新版本
    XRAY_VERSION=$(curl -sL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/' || echo "25.1.1")
    
    XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"
    
    log_info "下载 Xray v${XRAY_VERSION} from $XRAY_URL"
    
    cd /tmp
    rm -f Xray-linux-*.zip xray geoip.dat geosite.dat
    
    if command -v curl &>/dev/null; then
        curl -L -o xray.zip "$XRAY_URL" || { log_error "Xray 下载失败"; exit 1; }
    else
        wget -O xray.zip "$XRAY_URL" || { log_error "Xray 下载失败"; exit 1; }
    fi
    
    unzip -o xray.zip xray geoip.dat geosite.dat
    mv xray "$BIN_DIR/"
    mv geoip.dat geosite.dat "$CONFIG_DIR/" 2>/dev/null || true
    chmod +x "$BIN_DIR/xray"
    rm -f xray.zip
    
    # 创建软链接
    ln -sf "$BIN_DIR/xray" /usr/local/bin/xray
    
    log_info "Xray v${XRAY_VERSION} 安装完成"
}

download_tor() {
    log_step "安装 Tor..."
    
    # 优先使用包管理器（更稳定）
    log_info "尝试从包管理器安装 Tor..."
    case $OS in
        ubuntu|debian)
            apt-get update -y 2>/dev/null
            apt-get install -y tor 2>/dev/null
            ;;
        centos|rhel|fedora|rocky)
            dnf install -y epel-release 2>/dev/null || yum install -y epel-release 2>/dev/null || true
            dnf install -y tor 2>/dev/null || yum install -y tor 2>/dev/null
            ;;
        arch)
            pacman -Sy --noconfirm tor 2>/dev/null
            ;;
    esac
    
    # 检查是否安装成功
    if command -v tor &>/dev/null; then
        log_info "Tor 从包管理器安装成功"
        # 使用系统 tor
        TOR_USE_SYSTEM=1
        return
    fi
    
    # 包管理器失败，尝试 Expert Bundle
    log_warn "包管理器安装失败，尝试 Expert Bundle..."
    
    TOR_VERSION="14.0.4"
    TOR_URL="https://archive.torproject.org/tor-package-archive/torbrowser/${TOR_VERSION}/tor-expert-bundle-${TOR_ARCH}-${TOR_VERSION}.tar.gz"
    
    log_info "下载 Tor Expert Bundle v${TOR_VERSION}..."
    
    cd /tmp
    rm -rf tor-expert-bundle* tor
    
    if command -v curl &>/dev/null; then
        curl -L -o tor-bundle.tar.gz "$TOR_URL" || {
            log_warn "官方源下载失败，尝试备用源..."
            # 备用: 使用系统包管理器
            install_tor_from_package
            return
        }
    else
        wget -O tor-bundle.tar.gz "$TOR_URL" || {
            log_warn "官方源下载失败，尝试备用源..."
            install_tor_from_package
            return
        }
    fi
    
    tar -xzf tor-bundle.tar.gz || {
        log_error "Tor 解压失败"
        install_tor_from_package
        return
    }
    
    # 列出解压内容用于调试
    log_info "解压内容: $(ls -la)"
    
    # Expert Bundle 14.x 结构可能是:
    # - tor/tor (旧版)
    # - tor/libevent-*.so, tor/libssl.so.*, tor/<tor binary> (新版)
    TOR_FOUND=0
    
    # 方法1: 直接在 tor/ 目录找 tor 二进制
    if [ -f "tor/tor" ]; then
        mv tor/tor "$BIN_DIR/"
        TOR_FOUND=1
    fi
    
    # 方法2: 查找任何名为 tor 的可执行文件
    if [ "$TOR_FOUND" = "0" ]; then
        TOR_BIN_PATH=$(find . -name "tor" -type f -executable 2>/dev/null | head -1)
        if [ -n "$TOR_BIN_PATH" ]; then
            mv "$TOR_BIN_PATH" "$BIN_DIR/tor"
            TOR_FOUND=1
        fi
    fi
    
    # 方法3: 在解压目录中查找
    if [ "$TOR_FOUND" = "0" ] && [ -d "tor" ]; then
        # 新版 Expert Bundle 结构
        for f in tor/*; do
            if file "$f" 2>/dev/null | grep -q "executable\|ELF"; then
                BASENAME=$(basename "$f")
                if [ "$BASENAME" = "tor" ] || echo "$BASENAME" | grep -q "^tor$"; then
                    mv "$f" "$BIN_DIR/tor"
                    TOR_FOUND=1
                    break
                fi
            fi
        done
    fi
    
    if [ "$TOR_FOUND" = "1" ]; then
        chmod +x "$BIN_DIR/tor"
        # 复制 pluggable transports (如果有)
        if [ -d "tor/pluggable_transports" ]; then
            cp -r tor/pluggable_transports "$INSTALL_DIR/"
        fi
        # 复制依赖库 (递归查找所有 .so 文件)
        mkdir -p "$INSTALL_DIR/lib"
        find . -name "*.so*" -type f 2>/dev/null | while read lib; do
            cp "$lib" "$INSTALL_DIR/lib/" 2>/dev/null || true
        done
        
        # 检查是否有库文件
        if ls "$INSTALL_DIR/lib"/*.so* 1>/dev/null 2>&1; then
            log_info "已复制依赖库到 $INSTALL_DIR/lib/"
        else
            log_warn "未找到依赖库，可能需要从包管理器安装 libevent"
            # 尝试安装 libevent
            case $OS in
                ubuntu|debian) apt-get install -y libevent-2.1-7 2>/dev/null || true ;;
                centos|rhel|fedora|rocky) dnf install -y libevent 2>/dev/null || yum install -y libevent 2>/dev/null || true ;;
            esac
        fi
        
        rm -rf tor-bundle.tar.gz tor data debug
        ln -sf "$BIN_DIR/tor" /usr/local/bin/tor
        log_info "Tor v${TOR_VERSION} 安装完成"
    else
        log_warn "无法从 Expert Bundle 中提取 Tor，尝试包管理器..."
        rm -rf tor-bundle.tar.gz tor
        install_tor_from_package
    fi
}

install_tor_from_package() {
    log_warn "尝试从包管理器安装 Tor..."
    case $OS in
        ubuntu|debian)
            apt-get update -y
            apt-get install -y tor
            ;;
        centos|rhel|fedora|rocky)
            dnf install -y epel-release 2>/dev/null || yum install -y epel-release || true
            dnf install -y tor 2>/dev/null || yum install -y tor
            ;;
        arch)
            pacman -Sy --noconfirm tor
            ;;
    esac
    
    if command -v tor &>/dev/null; then
        log_info "Tor 从包管理器安装成功"
    else
        log_error "Tor 安装失败"
        exit 1
    fi
}

configure_tor() {
    log_step "配置 Tor..."
    
    # 检测 tor 用户
    TOR_USER="tor"
    if id "debian-tor" &>/dev/null; then
        TOR_USER="debian-tor"
    elif id "tor" &>/dev/null; then
        TOR_USER="tor"
    else
        # 创建 tor 用户
        useradd -r -s /bin/false tor 2>/dev/null || true
        TOR_USER="tor"
    fi
    
    mkdir -p /etc/tor /var/log/tor "$TOR_DATA_DIR"
    
    cat > /etc/tor/torrc << EOF
# Tor 配置
SocksPort 127.0.0.1:${TOR_SOCKS_PORT}
DNSPort 127.0.0.1:${TOR_DNS_PORT}
DataDirectory ${TOR_DATA_DIR}
Log notice file /var/log/tor/notices.log
AutomapHostsOnResolve 1
AutomapHostsSuffixes .onion
EOF
    
    chown -R $TOR_USER:$TOR_USER "$TOR_DATA_DIR" /var/log/tor 2>/dev/null || true
    chmod 700 "$TOR_DATA_DIR"
    
    log_info "Tor 配置完成"
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null || \
    uuidgen 2>/dev/null || \
    head -c 32 /dev/urandom | xxd -p | sed 's/\(..\{8\}\)\(..\{4\}\)\(..\{4\}\)\(..\{4\}\)\(..*\)/\1-\2-\3-\4-\5/'
}

configure_xray() {
    log_step "配置 Xray..."
    
    read -p "Xray 端口 [默认 $DEFAULT_XRAY_PORT]: " XRAY_PORT
    XRAY_PORT=${XRAY_PORT:-$DEFAULT_XRAY_PORT}
    
    echo "选择协议: 1) VLESS-Reality (推荐)  2) VLESS-TCP  3) VMess-WS  4) Shadowsocks"
    read -p "选择 [1-4, 默认 1]: " PROTO
    PROTO=${PROTO:-1}
    
    echo "路由模式: 1) 智能分流(.onion走Tor)  2) 全流量走Tor"
    read -p "选择 [1-2, 默认 1]: " MODE
    MODE=${MODE:-1}
    
    USER_UUID=$(generate_uuid)
    
    # 优先获取 IPv4，没有才用 IPv6
    log_info "获取服务器 IP..."
    SERVER_IPV4=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -4 -s --connect-timeout 5 ip.sb 2>/dev/null || echo "")
    SERVER_IPV6=$(curl -6 -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -6 -s --connect-timeout 5 ip.sb 2>/dev/null || echo "")
    
    if [ -n "$SERVER_IPV4" ]; then
        SERVER_IP="$SERVER_IPV4"
        log_info "使用 IPv4: $SERVER_IP"
    elif [ -n "$SERVER_IPV6" ]; then
        SERVER_IP="$SERVER_IPV6"
        log_info "使用 IPv6: $SERVER_IP"
    else
        SERVER_IP="YOUR_IP"
        log_warn "无法获取 IP，请手动修改配置"
    fi
    
    # 生成配置
    if [ "$PROTO" = "1" ]; then
        # VLESS Reality
        PROTO_NAME="VLESS-Reality"
        
        # 生成 x25519 密钥对
        log_info "生成 Reality 密钥..."
        
        KEYS=$("$BIN_DIR/xray" x25519 2>&1)
        log_info "xray x25519 输出:"
        echo "$KEYS"
        
        # 使用字段名匹配 (不依赖行号，避免控制字符/CRLF问题)
        # 新版 Xray: PrivateKey + Password (公钥)
        PRIVATE_KEY=$(echo "$KEYS" | grep -i '^PrivateKey:' | head -n1 | cut -d':' -f2- | tr -d '[:space:]')
        PUBLIC_KEY=$(echo "$KEYS" | grep -i '^Password:' | head -n1 | cut -d':' -f2- | tr -d '[:space:]')
        
        log_info "提取的私钥: $PRIVATE_KEY"
        log_info "提取的公钥: $PUBLIC_KEY"
        
        # 验证密钥
        if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
            log_error "Reality 密钥解析失败"
            log_warn "RAW KEYS:"
            printf '%q\n' "$KEYS"
            log_warn "可重新运行脚本选择 VLESS-TCP 协议"
            exit 1
        fi
        
        log_info "Private Key: ${PRIVATE_KEY:0:10}..."
        log_info "Public Key: ${PUBLIC_KEY:0:10}..."
        
        # 生成 shortId
        SHORT_ID=$(head -c 8 /dev/urandom | xxd -p)
        
        # Reality 目标站点（伪装）
        REALITY_DEST="www.apple.com:443"
        REALITY_SNI="www.apple.com"
        
        INBOUND='{
  "port": '$XRAY_PORT',
  "protocol": "vless",
  "settings": {
    "clients": [{"id": "'$USER_UUID'", "flow": "xtls-rprx-vision"}],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "dest": "'$REALITY_DEST'",
      "serverNames": ["'$REALITY_SNI'", "apple.com"],
      "privateKey": "'$PRIVATE_KEY'",
      "shortIds": ["'$SHORT_ID'", ""]
    }
  }
}'
    elif [ "$PROTO" = "2" ]; then
        # VLESS TCP (无加密)
        PROTO_NAME="VLESS-TCP"
        INBOUND='{"port":'$XRAY_PORT',"protocol":"vless","settings":{"clients":[{"id":"'$USER_UUID'"}],"decryption":"none"},"streamSettings":{"network":"tcp"}}'
    elif [ "$PROTO" = "3" ]; then
        PROTO_NAME="VMess-WS"
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
        RULES='[{"type":"field","domain":["domain:.onion"],"outboundTag":"tor-out"},{"type":"field","network":"tcp,udp","outboundTag":"direct"}]'
        MODE_NAME="智能分流"
    fi
    
    mkdir -p "$XRAY_CONFIG_DIR"
    
    cat > "$XRAY_CONFIG_DIR/config.json" << EOF
{
  "log":{"loglevel":"warning","access":"$XRAY_LOG_DIR/access.log","error":"$XRAY_LOG_DIR/error.log"},
  "inbounds":[$INBOUND],
  "outbounds":[
    {"tag":"direct","protocol":"freedom"},
    {"tag":"tor-out","protocol":"socks","settings":{"servers":[{"address":"127.0.0.1","port":$TOR_SOCKS_PORT}]}},
    {"tag":"block","protocol":"blackhole"}
  ],
  "routing":{"domainStrategy":"AsIs","rules":$RULES},
  "dns":{"servers":[{"address":"127.0.0.1","port":$TOR_DNS_PORT,"domains":["domain:.onion"]},"8.8.8.8"]}
}
EOF

    # 保存连接信息
    cat > "$XRAY_CONFIG_DIR/info.txt" << EOF
===== Xray + Tor 连接信息 =====
协议: $PROTO_NAME
服务器: $SERVER_IP
端口: $XRAY_PORT
UUID/密码: $USER_UUID
路由模式: $MODE_NAME
Tor SOCKS: 127.0.0.1:$TOR_SOCKS_PORT
==============================
EOF
    
    # 生成分享链接
    # 处理 IPv6 地址格式
    if echo "$SERVER_IP" | grep -q ":"; then
        # IPv6 地址需要方括号
        SERVER_ADDR="[${SERVER_IP}]"
        REMARK="Xray-Tor"
    else
        SERVER_ADDR="${SERVER_IP}"
        REMARK="Xray-Tor-${SERVER_IP}"
    fi
    REMARK_ENCODED=$(echo -n "$REMARK" | sed 's/ /%20/g; s/:/%3A/g; s/\//%2F/g')
    
    if [ "$PROTO" = "1" ]; then
        # VLESS Reality 链接格式
        SHARE_LINK="vless://${USER_UUID}@${SERVER_ADDR}:${XRAY_PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&sni=${REALITY_SNI}&flow=xtls-rprx-vision&fp=chrome#${REMARK_ENCODED}"
        
        # 保存 Reality 密钥信息
        cat >> "$XRAY_CONFIG_DIR/info.txt" << EOF
Reality Public Key: $PUBLIC_KEY
Reality Short ID: $SHORT_ID
Reality SNI: $REALITY_SNI
EOF
    elif [ "$PROTO" = "2" ]; then
        # VLESS TCP 链接格式
        SHARE_LINK="vless://${USER_UUID}@${SERVER_ADDR}:${XRAY_PORT}?type=tcp&security=none#${REMARK_ENCODED}"
    elif [ "$PROTO" = "3" ]; then
        # VMess 链接格式: vmess://base64(json)
        VMESS_JSON="{\"v\":\"2\",\"ps\":\"${REMARK}\",\"add\":\"${SERVER_IP}\",\"port\":\"${XRAY_PORT}\",\"id\":\"${USER_UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"/xray\",\"tls\":\"\"}"
        VMESS_BASE64=$(echo -n "$VMESS_JSON" | base64 -w 0 2>/dev/null || echo -n "$VMESS_JSON" | base64)
        SHARE_LINK="vmess://${VMESS_BASE64}"
    else
        # Shadowsocks 2022 链接格式
        SS_USERINFO=$(echo -n "2022-blake3-aes-128-gcm:${USER_UUID}" | base64 -w 0 2>/dev/null || echo -n "2022-blake3-aes-128-gcm:${USER_UUID}" | base64)
        SHARE_LINK="ss://${SS_USERINFO}@${SERVER_ADDR}:${XRAY_PORT}#${REMARK_ENCODED}"
    fi
    
    # 保存分享链接
    echo "$SHARE_LINK" > "$XRAY_CONFIG_DIR/share.txt"
    
    # 追加到 info.txt
    cat >> "$XRAY_CONFIG_DIR/info.txt" << EOF

========== 分享链接 ==========
$SHARE_LINK
==============================
EOF
    
    echo -e "${GREEN}配置完成!${NC}"
    cat "$XRAY_CONFIG_DIR/info.txt"
}

create_systemd_services() {
    log_step "创建 systemd 服务..."
    
    # 如果使用系统 Tor，不需要创建自定义服务
    if [ "$TOR_USE_SYSTEM" = "1" ]; then
        log_info "使用系统自带的 Tor 服务"
    else
        # 自定义 Tor 服务 (添加 LD_LIBRARY_PATH 以加载依赖库)
        cat > /etc/systemd/system/tor.service << EOF
[Unit]
Description=Tor Anonymity Network
After=network.target

[Service]
Type=simple
User=tor
Environment="LD_LIBRARY_PATH=$INSTALL_DIR/lib"
ExecStart=$BIN_DIR/tor -f /etc/tor/torrc
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    fi

    # Xray 服务
    cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target tor.service
Wants=tor.service

[Service]
Type=simple
ExecStart=$BIN_DIR/xray run -config $XRAY_CONFIG_DIR/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # 如果系统已有 tor 包安装的服务，使用系统的
    if systemctl list-unit-files | grep -q "^tor.service" && [ -f "/usr/bin/tor" ]; then
        log_info "使用系统自带的 Tor 服务"
        rm -f /etc/systemd/system/tor.service
    fi
    
    systemctl daemon-reload
    log_info "systemd 服务创建完成"
}

setup_services() {
    log_step "启动服务..."
    
    systemctl daemon-reload
    systemctl enable tor xray
    
    # 先启动 Tor
    systemctl restart tor
    log_info "等待 Tor 初始化..."
    sleep 5
    
    # 再启动 Xray
    systemctl restart xray
    sleep 2
    
    echo -e "${GREEN}Xray: $(systemctl is-active xray) | Tor: $(systemctl is-active tor)${NC}"
}

create_manager() {
    log_step "创建管理命令..."
    
    cat > /usr/local/bin/xray-tor << 'MANAGER'
#!/bin/bash
case "$1" in
  status) systemctl status xray tor --no-pager ;;
  restart) systemctl restart tor && sleep 3 && systemctl restart xray && echo "已重启" ;;
  stop) systemctl stop xray tor && echo "已停止" ;;
  start) systemctl start tor && sleep 3 && systemctl start xray && echo "已启动" ;;
  log) journalctl -u xray -n 50 --no-pager ;;
  tor-log) tail -50 /var/log/tor/notices.log 2>/dev/null || journalctl -u tor -n 50 ;;
  info) cat /usr/local/etc/xray/info.txt 2>/dev/null ;;
  test) 
    echo "测试 Tor 连接..."
    echo ""
    # 先检查 Tor 服务状态
    if ! systemctl is-active --quiet tor; then
      echo "[错误] Tor 服务未运行，尝试启动..."
      systemctl start tor
      sleep 5
    fi
    echo "检查 Tor 电路..."
    # 使用超时防止挂起
    RESULT=$(timeout 30 curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip 2>&1)
    if [ -n "$RESULT" ]; then
      echo "$RESULT" | jq . 2>/dev/null || echo "$RESULT"
      echo ""
      echo "[成功] Tor 连接正常!"
    else
      echo "[失败] Tor 连接超时或失败"
      echo ""
      echo "调试信息:"
      systemctl status tor --no-pager | head -10
    fi
    ;;
  test-onion)
    echo "测试 .onion 访问..."
    echo ""
    RESULT=$(timeout 60 curl -s --socks5-hostname 127.0.0.1:9050 http://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/ 2>&1 | head -20)
    if [ -n "$RESULT" ]; then
      echo "$RESULT"
      echo ""
      echo "[成功] .onion 访问正常!"
    else
      echo "[失败] .onion 访问超时"
    fi
    ;;
  switch)
    CFG="/usr/local/etc/xray/config.json"
    echo "当前模式切换:"
    echo "1) 智能分流 (.onion走Tor)"
    echo "2) 全流量走Tor"
    read -p "选择: " m
    if [ "$m" = "2" ]; then
      jq '.routing.rules=[{"type":"field","network":"tcp,udp","outboundTag":"tor-out"}]' "$CFG" > /tmp/x.json && mv /tmp/x.json "$CFG"
      echo "已切换到: 全流量Tor"
    else
      jq '.routing.rules=[{"type":"field","domain":["domain:.onion"],"outboundTag":"tor-out"},{"type":"field","network":"tcp,udp","outboundTag":"direct"}]' "$CFG" > /tmp/x.json && mv /tmp/x.json "$CFG"
      echo "已切换到: 智能分流"
    fi
    systemctl restart xray && echo "Xray 已重启"
    ;;
  uninstall)
    echo "确认卸载 Xray + Tor? [y/N]"
    read confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      systemctl stop xray tor 2>/dev/null
      systemctl disable xray tor 2>/dev/null
      rm -rf /usr/local/xray-tor /usr/local/etc/xray /var/log/xray
      rm -f /etc/systemd/system/xray.service /usr/local/bin/xray /usr/local/bin/tor /usr/local/bin/xray-tor
      systemctl daemon-reload
      echo "已卸载"
    fi
    ;;
  share|link)
    echo ""
    echo "========== 分享链接 =========="
    cat /usr/local/etc/xray/share.txt 2>/dev/null || echo "分享链接未找到"
    echo "=============================="
    echo ""
    ;;
  menu|"")
    # 交互式菜单
    while true; do
      clear
      echo ""
      echo "  ╔═══════════════════════════════════════╗"
      echo "  ║       Xray + Tor 管理面板             ║"
      echo "  ╠═══════════════════════════════════════╣"
      echo "  ║  1. 查看服务状态                      ║"
      echo "  ║  2. 启动服务                          ║"
      echo "  ║  3. 停止服务                          ║"
      echo "  ║  4. 重启服务                          ║"
      echo "  ║  5. 查看连接信息                      ║"
      echo "  ║  6. 显示分享链接                      ║"
      echo "  ║  7. 测试 Tor 连接                     ║"
      echo "  ║  8. 切换路由模式                      ║"
      echo "  ║  9. 查看日志                          ║"
      echo "  ║  0. 卸载                              ║"
      echo "  ║  q. 退出菜单                          ║"
      echo "  ╚═══════════════════════════════════════╝"
      echo ""
      echo -n "  请选择 [0-9/q]: "
      read choice
      case $choice in
        1) echo ""; systemctl status xray tor --no-pager; echo ""; read -p "按回车继续..." ;;
        2) systemctl start tor && sleep 3 && systemctl start xray && echo "已启动"; read -p "按回车继续..." ;;
        3) systemctl stop xray tor && echo "已停止"; read -p "按回车继续..." ;;
        4) systemctl restart tor && sleep 3 && systemctl restart xray && echo "已重启"; read -p "按回车继续..." ;;
        5) echo ""; cat /usr/local/etc/xray/info.txt 2>/dev/null; echo ""; read -p "按回车继续..." ;;
        6) echo ""; echo "分享链接:"; cat /usr/local/etc/xray/share.txt 2>/dev/null; echo ""; read -p "按回车继续..." ;;
        7) 
          echo "测试 Tor 连接..."
          timeout 30 curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip | jq . 2>/dev/null || echo "连接失败或超时"
          read -p "按回车继续..."
          ;;
        8)
          echo "1) 智能分流 (.onion走Tor)"
          echo "2) 全流量走Tor"
          read -p "选择: " m
          CFG="/usr/local/etc/xray/config.json"
          if [ "$m" = "2" ]; then
            jq '.routing.rules=[{"type":"field","network":"tcp,udp","outboundTag":"tor-out"}]' "$CFG" > /tmp/x.json && mv /tmp/x.json "$CFG"
            echo "已切换到: 全流量Tor"
          else
            jq '.routing.rules=[{"type":"field","domain":["domain:.onion"],"outboundTag":"tor-out"},{"type":"field","network":"tcp,udp","outboundTag":"direct"}]' "$CFG" > /tmp/x.json && mv /tmp/x.json "$CFG"
            echo "已切换到: 智能分流"
          fi
          systemctl restart xray
          read -p "按回车继续..."
          ;;
        9) echo ""; journalctl -u xray -n 30 --no-pager; echo ""; read -p "按回车继续..." ;;
        0)
          echo "确认卸载? [y/N]"
          read confirm
          if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            systemctl stop xray tor 2>/dev/null
            systemctl disable xray tor 2>/dev/null
            rm -rf /usr/local/xray-tor /usr/local/etc/xray /var/log/xray
            rm -f /etc/systemd/system/xray.service /etc/systemd/system/tor.service
            rm -f /usr/local/bin/xray /usr/local/bin/tor /usr/local/bin/xray-tor /usr/local/bin/xt
            systemctl daemon-reload
            echo "已卸载"
            exit 0
          fi
          ;;
        q|Q) echo "再见!"; exit 0 ;;
        *) echo "无效选择" ;;
      esac
    done
    ;;
  help|-h|--help)
    echo "Xray + Tor 管理工具"
    echo ""
    echo "用法: xray-tor [命令]"
    echo "      xt [命令]        (快捷方式)"
    echo ""
    echo "无参数时进入交互式菜单"
    echo ""
    echo "命令:"
    echo "  status    - 查看服务状态"
    echo "  start     - 启动服务"
    echo "  stop      - 停止服务"
    echo "  restart   - 重启服务"
    echo "  info      - 查看连接信息"
    echo "  share     - 显示分享链接"
    echo "  test      - 测试 Tor 连接"
    echo "  switch    - 切换路由模式"
    echo "  log       - 查看 Xray 日志"
    echo "  tor-log   - 查看 Tor 日志"
    echo "  menu      - 进入交互式菜单"
    echo "  uninstall - 卸载"
    ;;
  *)
    echo "未知命令: $1"
    echo "使用 'xray-tor help' 查看帮助"
    ;;
esac
MANAGER
    chmod +x /usr/local/bin/xray-tor
    
    # 创建快捷方式 xt
    ln -sf /usr/local/bin/xray-tor /usr/local/bin/xt
    
    log_info "管理命令: xray-tor 或 xt"
}

show_completion() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              安装完成!                            ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}进入管理菜单:${NC}"
    echo -e "  ${YELLOW}xray-tor${NC}  或  ${YELLOW}xt${NC}"
    echo ""
    echo -e "${GREEN}常用命令:${NC}"
    echo "  xt info     - 查看连接信息"
    echo "  xt share    - 显示分享链接"
    echo "  xt status   - 查看服务状态"
    echo "  xt restart  - 重启服务"
    echo "  xt test     - 测试 Tor 连接"
    echo ""
    cat "$XRAY_CONFIG_DIR/info.txt"
    echo ""
}

main() {
    echo -e "${CYAN}=== Xray + Tor 安装 (Linux) ===${NC}"
    check_root
    detect_os
    detect_arch
    create_directories
    install_dependencies
    download_xray
    download_tor
    configure_tor
    configure_xray
    create_systemd_services
    setup_services
    create_manager
    show_completion
}

main "$@"
