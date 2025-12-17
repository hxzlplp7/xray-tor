# Xray + Tor 使用说明

## 目录

1. [架构说明](#架构说明)
2. [Linux VPS 安装](#linux-vps-安装)
3. [FreeBSD (serv00/hostuno) 安装](#freebsd-安装)
4. [路由模式详解](#路由模式详解)
5. [客户端配置](#客户端配置)
6. [常见问题](#常见问题)
7. [高级配置](#高级配置)

---

## 架构说明

### 工作原理

```
客户端 → Xray (入站) → 路由判断 → [直连] 或 [Tor SOCKS] → 目标网站
                              ↓
                         .onion 域名
                              ↓
                        Tor 网络 → 暗网
```

### 两种路由模式

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| 智能分流 | `.onion` 走 Tor，其他直连 | 日常使用，需要访问暗网 |
| 全流量 Tor | 所有流量都经过 Tor | 需要完全匿名 |

---

## Linux VPS 安装

### 系统要求

- Debian/Ubuntu, CentOS/RHEL, Fedora, Arch Linux
- Root 权限
- 至少 512MB 内存

### 一键安装

```bash
# 下载并运行
bash <(curl -Ls https://raw.githubusercontent.com/hxzlplp7/xray-tor/main/scripts/install-linux.sh)

# 或使用 wget
wget -O - https://raw.githubusercontent.com/hxzlplp7/xray-tor/main/scripts/install-linux.sh | bash
```

### 手动安装

```bash
# 1. 克隆仓库
git clone https://github.com/hxzlplp7/xray-tor.git
cd tor

# 2. 添加执行权限
chmod +x scripts/install-linux.sh

# 3. 运行安装
sudo ./scripts/install-linux.sh
```

### 管理命令

安装完成后，使用 `xray-tor` 命令管理：

```bash
xray-tor status     # 查看服务状态
xray-tor restart    # 重启所有服务
xray-tor stop       # 停止服务
xray-tor start      # 启动服务
xray-tor log        # 查看 Xray 日志
xray-tor tor-log    # 查看 Tor 日志
xray-tor info       # 查看连接信息
xray-tor test       # 测试 Tor 连接
xray-tor switch     # 切换路由模式
```

---

## FreeBSD 安装

### serv00/hostuno 特别说明

**限制:**
- 无 root 权限
- 需要在控制面板开放端口
- 某些系统功能受限

**解决方案:**
- 用户级安装（安装到 `~/xray-tor`）
- 使用 cron 保活
- 手动编译 Tor（如需要）

### 安装步骤

```bash
# 1. SSH 连接到服务器
ssh username@server.serv00.com

# 2. 下载安装脚本
fetch https://raw.githubusercontent.com/hxzlplp7/xray-tor/main/scripts/install-freebsd.sh

# 或使用 curl
curl -O https://raw.githubusercontent.com/hxzlplp7/xray-tor/main/scripts/install-freebsd.sh

# 3. 添加执行权限
chmod +x install-freebsd.sh

# 4. 运行安装
./install-freebsd.sh
```

### 重要: 开放端口

1. 登录 serv00/hostuno 控制面板
2. 进入 "Port Reservation" 或类似选项
3. 添加 Xray 使用的端口（如 10086）
4. 选择 TCP 协议

### 管理命令

```bash
# 启动服务
~/xray-tor/bin/xray-tor start

# 停止服务
~/xray-tor/bin/xray-tor stop

# 查看状态
~/xray-tor/bin/xray-tor status

# 查看连接信息
~/xray-tor/bin/xray-tor info
```

### Tor 安装问题

如果自动安装 Tor 失败，有以下选项：

**选项 1: 使用外部 Tor 代理**

在安装时输入已有的 Tor SOCKS 地址（如公共 Tor 节点）

**选项 2: 从源码编译**

```bash
# 下载 Tor 源码
cd /tmp
fetch https://www.torproject.org/dist/tor-0.4.8.10.tar.gz
tar xzf tor-0.4.8.10.tar.gz
cd tor-0.4.8.10

# 配置（安装到用户目录）
./configure --prefix=$HOME/xray-tor --disable-asciidoc

# 编译安装
make
make install
```

---

## 路由模式详解

### 智能分流模式

**配置逻辑:**
```json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": ["regexp:\\.onion$"],
        "outboundTag": "tor-out"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "direct"
      }
    ]
  }
}
```

**效果:**
- 访问 `example.onion` → 通过 Tor
- 访问 `google.com` → 直连

### 全流量 Tor 模式

**配置逻辑:**
```json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "tor-out"
      }
    ]
  }
}
```

**效果:**
- 所有流量都经过 Tor 网络
- 完全匿名但速度较慢

### 切换模式

```bash
# Linux
xray-tor switch

# FreeBSD
~/xray-tor/bin/xray-tor switch
```

---

## 客户端配置

### 获取连接信息

```bash
# Linux
xray-tor info

# FreeBSD
~/xray-tor/bin/xray-tor info
```

### V2rayN / V2rayNG 配置

1. 复制连接信息中的 UUID
2. 添加服务器：
   - 地址: 你的服务器 IP
   - 端口: 安装时设置的端口
   - UUID: 复制的 UUID
   - 协议: VLESS / VMess / Shadowsocks

### 访问暗网

1. 确保使用智能分流或全 Tor 模式
2. 在浏览器中直接访问 `.onion` 地址
3. 无需额外配置 Tor Browser

---

## 常见问题

### Q: Tor 连接很慢？

**A:** Tor 建立电路需要时间，首次连接可能需要 1-3 分钟。之后会变快。

### Q: 无法访问 .onion 网站？

**A:** 检查:
1. Tor 是否正常运行
2. 路由模式是否正确
3. DNS 配置是否指向 Tor

```bash
# 测试 Tor 连接
xray-tor test
```

### Q: serv00 端口无法访问？

**A:** 确保:
1. 在控制面板开放了端口
2. 端口号在允许范围内
3. 选择了正确的协议类型 (TCP)

### Q: 如何查看真实 IP？

```bash
# 直连 IP
curl ifconfig.me

# Tor IP
curl --socks5-hostname 127.0.0.1:9050 ifconfig.me
```

---

## 高级配置

### 自定义 Tor 出口节点

编辑 torrc 文件：

```
# 只使用美国和德国的出口节点
ExitNodes {us},{de}
StrictNodes 1
```

### 使用 Tor 网桥

如果 Tor 被封锁：

```
UseBridges 1
Bridge obfs4 IP:PORT FINGERPRINT cert=... iat-mode=0
```

### 多协议入站

可以同时配置多个入站：

```json
{
  "inbounds": [
    {"port": 10086, "protocol": "vless", ...},
    {"port": 10087, "protocol": "vmess", ...},
    {"port": 10088, "protocol": "shadowsocks", ...}
  ]
}
```

### 日志级别调整

```json
{
  "log": {
    "loglevel": "debug"  // 调试时使用
  }
}
```

---

## 安全建议

1. **定期更新** - 保持 Xray 和 Tor 最新版本
2. **使用强密码** - 不要使用简单的 UUID
3. **限制访问** - 只允许信任的客户端连接
4. **监控日志** - 定期检查异常访问
5. **备份配置** - 保存重要配置文件

---

## 卸载

### Linux

```bash
sudo ./scripts/install-linux.sh uninstall
```

### FreeBSD

```bash
# 停止服务
~/xray-tor/bin/xray-tor stop

# 删除 cron 任务
crontab -l | grep -v keepalive | crontab -

# 删除安装目录
rm -rf ~/xray-tor
```
