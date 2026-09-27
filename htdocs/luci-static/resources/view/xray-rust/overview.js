'use strict';
'require form';
'require fs';
'require rpc';
'require uci';
'require view';

var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: [ 'name' ],
	expect: { 'xray-rust': {} }
});

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
			_('High-performance, ultra-low-memory (6.5 MB RSS) Xray proxy client with transparent routing for OpenWrt.'));

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
		s.tab('routing', _('Routing & Shunting'));

		// --- Basic Settings Tab ---
		o = s.taboption('basic', form.Flag, 'enabled', _('Enable Service'));
		o.rmempty = false;
		o.default = '1';

		o = s.taboption('basic', form.ListValue, 'mode', _('Running Mode'));
		o.value('redirect', _('TCP Transparent Proxy (Redirect entire router & LAN)'));
		o.value('socks', _('SOCKS5 Only (Standalone local proxy)'));
		o.default = 'redirect';

		o = s.taboption('basic', form.ListValue, 'active_node', _('Active Node'));
		var nodes = uci.sections('xray-rust', 'node');
		nodes.forEach(function(node) {
			var label = (node.remark || node['.name']) + ' (' + (node.server || 'unknown') + ':' + (node.port || '443') + ')';
			o.value(node['.name'], label);
		});
		if (nodes.length > 0 && !uci.get('xray-rust', 'main', 'active_node')) {
			o.default = nodes[0]['.name'];
		}

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
		o.default = '1';
		o.depends('mode', 'redirect');

		// --- Routing & Shunting Tab ---
		o = s.taboption('routing', form.ListValue, 'routing_mode', _('Routing Mode'));
		o.value('bypass_lan', _('Bypass LAN & Private IPs (Global Proxy)'));
		o.value('bypass_iran', _('Bypass LAN + Iran Domestic Domains/IPs (geoip:ir / geosite:ir)'));
		o.default = 'bypass_lan';

		o = s.taboption('routing', form.DynamicList, 'direct_domain', _('Direct Domains (Whitelist)'));
		o.description = _('Domains that directly connect without going through the proxy.');
		o.placeholder = 'example.ir';

		o = s.taboption('routing', form.DynamicList, 'proxy_domain', _('Proxy Domains (Forced)'));
		o.description = _('Domains always routed through the proxy.');
		o.placeholder = 'google.com';

		o = s.taboption('routing', form.DynamicList, 'direct_ip', _('Direct CIDRs / IPs'));
		o.description = _('IP CIDRs to bypass (e.g. 10.0.0.0/8).');
		o.placeholder = '192.168.0.0/16';

		// 3. Node Management Section
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

		return m.render();
	}
});
