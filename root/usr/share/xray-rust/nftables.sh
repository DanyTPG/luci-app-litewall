#!/bin/sh
# Transparent proxy nftables manager for xray-rust

NFTABLE_NAME="xray_rust"
REDIR_PORT="${2:-1081}"
PROXY_ROUTER="${3:-0}"
HIJACK_DNS="${4:-1}"
BLOCK_QUIC="${5:-1}"

start() {
	stop >/dev/null 2>&1

	# Determine server IP addresses to bypass proxy loop
	SERVER_IPS=""
	if [ -f /var/etc/xray-rust/server_ips ]; then
		SERVER_IPS=$(cat /var/etc/xray-rust/server_ips)
	fi

	nft -f - <<EOF
table inet $NFTABLE_NAME {
	set local_ips {
		type ipv4_addr
		flags interval
		elements = {
			0.0.0.0/8,
			10.0.0.0/8,
			100.64.0.0/10,
			127.0.0.0/8,
			169.254.0.0/16,
			172.16.0.0/12,
			192.168.0.0/16,
			224.0.0.0/4,
			240.0.0.0/4
		}
	}

	set server_ips {
		type ipv4_addr
		flags interval
	}

	set bypass_ips {
		type ipv4_addr
		flags interval
	}

	set lan_bypass {
		type ipv4_addr
		flags interval
	}

	chain prerouting {
		type nat hook prerouting priority dstnat; policy accept;

		# Bypass local and destination subnets
		ip daddr @local_ips return
		ip daddr @server_ips return
		ip daddr @bypass_ips return

		# Redirect TCP to xray-rust transparent proxy port
		meta l4proto tcp redirect to :$REDIR_PORT
	}
}
EOF

	# DNS Hijacking to local router dnsmasq if enabled
	if [ "$HIJACK_DNS" = "1" ]; then
		nft "insert rule inet $NFTABLE_NAME prerouting udp dport 53 redirect to :53" 2>/dev/null
		nft "insert rule inet $NFTABLE_NAME prerouting tcp dport 53 redirect to :53" 2>/dev/null
	fi

	# Block QUIC (UDP 443) to force clients to fall back to TCP and route via proxy
	if [ "$BLOCK_QUIC" = "1" ]; then
		nft "add rule inet $NFTABLE_NAME prerouting udp dport 443 reject" 2>/dev/null
	fi

	# Optional router self-proxy
	if [ "$PROXY_ROUTER" = "1" ]; then
		nft -f - <<EOF
table inet $NFTABLE_NAME {
	chain output {
		type nat hook output priority -100; policy accept;
		ip daddr @local_ips return
		ip daddr @server_ips return
		ip daddr @bypass_ips return
		tcp dport { $REDIR_PORT, 10808, 22, 53 } return
		meta l4proto tcp redirect to :$REDIR_PORT
	}
}
EOF
		if [ "$BLOCK_QUIC" = "1" ]; then
			nft "add rule inet $NFTABLE_NAME output udp dport 443 reject" 2>/dev/null
		fi
	fi

	# Add server IPs if available
	if [ -n "$SERVER_IPS" ]; then
		for ip in $SERVER_IPS; do
			nft "add element inet $NFTABLE_NAME server_ips { $ip }" 2>/dev/null
		done
	fi

	# Add custom bypass IPs if exists
	if [ -f /var/etc/xray-rust/bypass_ips ]; then
		for ip in $(cat /var/etc/xray-rust/bypass_ips); do
			nft "add element inet $NFTABLE_NAME bypass_ips { $ip }" 2>/dev/null
		done
	fi

	# Add LAN client bypass (exempt specific clients from proxy)
	if [ -f /var/etc/xray-rust/lan_bypass ]; then
		for ip in $(cat /var/etc/xray-rust/lan_bypass); do
			nft "add element inet $NFTABLE_NAME lan_bypass { $ip }" 2>/dev/null
		done
		nft "insert rule inet $NFTABLE_NAME prerouting ip saddr @lan_bypass return" 2>/dev/null
	fi

	logger -t xray-rust "nftables transparent proxy rules applied on port $REDIR_PORT (router_proxy=$PROXY_ROUTER, dns_hijack=$HIJACK_DNS)"
}

stop() {
	nft flush table inet $NFTABLE_NAME 2>/dev/null
	nft delete table inet $NFTABLE_NAME 2>/dev/null
	logger -t xray-rust "nftables transparent proxy rules removed"
}

case "$1" in
	start) start ;;
	stop) stop ;;
	restart) stop; start ;;
	*) echo "Usage: $0 {start|stop|restart} [redir_port] [proxy_router] [hijack_dns]" ;;
esac
