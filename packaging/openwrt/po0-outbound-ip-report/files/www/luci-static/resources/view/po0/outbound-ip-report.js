'use strict';
'require view';
'require form';
'require fs';
'require ui';

return view.extend({
	render: function() {
		var m = new form.Map('po0_outbound_ip_report', _('PO0 出口 IP 上报'),
			_('从上游路由探针读取一个或多个 WAN 公网 IPv4，并由本机提交到 LAN Worker。'));
		var s = m.section(form.NamedSection, 'main', 'reporter', _('上报设置'));
		s.anonymous = true;

		var o = s.option(form.Flag, 'enabled', _('启用定时上报'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'worker_url', _('LAN Worker URL'));
		o.placeholder = 'https://report.example.com/report';
		o.rmempty = false;

		o = s.option(form.Value, 'source_id', _('来源 ID'));
		o.default = 'router-88-1';
		o.rmempty = false;

		o = s.option(form.Value, 'identity', _('身份标签'));
		o.default = 'router-88-1-via-gateway';

		o = s.option(form.Value, 'secret', _('共享密钥'));
		o.password = true;
		o.rmempty = true;

		o = s.option(form.Flag, 'allow_http', _('允许 HTTP Worker'));
		o.default = '0';

		o = s.option(form.Value, 'router_probe_url', _('主路由探针 URL'));
		o.default = 'http://192.168.88.1/cgi-bin/po0-wan-probe';
		o.rmempty = false;

		o = s.option(form.Value, 'wans', _('WAN 选择'));
		o.default = 'all';
		o.description = _('使用 all，或用英文分号分隔 wan1;wan2。');

		o = s.option(form.Value, 'interval_seconds', _('上报间隔（秒）'));
		o.datatype = 'uinteger';
		o.default = '3600';
		o.rmempty = false;

		o = s.option(form.Button, '_discover', _('读取 WAN 列表'));
		o.inputstyle = 'apply';
		o.onclick = function() {
			return fs.exec('/usr/libexec/po0-outbound-ip-report-control', [ 'discover-wans' ]).then(function(res) {
				ui.addNotification(null, E('pre', {}, [ res.stdout || res.stderr || _('没有输出') ]));
			});
		};

		o = s.option(form.Button, '_test', _('立即测试上报'));
		o.inputstyle = 'apply';
		o.onclick = function() {
			return fs.exec('/usr/libexec/po0-outbound-ip-report-control', [ 'test' ]).then(function(res) {
				ui.addNotification(null, E('pre', {}, [ res.stdout || res.stderr || _('没有输出') ]));
			});
		};

		o = s.option(form.Button, '_status', _('查看最近结果'));
		o.onclick = function() {
			return fs.exec('/usr/libexec/po0-outbound-ip-report-control', [ 'status' ]).then(function(res) {
				ui.addNotification(null, E('pre', {}, [ res.stdout || res.stderr || _('暂无运行记录') ]));
			});
		};

		return m.render();
	}
});

