#!/bin/sh
# Transparent proxy nftables manager for xray-rust

NFTABLE_NAME="xray_rust"
REDIR_PORT="${2:-1081}"

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

	chain prerouting {
		type filter hook prerouting priority mangle; policy accept;
		# DNS Hijacking to local router dnsmasq
		meta l4proto udp udp dport 53 redirect to :53 comment "xray: hijack dns"
		meta l4proto tcp tcp dport 53 redirect to :53 comment "xray: hijack dns tcp"

		# Bypass local and destination subnets
		ip daddr @local_ips return
		ip daddr @server_ips return
		ip daddr @bypass_ips return

		# Redirect TCP to xray-rust transparent proxy port
		meta l4proto tcp redirect to :$REDIR_PORT comment "xray: redirect tcp"
	}

	chain output {
		type filter hook output priority mangle; policy accept;
		# Avoid redirect loop for router self-traffic
		ip daddr @local_ips return
		ip daddr @server_ips return
		ip daddr @bypass_ips return

		# Do not redirect packets destined to proxy or local ports
		tcp dport { $REDIR_PORT, 10808, 22, 53, 80, 443 } return
	}
}
EOF

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

	logger -t xray-rust "nftables transparent proxy rules applied on port $REDIR_PORT"
}

stop() {
	nft delete table inet $NFTABLE_NAME 2>/dev/null
	logger -t xray-rust "nftables transparent proxy rules removed"
}

case "$1" in
	start) start ;;
	stop) stop ;;
	restart) stop; start ;;
	*) echo "Usage: $0 {start|stop|restart} [redir_port]" ;;
esac
