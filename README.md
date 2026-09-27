# luci-app-xray-rust

LuCI web management application for `xray-rust`, a memory-efficient Rust implementation of the Xray-core client supporting VLESS, Reality, and XHTTP transports on OpenWrt routers.

## Features

- **Extreme Low Memory**: ~6.5 MB RSS compared to Go Xray's ~80+ MB RSS / ~590 MB VSZ.
- **Full Transparent Proxying**: Intercepts router and LAN TCP traffic via OpenWrt `nftables` redirect into a built-in SO_ORIGINAL_DST redirect bridge.
- **DNS Leak Protection**: Automatic port 53 DNS hijacking redirects all client DNS queries to local `dnsmasq`.
- **Protocol Support**: VLESS + XHTTP (`stream-up`, `packet-up`, `stream-one`), WebSocket, HTTPUpgrade, gRPC, TLS, Reality.
- **Multi-Node Management**: Store multiple nodes, switch active nodes instantly from LuCI dropdown, import directly from `vless://` share URLs.
- **Routing Rules**: Configurable routing modes (Bypass LAN / Private IPs, Bypass Iran Domestic `geoip:ir`/`geosite:ir`, Global Proxy), plus custom whitelist/blacklist domain and IP lists.
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
