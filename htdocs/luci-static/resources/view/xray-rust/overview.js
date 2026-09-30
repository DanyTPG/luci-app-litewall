'use strict';
'require dom';
'require form';
'require fs';
'require rpc';
'require uci';
'require ui';
'require view';

var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: [ 'name' ],
	expect: { 'xray-rust': {} }
});

function createTestLink(type, section_id) {
	var node = uci.get('xray-rust', section_id);
	if (!node || !node.server) {
		return E('span', { 'style': 'color:#888;' }, '---');
	}

	var server = node.server;
	var port = node.port || '443';

	return E('a', {
		'href': 'javascript:void(0)',
		'style': 'color:#33a3dc;text-decoration:none;cursor:pointer;font-weight:bold;white-space:nowrap;',
		'click': function(ev) {
			ev.preventDefault();
			if (this.getAttribute('data-busy') === '1') return;
			this.setAttribute('data-busy', '1');
			this.style.color = '#aaa';
			this.innerText = _('Checking...');

			var args = [type];
			if (type === 'ping') {
				args.push(server);
			} else if (type === 'tcping') {
				args.push(server, port);
			} else if (type === 'urltest') {
				args.push(section_id);
			}

			var self = this;
			fs.exec('/usr/share/xray-rust/test.sh', args).then(function(res) {
				self.setAttribute('data-busy', '0');
				var out = (res.stdout || '').trim();
				var ms = parseFloat(out);
				if (!out || out.indexOf('timeout') !== -1 || out.indexOf('fail') !== -1 || out.indexOf('error') !== -1 || isNaN(ms) || ms < 0) {
					self.innerText = _('Timeout');
					self.style.color = '#e74c3c';
				} else {
					var rounded = Math.round(ms);
					self.innerText = rounded + ' ms';
					if (rounded < 150) {
						self.style.color = '#2ecc71';
					} else if (rounded < 500) {
						self.style.color = '#fb9a05';
					} else {
						self.style.color = '#e74c3c';
					}
				}
			}).catch(function() {
				self.setAttribute('data-busy', '0');
				self.innerText = _('Timeout');
				self.style.color = '#e74c3c';
			});
		}
	}, _('Test'));
}

