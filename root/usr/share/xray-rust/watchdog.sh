#!/bin/sh
# Watchdog script for xray-rust: auto-restarts on crash, auto-cleans on disable

# Check if watchdog is enabled in UCI (default 1)
watchdog_enabled=$(uci -q get xray-rust.main.watchdog)
[ "$watchdog_enabled" = "0" ] && exit 0

enabled=$(uci -q get xray-rust.main.enabled)
COUNT_FILE="/tmp/xray_rust_restart_count"
NOTIFY_EVERY=5   # notify on 1st, 6th, 11th... consecutive restart

# Lock file to prevent multiple instances from overlapping
LOCKFILE="/var/run/xray-rust-watchdog.lock"
if [ -e "$LOCKFILE" ]; then
    pid=$(cat "$LOCKFILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

if [ "$enabled" != "1" ]; then
    # Service is disabled: if stray transparent proxy firewall rules exist, clean them up
    if nft list table inet xray_rust >/dev/null 2>&1; then
        logger -t xray-rust-watchdog "Service is disabled but transparent proxy table exists. Cleaning up..."
        /usr/share/xray-rust/clean.sh clean >/dev/null 2>&1
    fi
    rm -f "$COUNT_FILE"
    exit 0
fi

# Service is enabled: check if xray-rust process is alive
if pidof xray-rust >/dev/null 2>&1; then
    # Running fine — reset streak counter
    rm -f "$COUNT_FILE"
    exit 0
fi

# It crashed!
logger -t xray-rust-watchdog "ALERT: xray-rust is enabled but process is not running (crashed). Initiating clean restart..."
/usr/share/xray-rust/clean.sh restart >/dev/null 2>&1
RC=$?

N=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
N=$((N + 1))
echo "$N" > "$COUNT_FILE"

# Send ntfy notification
topic=$(uci -q get xray-rust.main.ntfy_topic)
[ -z "$topic" ] && topic="my-alert-topic"

if [ -n "$topic" ]; then
    case "$topic" in
        http://*|https://*) url="$topic" ;;
        */*) url="https://$topic" ;;
        *) url="https://ntfy.sh/$topic" ;;
    esac
    
    if [ $(( (N - 1) % NOTIFY_EVERY )) -eq 0 ]; then
        curl -s -m 10 -d "⚠️ xray-rust auto-restarted (crashed / OOM) [streak #$N, restart rc=$RC]" "$url" >/dev/null 2>&1 || \
        curl -s -m 10 -d "⚠️ xray-rust auto-restarted (crashed / OOM) [streak #$N, restart rc=$RC]" "${url/https:/http:}" >/dev/null 2>&1
    fi
fi

exit 0
