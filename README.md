# Xray + Tor Proxy Solution

[中文文档](README_CN.md)

> ⚠️ **Disclaimer**
> 
> This project is for **educational and research purposes only**. Before using this project, please ensure you understand and comply with all applicable laws and regulations in your jurisdiction.
> 
> **About Tor:**
> - Tor (The Onion Router) is a legitimate privacy tool used by journalists, activists, and regular users to protect online privacy
> - Using Tor is legal in most countries, but may be restricted in some regions
> - This project does not encourage or support any illegal activities
> 
> **User Responsibility:**
> - You are solely responsible for your use of this project
> - Do not use this project for any illegal, infringing, or unethical activities
> - The author is not liable for any direct or indirect damages arising from the use of this project

---

## Overview

This project provides installation scripts for deploying Xray + Tor proxy on different environments:

### Features

- ✅ Regular websites via Xray (direct or proxy)
- ✅ Dark web (.onion) traffic via Tor
- ✅ Optional: All traffic via Tor
- ✅ Multiple inbound protocols (VLESS, VMess, Shadowsocks)
- ✅ Smart traffic routing

### Supported Environments

| Environment | Script | Description |
|-------------|--------|-------------|
| Linux VPS | `install-linux.sh` | Linux with root privileges |
| FreeBSD (serv00/hostuno) | `install-freebsd.sh` | FreeBSD without root privileges |

## Directory Structure

```
├── README.md                    # This document
├── README_CN.md                 # Chinese documentation
├── scripts/
│   ├── install-linux.sh         # Linux VPS installation script
│   └── install-freebsd.sh       # FreeBSD installation script
├── configs/
│   ├── xray-config.json         # Xray config template
│   ├── torrc                    # Tor config template
│   └── xray-tor-all.json        # Full Tor mode config
└── docs/
    └── usage.md                 # Usage guide
```

## Quick Start

### Linux VPS (with root)

```bash
# One-line installation
bash <(curl -Ls https://raw.githubusercontent.com/hxzlplp7/xray-tor/main/scripts/install-linux.sh)

# Or run locally
chmod +x scripts/install-linux.sh
sudo ./scripts/install-linux.sh
```

### FreeBSD (serv00/hostuno)

```bash
# After SSH connection
# Download the script
curl -O https://raw.githubusercontent.com/hxzlplp7/xray-tor/main/scripts/install-freebsd.sh

# Run installation
chmod +x install-freebsd.sh
./install-freebsd.sh
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Client                                   │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Xray Inbound                                  │
│             (VLESS/VMess/Shadowsocks)                            │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Xray Routing Module                            │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Rule 1: .onion domains → Tor Outbound                       ││
│  │ Rule 2: Other traffic → Direct Outbound (or Proxy)          ││
│  │ Rule 3: Full Tor mode → Tor Outbound                        ││
│  └─────────────────────────────────────────────────────────────┘│
└──────────────┬──────────────────────────────────┬───────────────┘
               │                                  │
               ▼                                  ▼
┌──────────────────────────┐      ┌──────────────────────────────┐
│     Direct Outbound      │      │       Tor Outbound           │
│   (Direct Internet)      │      │   (SOCKS5 → 127.0.0.1:9050)  │
└──────────────────────────┘      └──────────────┬───────────────┘
                                                 │
                                                 ▼
                                  ┌──────────────────────────────┐
                                  │         Tor Process          │
                                  │      (SOCKS5 @ 9050)         │
                                  └──────────────────────────────┘
```

## Routing Modes

### 1. Smart Routing (Default)
- `.onion` domains → Tor
- Other traffic → Direct

### 2. Full Tor Mode
- All traffic goes through Tor network

### Switch Mode

```bash
# Linux
xray-tor switch

# FreeBSD (serv00/hostuno)
~/xray-tor/bin/xray-tor switch
```

## Management Commands

### Linux

```bash
xray-tor status     # Check service status
xray-tor restart    # Restart all services
xray-tor stop       # Stop services
xray-tor start      # Start services
xray-tor log        # View Xray logs
xray-tor tor-log    # View Tor logs
xray-tor info       # Show connection info
xray-tor test       # Test Tor connection
xray-tor switch     # Switch routing mode
```

### FreeBSD

```bash
~/xray-tor/bin/xray-tor start    # Start services
~/xray-tor/bin/xray-tor stop     # Stop services
~/xray-tor/bin/xray-tor status   # Check status
~/xray-tor/bin/xray-tor info     # Show connection info
```

## Important Notes

### serv00/hostuno Limitations
- No root privileges, requires user-level installation
- Uses cron for service keepalive
- Ports must be opened in the control panel

### Security Recommendations
- Regularly update Xray and Tor
- Use strong passwords/UUIDs
- Enable TLS when possible

## Uninstall

### Linux

```bash
sudo ./scripts/install-linux.sh uninstall
```

### FreeBSD

```bash
~/xray-tor/bin/xray-tor stop
crontab -l | grep -v keepalive | crontab -
rm -rf ~/xray-tor
```

## License

MIT License - See [LICENSE](LICENSE) for details.

---

**⭐ If this project helps you, please give it a star!**
