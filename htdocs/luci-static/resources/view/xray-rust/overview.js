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

		m = new form.Map('xray-rust', _('Xray Rust Client'),
			_('High-performance, ultra-low-memory (6.5 MB RSS) Xray proxy client with transparent routing, node diagnostics, and shunt rules.'));

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

		// 2. Main Config with Tabs
		s = m.section(form.NamedSection, 'main', 'main', _('Settings'));
		s.tab('basic', _('Basic Settings'));
		s.tab('rules', _('Rule Groups (Shunt)'));
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

		o = s.taboption('basic', form.Flag, 'proxy_router', _('Proxy Router Itself'));
		o.description = _('Also route router-originated traffic through the proxy.');
		o.default = '0';
		o.depends('mode', 'redirect');

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

		// 3. Node Management Section with Tests
		s = m.section(form.GridSection, 'node', _('Node Management'));
		s.addremove = true;
		s.anonymous = false;
		s.sortable = true;

		o = s.option(form.Value, 'remark', _('Remark / Name'));
		o.placeholder = 'My VLESS Server';

		o = s.option(form.ListValue, 'type', _('Protocol'));
		o.value('vless', 'VLESS');
		o.default = 'vless';

		o = s.option(form.Value, 'server', _('Server Address'));
		o.datatype = 'host';
		o.placeholder = 'example.com';

		o = s.option(form.Value, 'port', _('Port'));
		o.datatype = 'port';
		o.default = '443';

		o = s.option(form.ListValue, 'transport', _('Transport'));
		o.value('xhttp', 'XHTTP');
		o.value('ws', 'WebSocket');
		o.value('httpupgrade', 'HTTPUpgrade');
		o.value('grpc', 'gRPC');
		o.value('tcp', 'TCP / Raw');
		o.default = 'xhttp';

		o = s.option(form.ListValue, 'security', _('Security'));
		o.value('tls', 'TLS');
		o.value('reality', 'REALITY');
		o.value('none', 'None');
		o.default = 'tls';

		// Node Diagnostics & Latency Tests (Ping, TCPing, URL Test) - Passwall2 Style
		o = s.option(form.DummyValue, '_ping', _('Ping'));
		o.modalonly = false;
		o.textvalue = function(section_id) {
			return createTestLink('ping', section_id);
		};
		o.cfgvalue = o.textvalue;

		o = s.option(form.DummyValue, '_tcping', _('TCPing'));
		o.modalonly = false;
		o.textvalue = function(section_id) {
			return createTestLink('tcping', section_id);
		};
		o.cfgvalue = o.textvalue;

		o = s.option(form.DummyValue, '_urltest', _('URL Test'));
		o.modalonly = false;
		o.textvalue = function(section_id) {
			return createTestLink('urltest', section_id);
		};
		o.cfgvalue = o.textvalue;

		// Modal options for editing node details
		o = s.option(form.TextValue, 'raw_link', _('Or Paste Share Link (vless://...)'));
		o.modalonly = true;
		o.rows = 4;
		o.placeholder = 'vless://uuid@host:port?type=xhttp...';

		o = s.option(form.Value, 'uuid', _('UUID / User ID'));
		o.modalonly = true;
		o.placeholder = '00000000-0000-0000-0000-000000000000';

		o = s.option(form.Value, 'path', _('Path'));
		o.modalonly = true;
		o.default = '/';

		o = s.option(form.Value, 'sni', _('SNI / ServerName'));
		o.modalonly = true;
		o.placeholder = 'example.com';

		o = s.option(form.Value, 'fp', _('Fingerprint'));
		o.modalonly = true;
		o.default = 'chrome';

		// 4. Routing Rule Groups (Passwall2 Style Shunting)
		s = m.section(form.GridSection, 'rule_group', _('Routing Rule Groups (Shunting)'),
			_('Configure rule groups and assign specific outbound nodes or direct bypass to each group.'));
		s.addremove = true;
		s.anonymous = false;
		s.sortable = true;

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'remarks', _('Group Name / Remark'));
		o.placeholder = 'My Rule Group';

		o = s.option(form.ListValue, 'target_node', _('Target Node'));
		o.value('_direct', _('Direct (Bypass Proxy)'));
		o.value('_default', _('Default Active Node (Proxy)'));
		o.value('_block', _('Block (Blackhole)'));
		nodes.forEach(function(node) {
			var label = (node.remark || node['.name']);
			o.value(node['.name'], _('Node: ') + label);
		});
		o.default = '_default';

		o = s.option(form.ListValue, 'network', _('Network'));
		o.value('tcp,udp', 'TCP + UDP');
		o.value('tcp', 'TCP Only');
		o.value('udp', 'UDP Only');
		o.default = 'tcp,udp';

		o = s.option(form.DynamicList, 'domain_list', _('Domain Matchers'));
		o.modalonly = true;
		o.placeholder = 'geosite:ir';
		o.description = _('Domains, geosite rules (e.g. geosite:ir, geosite:youtube), or regex (e.g. regexp:.*google.*).');

		o = s.option(form.DynamicList, 'ip_list', _('IP Matchers'));
		o.modalonly = true;
		o.placeholder = 'geoip:ir';
		o.description = _('IP CIDRs (e.g. 1.2.3.0/24) or geoip rules (e.g. geoip:ir, geoip:telegram).');

		o = s.option(form.Value, 'port', _('Port / Range'));
		o.modalonly = true;
		o.placeholder = '80,443';

		return m.render();
	}
});
