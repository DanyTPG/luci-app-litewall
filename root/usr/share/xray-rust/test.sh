#!/bin/sh
# Node latency & connectivity tester for xray-rust

cmd=$1
param1=$2
param2=$3
param3=$4

PROG="/usr/bin/xray-rust"
CONFIG_GEN="/usr/share/xray-rust/generate_config.lua"

case "$cmd" in
  ping)
    addr="$param1"
    [ -z "$addr" ] && echo "error: missing address" && exit 1
    res=$(ping -c 1 -W 2 "$addr" 2>/dev/null | grep -o "time=[0-9.]*" | cut -d= -f2)
    if [ -n "$res" ]; then
      echo "${res} ms"
    else
      echo "timeout"
    fi
    ;;

  tcping)
    addr="$param1"
    port="${param2:-443}"
    [ -z "$addr" ] && echo "error: missing address" && exit 1
    if command -v tcping >/dev/null 2>&1; then
      res=$(tcping -c 1 -t 2 -p "$port" "$addr" 2>/dev/null | grep -o "time=[0-9.]*" | cut -d= -f2)
      if [ -n "$res" ]; then
        echo "${res} ms"
      else
        echo "timeout"
      fi
    else
      # Fallback using nc
      start=$(date +%s%3N 2>/dev/null || date +%s)
      if nc -w 2 -z "$addr" "$port" 2>/dev/null; then
        finish=$(date +%s%3N 2>/dev/null || date +%s)
        diff=$((finish - start))
        echo "${diff} ms"
      else
        echo "timeout"
      fi
    fi
    ;;

  urltest)
    node_id="$param1"
    probe_url="${param2:-https://www.google.com/generate_204}"
    [ -z "$node_id" ] && echo "error: missing node_id" && exit 1

    active_node=$(uci -q get xray-rust.main.active_node)
    service_running=$(ubus call service list '{"name":"xray-rust"}' 2>/dev/null | grep -o '"running": true')

    if [ "$node_id" = "$active_node" ] && [ -n "$service_running" ]; then
      socks_port=$(uci -q get xray-rust.main.socks_port || echo "10808")
      res=$(curl -x "socks5h://127.0.0.1:${socks_port}" -o /dev/null -sk -w "%{http_code}:%{time_total}" --connect-timeout 3 -m 5 "$probe_url" 2>/dev/null)
      code=$(echo "$res" | cut -d: -f1)
      sec=$(echo "$res" | cut -d: -f2)
      if [ "$code" = "200" ] || [ "$code" = "204" ]; then
        ms=$(awk -v s="$sec" 'BEGIN { printf "%.0f", s * 1000 }')
        echo "${ms} ms"
      else
        echo "timeout"
      fi
    else
      # Test standalone node via temporary instance
      tmp_port=10899
      tmp_cfg="/tmp/urltest_${node_id}.json"
      lua "$CONFIG_GEN" "$tmp_cfg" "$node_id" "$tmp_port" >/dev/null 2>&1
      if [ ! -f "$tmp_cfg" ]; then
        echo "timeout"
        exit 1
      fi

      $PROG run -config "$tmp_cfg" >/dev/null 2>&1 &
      tpid=$!
      sleep 1

      res=$(curl -x "socks5h://127.0.0.1:${tmp_port}" -o /dev/null -sk -w "%{http_code}:%{time_total}" --connect-timeout 3 -m 5 "$probe_url" 2>/dev/null)
      kill -9 "$tpid" 2>/dev/null
      rm -f "$tmp_cfg"

      code=$(echo "$res" | cut -d: -f1)
      sec=$(echo "$res" | cut -d: -f2)
      if [ "$code" = "200" ] || [ "$code" = "204" ]; then
        ms=$(awk -v s="$sec" 'BEGIN { printf "%.0f", s * 1000 }')
        echo "${ms} ms"
      else
        echo "timeout"
      fi
    fi
    ;;

  *)
    echo "Usage: $0 {ping|tcping|urltest} [args...]"
    exit 1
    ;;
esac