return view.extend({
	load: function() {
		return Promise.all([
			callServiceList('xray-rust'),
			uci.load('xray-rust')
		]);
	},

	render: function(data) {
		var serviceData = data[0] || {};
		var instances = serviceData.instances || {};
		var isRunning = false;
		var pid = null;

		for (var inst in instances) {
			if (instances[inst].running) {
				isRunning = true;
				pid = instances[inst].pid;
				break;
			}
		}

		var m, s, o;

		m = new form.Map('xray-rust', _('LiteWall'),
			_('High-performance, ultra-low-memory proxy client with transparent routing, node diagnostics, and kernel fast-path shunting.'));

		// 1. Status Section
		s = m.section(form.NamedSection, 'main', 'main', _('System & Service Status'));
		s.anonymous = true;

		o = s.option(form.DummyValue, '_status', _('Daemon Status'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			if (isRunning) {
				return '<span style="color:#2ecc71;font-weight:bold;font-size:1.1em;">&#9679; ' +
					_('RUNNING') + '</span> <span style="color:#888;margin-left:8px;">(PID: ' + pid + ' | Memory: ~6.5 MB RSS)</span>';
			} else {
				return '<span style="color:#e74c3c;font-weight:bold;font-size:1.1em;">&#9679; ' +
					_('STOPPED') + '</span>';
			}
		};

		o = s.option(form.DummyValue, '_ports', _('Listening Inbounds'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			var socks = uci.get('xray-rust', 'main', 'socks_port') || '10808';
			var redir = uci.get('xray-rust', 'main', 'redir_port') || '1081';
			var mode = uci.get('xray-rust', 'main', 'mode') || 'redirect';
			var html = '<code>127.0.0.1:' + socks + ' (SOCKS5)</code>';
			if (mode === 'redirect') {
				html += ' &nbsp;|&nbsp; <code>0.0.0.0:' + redir + ' (Transparent TCP Redirect)</code>';
			}
			return html;
		};

		o = s.option(form.DummyValue, '_recovery', _('Emergency Actions'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return E('div', { 'style': 'display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-top:4px;' }, [
				E('button', {
					'class': 'cbi-button cbi-button-reset',
					'style': 'background:#e74c3c;color:#fff;border:none;padding:5px 12px;border-radius:4px;cursor:pointer;font-weight:bold;',
					'click': function(ev) {
						ev.preventDefault();
						var btn = ev.target;
						btn.disabled = true;
						btn.innerText = _('Resetting...');
						fs.exec('/usr/share/xray-rust/clean.sh', ['clean']).then(function(res) {
							ui.addNotification(null, E('p', _('Emergency Reset Completed: All firewall redirect rules removed, DNS restored, and internet unblocked.')), 'info');
							window.setTimeout(function() { window.location.reload(); }, 1500);
						}).catch(function(err) {
							ui.addNotification(null, E('p', _('Reset failed: ') + err.message), 'error');
							btn.disabled = false;
							btn.innerText = _('Emergency Reset & Flush');
						});
					}
				}, _('Emergency Reset & Flush Firewall')),

				E('button', {
					'class': 'cbi-button cbi-button-action',
					'style': 'background:#2980b9;color:#fff;border:none;padding:5px 12px;border-radius:4px;cursor:pointer;font-weight:bold;',
					'click': function(ev) {
						ev.preventDefault();
						var btn = ev.target;
						btn.disabled = true;
						btn.innerText = _('Restarting...');
						fs.exec('/usr/share/xray-rust/clean.sh', ['restart']).then(function(res) {
							ui.addNotification(null, E('p', _('Clean Restart Completed: Service and firewall re-initialized.')), 'info');
							window.setTimeout(function() { window.location.reload(); }, 2000);
						}).catch(function(err) {
							ui.addNotification(null, E('p', _('Restart failed: ') + err.message), 'error');
							btn.disabled = false;
							btn.innerText = _('Clean Restart Service');
						});
					}
				}, _('Clean Restart Service'))
			]);
		};

		// 2. Main Config with Unified Tab Groups
		s = m.section(form.NamedSection, 'main', 'main', _('Settings'));
		s.tab('basic', _('Basic Settings'));
		s.tab('nodes', _('Node Management'));
		s.tab('rules', _('Routing Rule Groups'));
		s.tab('tuning', _('Memory & Performance'));
		s.tab('custom_override', _('Custom Whitelist / Overrides'));

		// --- Basic Settings Tab ---
		o = s.taboption('basic', form.Flag, 'enabled', _('Enable Service'));
		o.rmempty = false;
		o.default = '1';

		o = s.taboption('basic', form.ListValue, 'mode', _('Running Mode'));
		o.value('redirect', _('TCP Transparent Proxy (Redirect entire router & LAN)'));
		o.value('socks', _('SOCKS5 Only (Standalone local proxy)'));
		o.default = 'redirect';

		o = s.taboption('basic', form.ListValue, 'active_node', _('Default Active Node'));
		var nodes = uci.sections('xray-rust', 'node');
		nodes.forEach(function(node) {
			var label = (node.remark || node['.name']) + ' (' + (node.server || 'unknown') + ':' + (node.port || '443') + ')';
			o.value(node['.name'], label);
		});
		if (nodes.length > 0 && !uci.get('xray-rust', 'main', 'active_node')) {
			o.default = nodes[0]['.name'];
		}

		o = s.taboption('basic', form.ListValue, 'default_routing_mode', _('Default Routing Mode'));
		o.value('direct', _('Direct (Bypass - only proxy matched rules)'));
		o.value('proxy', _('Proxy (Global - route unmatched traffic to proxy)'));
		o.default = 'direct';
		o.description = _('Defines the fallback routing behavior for traffic not matched by any rule group.');

		o = s.taboption('basic', form.Value, 'socks_port', _('SOCKS5 Port'));
		o.datatype = 'port';
		o.default = '10808';

		o = s.taboption('basic', form.Value, 'redir_port', _('Transparent Redirect Port'));
		o.datatype = 'port';
		o.default = '1081';
		o.depends('mode', 'redirect');

		o = s.taboption('basic', form.Flag, 'hijack_dns', _('Hijack LAN DNS'));
		o.description = _('Force all LAN device DNS queries to router dnsmasq to eliminate DNS leaks.');
		o.default = '1';
		o.depends('mode', 'redirect');

		o = s.taboption('basic', form.Flag, 'block_quic', _('Block QUIC (UDP 443)'));
		o.description = _('Reject UDP port 443 to force Android apps (YouTube, Twitter) and browsers to fall back to TCP and route through proxy. Does not affect gaming or other UDP ports.');
		o.default = '1';
		o.depends('mode', 'redirect');

		o = s.taboption('basic', form.Flag, 'bypass_iran_firewall', _('Bypass Domestic IPs in Firewall'));
		o.description = _('Directly bypass Iranian IP ranges in nftables to route domestic traffic via Linux kernel fast-path, greatly reducing RAM and CPU load.');
		o.default = '1';
		o.depends('mode', 'redirect');

		o = s.taboption('basic', form.Flag, 'proxy_router', _('Proxy Router Itself'));
		o.description = _('Also route router-originated traffic through the proxy.');
		o.default = '0';
		o.depends('mode', 'redirect');

		o = s.taboption('basic', form.Flag, 'watchdog', _('Auto-Restart Watchdog'));
		o.description = _('Automatically monitor xray-rust every minute via crontab and cleanly restart firewall and daemon if a crash occurs.');
		o.default = '1';

		o = s.taboption('basic', form.Value, 'ntfy_topic', _('ntfy Notification Topic'));
		o.description = _('Optional ntfy topic (e.g. my-alert-topic or ntfy.sh/topic) to send crash restart alerts to your phone.');
		o.placeholder = 'my-alert-topic';
		o.depends('watchdog', '1');

		o = s.taboption('basic', form.DynamicList, 'bypass_lan_ips', _('Bypass LAN IP Addresses'));
		o.description = _('LAN IP addresses (e.g. your management PC) that should completely bypass transparent proxy and DNS redirection.');
		o.datatype = 'ip4addr';
		o.optional = true;

		// --- Memory & Performance Tuning Tab ---
		o = s.taboption('tuning', form.ListValue, 'h2_window', _('HTTP/2 Stream Receive Window'));
		o.value('131072', '128 KiB (Ultra Low Memory)');
		o.value('262144', '256 KiB (Recommended for 128/256 MB RAM)');
		o.value('524288', '512 KiB');
		o.value('1048576', '1 MiB');
		o.value('2097152', '2 MiB');
		o.value('4194304', '4 MiB (Default)');
		o.default = '262144';
		o.description = _('Caps the HTTP/2 stream receive window for XHTTP uplink connections. Lowering from 4 MiB to 256 KiB drastically reduces memory spikes without sacrificing streaming performance.');

		o = s.taboption('tuning', form.ListValue, 'buffer_size', _('Relay Buffer Size (KiB)'));
		o.value('8', '8 KiB (Ultra Low Memory)');
		o.value('16', '16 KiB (Recommended for 128 MB RAM)');
		o.value('32', '32 KiB');
		o.value('64', '64 KiB');
		o.value('128', '128 KiB (Xray Core Default)');
		o.default = '16';
		o.description = _('Per-connection buffer size for relay copying. 16 KiB significantly reduces memory pressure under heavy concurrent connections.');

		o = s.taboption('tuning', form.Value, 'conn_idle', _('Proxy Connection Idle Timeout (Seconds)'));
		o.datatype = 'uinteger';
		o.default = '30';
		o.description = _('Closes idle proxy TCP connections after N seconds of inactivity (default 30s vs core 300s) to free socket and memory resources.');

		o = s.taboption('tuning', form.Value, 'redir_idle', _('Transparent Redir Idle Timeout (Seconds)'));
		o.datatype = 'uinteger';
		o.default = '60';
		o.description = _('Closes transparent redirected client sockets when dormant for N seconds, preventing mobile app background connections from lingering.');

		o = s.taboption('tuning', form.Value, 'handshake', _('Handshake Timeout (Seconds)'));
		o.datatype = 'uinteger';
		o.default = '4';
		o.description = _('Maximum seconds allowed for establishing outbound TCP/TLS handshakes.');

		o = s.taboption('tuning', form.Value, 'max_post_bytes', _('XHTTP Max POST Buffer Cap (Bytes)'));
		o.datatype = 'uinteger';
		o.default = '32768';
		o.description = _('Safety ceiling for XHTTP packet-up POST buffers (e.g. 32768 = 32 KiB). Prevents nodes configured with huge post buffers (like 1 MB) from causing Out-Of-Memory.');

		// --- Custom Overrides Tab ---
		o = s.taboption('custom_override', form.DynamicList, 'direct_domain', _('Direct Domains (Always Bypass)'));
		o.description = _('Domains that directly connect without going through the proxy.');
		o.placeholder = 'example.ir';

		o = s.taboption('custom_override', form.DynamicList, 'proxy_domain', _('Proxy Domains (Always Proxy)'));
		o.description = _('Domains always routed through the proxy.');
		o.placeholder = 'google.com';

		o = s.taboption('custom_override', form.DynamicList, 'direct_ip', _('Direct CIDRs / IPs'));
		o.description = _('IP CIDRs to bypass (e.g. 10.0.0.0/8).');
		o.placeholder = '192.168.0.0/16';

		// --- Tab 2: Node Management (Inside dedicated tab) ---
		o = s.taboption('nodes', form.SectionValue, '_nodes', form.GridSection, 'node', _('Node Management'),
			_('Configure VLESS/XHTTP proxy nodes and run real-time latency tests.'));
		var s_node = o.subsection;
		s_node.addremove = true;
		s_node.anonymous = false;
		s_node.sortable = true;

		var no;
		no = s_node.option(form.Value, 'remark', _('Remark / Name'));
		no.placeholder = 'My VLESS Server';

		no = s_node.option(form.ListValue, 'type', _('Protocol'));
		no.value('vless', 'VLESS');
		no.default = 'vless';

		no = s_node.option(form.Value, 'server', _('Server Address'));
		no.datatype = 'host';
		no.placeholder = 'example.com';

		no = s_node.option(form.Value, 'port', _('Port'));
		no.datatype = 'port';
		no.default = '443';

		no = s_node.option(form.ListValue, 'transport', _('Transport'));
		no.value('xhttp', 'XHTTP');
		no.value('ws', 'WebSocket');
		no.value('httpupgrade', 'HTTPUpgrade');
		no.value('grpc', 'gRPC');
		no.value('tcp', 'TCP / Raw');
		no.default = 'xhttp';

		no = s_node.option(form.ListValue, 'security', _('Security'));
		no.value('tls', 'TLS');
		no.value('reality', 'REALITY');
		no.value('none', 'None');
		no.default = 'tls';

		// Node Diagnostics & Latency Tests (Ping, TCPing, URL Test) - Passwall2 Style
		no = s_node.option(form.DummyValue, '_ping', _('Ping'));
		no.modalonly = false;
		no.textvalue = function(section_id) {
			return createTestLink('ping', section_id);
		};
		no.cfgvalue = no.textvalue;

		no = s_node.option(form.DummyValue, '_tcping', _('TCPing'));
		no.modalonly = false;
		no.textvalue = function(section_id) {
			return createTestLink('tcping', section_id);
		};
		no.cfgvalue = no.textvalue;

		no = s_node.option(form.DummyValue, '_urltest', _('URL Test'));
		no.modalonly = false;
		no.textvalue = function(section_id) {
			return createTestLink('urltest', section_id);
		};
		no.cfgvalue = no.textvalue;

		// Modal options for editing node details
		no = s_node.option(form.TextValue, 'raw_link', _('Or Paste Share Link (vless://...)'));
		no.modalonly = true;
		no.rows = 4;
		no.placeholder = 'vless://uuid@host:port?type=xhttp...';

		no = s_node.option(form.Value, 'uuid', _('UUID / User ID'));
		no.modalonly = true;
		no.placeholder = '00000000-0000-0000-0000-000000000000';

		no = s_node.option(form.Value, 'path', _('Path'));
		no.modalonly = true;
		no.default = '/';

		no = s_node.option(form.Value, 'sni', _('SNI / ServerName'));
		no.modalonly = true;
		no.placeholder = 'example.com';

		no = s_node.option(form.Value, 'fp', _('Fingerprint'));
		no.modalonly = true;
		no.default = 'chrome';

		// --- Tab 3: Routing Rule Groups (Inside dedicated tab) ---
		o = s.taboption('rules', form.SectionValue, '_rules', form.GridSection, 'rule_group', _('Routing Rule Groups (Shunting)'),
			_('Configure rule groups and assign specific outbound nodes or direct bypass to each group.'));
		var s_rule = o.subsection;
		s_rule.addremove = true;
		s_rule.anonymous = false;
		s_rule.sortable = true;

		var ro;
		ro = s_rule.option(form.Flag, 'enabled', _('Enable'));
		ro.default = '1';
		ro.rmempty = false;

		ro = s_rule.option(form.Value, 'remarks', _('Group Name / Remark'));
		ro.placeholder = 'My Rule Group';

		ro = s_rule.option(form.ListValue, 'target_node', _('Target Node'));
		ro.value('_direct', _('Direct (Bypass Proxy)'));
		ro.value('_default', _('Default Active Node (Proxy)'));
		ro.value('_block', _('Block (Blackhole)'));
		nodes.forEach(function(node) {
			var label = (node.remark || node['.name']);
			ro.value(node['.name'], _('Node: ') + label);
		});
		ro.default = '_default';

		ro = s_rule.option(form.ListValue, 'network', _('Network'));
		ro.value('tcp,udp', 'TCP + UDP');
		ro.value('tcp', 'TCP Only');
		ro.value('udp', 'UDP Only');
		ro.default = 'tcp,udp';

		ro = s_rule.option(form.DynamicList, 'domain_list', _('Domain Matchers'));
		ro.modalonly = true;
		ro.placeholder = 'geosite:ir';
		ro.description = _('Domains, geosite rules (e.g. geosite:ir, geosite:youtube), or regex (e.g. regexp:.*google.*).');

		ro = s_rule.option(form.DynamicList, 'ip_list', _('IP Matchers'));
		ro.modalonly = true;
		ro.placeholder = 'geoip:ir';
		ro.description = _('IP CIDRs (e.g. 1.2.3.0/24) or geoip rules (e.g. geoip:ir, geoip:telegram).');

		ro = s_rule.option(form.Value, 'port', _('Port / Range'));
		ro.modalonly = true;
		ro.placeholder = '80,443';

		return m.render();
	}
});
