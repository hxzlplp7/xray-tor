# Xray + Tor 代理方案

[English](README.md)

> ⚠️ **免责声明 / Disclaimer**
> 
> 本项目仅供学习和研究网络技术使用。使用本项目前，请确保您了解并遵守当地法律法规。
> 
> **关于 Tor 网络：**
> - Tor（The Onion Router）是一个合法的隐私保护工具，被记者、活动家和普通用户用于保护网络隐私
> - 在大多数国家，使用 Tor 是合法的，但在某些地区可能受到限制
> - 本项目不鼓励、不支持任何非法活动
> 
> **使用者责任：**
> - 您应对使用本项目的行为负全部责任
> - 请勿将本项目用于任何违法、侵权或不道德的活动
> - 作者不对因使用本项目而产生的任何直接或间接损失承担责任
> 
> **This project is for educational and research purposes only. By using this project, you agree to comply with all applicable laws and regulations in your jurisdiction. The author is not responsible for any misuse or illegal activities conducted with this software.**

---

## 项目说明

本项目提供两套安装脚本，用于在不同环境下部署 Xray + Tor 代理：

### 功能特性

- ✅ 访问普通网站走 Xray（直连或代理）
- ✅ 暗网(.onion)流量走 Tor
- ✅ 可选：所有流量走 Tor
- ✅ 支持多种入站协议（VLESS, VMess, Trojan, Shadowsocks）
- ✅ 智能路由分流

### 环境支持

| 环境类型 | 脚本文件 | 说明 |
|---------|---------|------|
| Linux VPS | `install-linux.sh` | 有 root 权限的 Linux 系统 |
| FreeBSD (serv00/hostuno) | `install-freebsd.sh` | 无 root 权限的 FreeBSD 系统 |

## 目录结构

```
├── README.md                    # 本文档
├── scripts/
│   ├── install-linux.sh         # Linux VPS 安装脚本
│   └── install-freebsd.sh       # FreeBSD 安装脚本
├── configs/
│   ├── xray-config.json         # Xray 配置模板
│   ├── torrc                    # Tor 配置模板
│   └── xray-tor-all.json        # 全流量走Tor的Xray配置
└── docs/
    └── usage.md                 # 使用说明
```

## 快速开始

### Linux VPS（有 root 权限）

```bash
# 下载并运行安装脚本
bash <(curl -Ls https://raw.githubusercontent.com/hxzlplp7/xray-tor/main/scripts/install-linux.sh)

# 或本地运行
chmod +x scripts/install-linux.sh
sudo ./scripts/install-linux.sh
```

### FreeBSD (serv00/hostuno)

```bash
# SSH 连接到 serv00/hostuno 后
# 上传脚本到服务器
scp scripts/install-freebsd.sh user@server:~/

# 运行安装脚本
chmod +x ~/install-freebsd.sh
./install-freebsd.sh
```

## 架构说明

```
┌─────────────────────────────────────────────────────────────────┐
│                        客户端                                    │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Xray Inbound                                  │
│           (VLESS/VMess/Trojan/Shadowsocks)                       │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Xray 路由模块                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ 规则1: .onion 域名 → Tor Outbound                           ││
│  │ 规则2: 普通流量 → Direct Outbound (或 Proxy)                ││
│  │ 规则3: 全流量模式 → Tor Outbound                            ││
│  └─────────────────────────────────────────────────────────────┘│
└──────────────┬──────────────────────────────────┬───────────────┘
               │                                  │
               ▼                                  ▼
┌──────────────────────────┐      ┌──────────────────────────────┐
│     Direct Outbound      │      │       Tor Outbound           │
│     (直接访问互联网)      │      │   (SOCKS5 → 127.0.0.1:9050) │
└──────────────────────────┘      └──────────────┬───────────────┘
                                                 │
                                                 ▼
                                  ┌──────────────────────────────┐
                                  │         Tor 进程              │
                                  │    (SOCKS5 @ 9050)           │
                                  └──────────────────────────────┘
```

## 配置说明

### 路由模式

1. **智能分流模式（默认）**
   - `.onion` 域名 → Tor
   - 其他流量 → 直连

2. **全 Tor 模式**
   - 所有流量都经过 Tor 网络

### 切换模式

```bash
# Linux
sudo xray-tor switch-mode

# FreeBSD (serv00/hostuno)
~/bin/xray-tor switch-mode
```

## 注意事项

1. **serv00/hostuno 限制**
   - 无 root 权限，需要编译安装
   - 使用用户级 systemd 或 cron 管理服务
   - 端口需在面板中开放

2. **安全建议**
   - 定期更新 Xray 和 Tor
   - 使用强密码/UUID
   - 建议开启 TLS

## 许可证

MIT License
