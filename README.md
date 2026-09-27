# luci-app-xray-rust

LuCI web management application for `xray-rust`, a memory-efficient Rust implementation of the Xray-core client supporting VLESS, Reality, and XHTTP transports on OpenWrt routers.

## Features

- **Extreme Low Memory**: ~6.5 MB RSS compared to Go Xray's ~80+ MB RSS / ~590 MB VSZ.
- **Protocol Support**: VLESS + XHTTP (`stream-up`, `packet-up`, `stream-one`), WebSocket, HTTPUpgrade, gRPC, TLS, Reality.
- **Link Import**: Paste standard `vless://` share links directly into the WebUI.
- **SOCKS5 Inbound**: Configurable local SOCKS5 port (default `10808`).
- **Procd Integration**: Native OpenWrt service lifecycle management with automatic respawn and configuration validation.

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
