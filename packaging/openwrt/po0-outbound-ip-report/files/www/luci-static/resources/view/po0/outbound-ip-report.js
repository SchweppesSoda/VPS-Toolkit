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

		var wanOption = s.option(form.Value, 'wans', _('WAN 选择'));
		wanOption.default = 'all';
		wanOption.description = _('使用 all，或用英文分号分隔 wan1;wan2。');

		o = s.option(form.Value, 'interval_seconds', _('上报间隔（秒）'));
		o.datatype = 'uinteger';
		o.default = '3600';
		o.rmempty = false;

		o = s.option(form.Button, '_discover', _('读取 WAN 列表'));
		o.inputstyle = 'apply';
		o.onclick = function() {
			return fs.exec('/usr/libexec/po0-outbound-ip-report-control', [ 'discover-wans' ]).then(function(res) {
				var raw = (res.stdout || '').trim();
				var wans = raw ? raw.split(/\s+/) : [];
				var selection = wanOption.formvalue('main') || wanOption.cfgvalue('main') || 'all';
				if (!wans.length) {
					ui.addNotification(null, E('p', {}, [ res.stderr || _('读取失败：上游探针没有返回 WAN。') ]), 'error');
					return;
				}
				ui.addNotification(null, E('p', {}, [
					_('读取成功：发现 %d 个 WAN：%s。当前 WAN 选择为 %s；读取列表不会自动修改配置。')
						.format(wans.length, wans.join('、'), selection)
				]), 'info');
			}).catch(function(err) {
				ui.addNotification(null, E('p', {}, [ _('读取 WAN 失败：%s').format(err.message || err) ]), 'error');
			});
		};

		o = s.option(form.Button, '_test', _('立即测试上报'));
		o.inputstyle = 'apply';
		o.description = _('使用已保存的 UCI 配置执行；修改字段后请先保存并应用。');
		o.onclick = function() {
			return fs.exec('/usr/libexec/po0-outbound-ip-report-control', [ 'test' ]).then(function(res) {
				var output = res.stdout || res.stderr || _('测试没有返回输出。');
				ui.addNotification(null, E('pre', {}, [ output ]), res.code === 0 ? 'info' : 'error');
			}).catch(function(err) {
				ui.addNotification(null, E('pre', {}, [ _('测试上报失败：%s').format(err.message || err) ]), 'error');
			});
		};

		o = s.option(form.Button, '_status', _('查看最近结果'));
		o.onclick = function() {
			return fs.exec('/usr/libexec/po0-outbound-ip-report-control', [ 'status' ]).then(function(res) {
				var raw = res.stdout || res.stderr || '';
				var observed = raw.match(/^observed_at=([0-9]+)$/m);
				var exitCode = raw.match(/^exit_code=([0-9]+)$/m);
				var log = raw.replace(/^observed_at=[^\n]*\n?/m, '').replace(/^exit_code=[^\n]*\n?/m, '').trim();
				var summary = [];
				if (observed)
					summary.push(_('最近执行：%s').format(new Date(parseInt(observed[1], 10) * 1000).toLocaleString()));
				if (exitCode)
					summary.push(exitCode[1] === '0' ? _('执行结果：成功（exit 0）') : _('执行结果：失败（exit %s）').format(exitCode[1]));
				if (log)
					summary.push(_('最近输出：') + '\n' + log);
				ui.addNotification(null, E('pre', {}, [ summary.join('\n') || _('暂无运行记录') ]),
					exitCode && exitCode[1] !== '0' ? 'error' : 'info');
			}).catch(function(err) {
				ui.addNotification(null, E('p', {}, [ _('读取最近结果失败：%s').format(err.message || err) ]), 'error');
			});
		};

		return m.render();
	}
});
