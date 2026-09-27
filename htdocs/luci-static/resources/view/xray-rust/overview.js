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
			_('Lightweight, memory-efficient Rust port of Xray core supporting VLESS and XHTTP transports.'));

		// Status section
		s = m.section(form.NamedSection, '_status', '_status', _('Service Status'));
		s.anonymous = true;

		o = s.option(form.DummyValue, '_state', _('Running Status'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			if (isRunning) {
				return '<span style="color:green;font-weight:bold;">&#9679; ' +
					_('RUNNING') + ' (PID: ' + pid + ')</span>';
			} else {
				return '<span style="color:red;font-weight:bold;">&#9679; ' +
					_('STOPPED') + '</span>';
			}
		};

		// Main configuration
		s = m.section(form.NamedSection, 'main', 'xray-rust', _('Configuration'));
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable Service'));
		o.rmempty = false;
		o.default = '1';

		o = s.option(form.Value, 'socks_port', _('SOCKS5 Inbound Port'));
		o.datatype = 'port';
		o.default = '10808';
		o.placeholder = '10808';
		o.rmempty = false;

		o = s.option(form.ListValue, 'config_type', _('Configuration Source'));
		o.value('link', _('Share Link (vless://...)'));
		o.value('custom', _('Custom JSON Configuration'));
		o.default = 'link';

		o = s.option(form.TextValue, 'share_link', _('VLESS Share Link'));
		o.rows = 4;
		o.placeholder = 'vless://uuid@host:port?type=xhttp&...#tag';
		o.depends('config_type', 'link');
		o.rmempty = false;

		o = s.option(form.TextValue, 'custom_json', _('Raw Xray-Rust JSON'));
		o.rows = 15;
		o.monospace = true;
		o.placeholder = '{\n  "inbounds": [...],\n  "outbounds": [...]\n}';
		o.depends('config_type', 'custom');

		return m.render();
	}
});
