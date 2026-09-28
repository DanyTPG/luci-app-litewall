#!/bin/sh
ACTION="${1:-clean}"

logger -t xray-rust "Recovery script invoked (action: $ACTION)"

case "$ACTION" in
    clean)
        # 1. Kill any hung or deadlocked xray-rust instances
        killall -9 xray-rust 2>/dev/null || true
        # 2. Unconditionally tear down nftables transparent proxy
        /usr/share/xray-rust/nftables.sh stop >/dev/null 2>&1
        # 3. Clean up dnsmasq configuration injection
        rm -f /tmp/dnsmasq.*.d/xray-rust.conf 2>/dev/null
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
        # 4. Disable in UCI to prevent accidental restart loops
        uci set xray-rust.main.enabled='0'
        uci commit xray-rust
        logger -t xray-rust "Emergency clean completed: nftables removed, dnsmasq restored, service disabled"
        echo '{"status":"ok","action":"clean","message":"Emergency reset completed: firewall flushed, DNS restored, service stopped."}'
        ;;
    restart)
        # 1. Kill any stale instances
        killall -9 xray-rust 2>/dev/null || true
        # 2. Tear down old firewall rules
        /usr/share/xray-rust/nftables.sh stop >/dev/null 2>&1
        # 3. Clean dnsmasq
        rm -f /tmp/dnsmasq.*.d/xray-rust.conf 2>/dev/null
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
        # 4. Ensure enabled in UCI
        uci set xray-rust.main.enabled='1'
        uci commit xray-rust
        # 5. Start service cleanly
        /etc/init.d/xray-rust restart >/dev/null 2>&1
        logger -t xray-rust "Clean restart completed: firewall and daemon reinitialized"
        echo '{"status":"ok","action":"restart","message":"Clean restart completed: service and firewall reinitialized."}'
        ;;
    *)
        echo '{"status":"error","message":"Invalid action"}'
        exit 1
        ;;
esac
exit 0
