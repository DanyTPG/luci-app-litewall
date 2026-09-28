# luci-app-xray-rust

LuCI web management application for `xray-rust`, a memory-efficient Rust implementation of the Xray-core client supporting VLESS, Reality, and XHTTP transports on OpenWrt routers.

## Features

- **Extreme Low Memory**: ~6.5 MB RSS compared to Go Xray's ~80+ MB RSS / ~590 MB VSZ.
- **Full Transparent Proxying**: Intercepts router and LAN TCP traffic via OpenWrt `nftables` redirect into a built-in SO_ORIGINAL_DST redirect bridge.
- **DNS Leak & QUIC Protection**: Automatic port 53 DNS hijacking redirects all client DNS queries to local `dnsmasq`. Optional QUIC (UDP 443) blocker forces Android apps and browsers onto TCP proxy without touching gaming UDP packets.
- **Protocol Support**: VLESS + XHTTP (`stream-up`, `packet-up`, `stream-one`), WebSocket, HTTPUpgrade, gRPC, TLS, Reality.
- **Multi-Node Management & Diagnostics**: Store multiple nodes, switch active nodes instantly from LuCI dropdown, import directly from `vless://` share URLs, and perform Passwall2-style one-click latency diagnostics (Ping, TCPing, URL Test).
- **Rule Groups & Shunting**: Shunt rules by traffic category (Iran domestic, GFW blocked, Sanctions, ADS adblocking) routing to specific nodes, direct bypass, or block (native blackhole).
- **Configurable Default Routing Mode**: Global switch between Direct (bypass by default, only proxy matched rules) and Proxy (global proxy fallback).
- **Procd Integration**: Native OpenWrt service lifecycle management with automatic respawn and configuration validation.

## Architecture

1. **`xray-rust` core**: Runs VLESS + XHTTP outbound tunnel and local SOCKS5 inbound (`127.0.0.1:10808`).
2. **Transparent Redirect Bridge**: Built directly into `xray-rust` CLI (`XRAY_REDIR_PORT=1081`). Intercepts TCP connections redirected by nftables, queries `SO_ORIGINAL_DST`, and establishes transparent SOCKS5 connections.
3. **`nftables` Engine (`/usr/share/xray-rust/nftables.sh`)**: Creates `inet xray_rust` NAT table with prerouting and output chains to redirect LAN/router traffic to `:1081` while bypassing local subnets and proxy server IPs.
4. **LuCI Management View**: Modern JavaScript UI with tabs for Status, Basic Settings, Routing & Shunting Rules, and Node Management.

## Manual Installation on Router

Copy the package files directly to OpenWrt root:

```sh
# Copy binary
cp xray-rust /usr/bin/xray-rust
chmod +x /usr/bin/xray-rust

# Copy LuCI files
cp -r root/* /
cp -r htdocs/* /www/

# Set executable permissions
chmod +x /etc/init.d/xray-rust
chmod +x /usr/share/xray-rust/generate_config.lua

# Reload LuCI services
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```
