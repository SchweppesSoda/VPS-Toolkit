'use strict';
'require view';
'require form';
'require fs';

var ActionResultValue = form.DummyValue.extend({
	renderWidget: function() {
		return E('div', {
			'id': 'po0-action-result',
			'class': 'alert-message notice'
		}, [ E('em', {}, [ _('尚未执行操作。') ]) ]);
	}
});

function showActionResult(message, level) {
	var node = document.getElementById('po0-action-result');
	if (!node)
		return;

	node.className = 'alert-message ' + (level === 'error' ? 'error' : 'notice');
	while (node.firstChild)
		node.removeChild(node.firstChild);
	node.appendChild(E('pre', { 'style': 'margin:0;white-space:pre-wrap' }, [ message ]));
}

function formatRecentResult(raw) {
	var observed = raw.match(/^observed_at=([0-9]+)$/m);
	var exitCode = raw.match(/^exit_code=([0-9]+)$/m);
	var successPattern = /PO0 Outbound IP Report 已完成：上游路由器 WAN ([^的\r\n]+)的公网出口 IPv4 ([0-9.]+) 已被 LAN Worker 接收[^\r\n]*/g;
	var failurePattern = /PO0 Outbound IP Report 未完成：([^\r\n]+)/g;
	var summaryMatch = raw.match(/WAN 上报结束：成功 ([0-9]+) 条，失败 ([0-9]+) 条/);
	var lines = [];
	var wanLines = [];
	var failureLines = [];
	var match;

	if (observed) {
		var date = new Date(parseInt(observed[1], 10) * 1000);
		if (!isNaN(date.getTime()))
			lines.push(_('最近上报时间：%s（浏览器本地时间）').format(date.toLocaleString()));
	}
	if (exitCode)
		lines.push(exitCode[1] === '0' ? _('执行结果：成功') : _('执行结果：失败（exit %s）').format(exitCode[1]));

	while ((match = successPattern.exec(raw)) !== null)
		wanLines.push(_('%s：成功，公网 IPv4 %s').format(match[1], match[2]));
	while ((match = failurePattern.exec(raw)) !== null) {
		if (match[1].indexOf('WAN 上报结束：') !== 0)
			failureLines.push(match[1]);
	}

	if (wanLines.length) {
		lines.push('');
		lines.push(_('WAN 结果：'));
		lines = lines.concat(wanLines);
	}
	if (failureLines.length) {
		lines.push('');
		lines.push(_('失败信息：'));
		lines = lines.concat(failureLines.slice(-5));
	}
	if (summaryMatch) {
		lines.push('');
		lines.push(_('汇总：成功 %s 条，失败 %s 条').format(summaryMatch[1], summaryMatch[2]));
	}
	if (!wanLines.length && !failureLines.length && !summaryMatch)
		lines.push(_('没有找到可识别的上报结果。'));

	return {
		text: lines.join('\n') || _('暂无运行记录'),
		error: !!(exitCode && exitCode[1] !== '0')
	};
}

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

		o = s.option(form.Value, 'ip_check_urls', _('公网 IP 探测 URL'));
		o.placeholder = 'https://ip9.com.cn/get';
		o.description = _('仅未使用上游路由探针时生效；多个 URL 用英文逗号分隔。');

		o = s.option(form.Value, 'skip_wifi_ssids', _('跳过 Wi-Fi SSID'));
		o.description = _('多个 SSID 用英文分号分隔；当前设备连接这些 Wi-Fi 时跳过定时上报。');

		o = s.option(form.Value, 'interval_seconds', _('上报间隔（秒）'));
		o.datatype = 'uinteger';
		o.default = '3600';
		o.rmempty = false;

		o = s.option(form.Button, '_discover', _('读取 WAN 列表'));
		o.inputstyle = 'apply';
		o.onclick = function() {
			showActionResult(_('正在读取上游路由 WAN 列表……'), 'info');
			return fs.exec('/usr/libexec/po0-outbound-ip-report-control', [ 'discover-wans' ]).then(function(res) {
				var raw = (res.stdout || '').trim();
				var wans = raw ? raw.split(/\s+/) : [];
				var selection = wanOption.formvalue('main') || wanOption.cfgvalue('main') || 'all';
				if (!wans.length) {
					showActionResult(res.stderr || _('读取失败：上游探针没有返回 WAN。'), 'error');
					return;
				}
				showActionResult(
					_('读取成功：发现 %d 个 WAN：%s。\n当前 WAN 选择：%s。\n读取操作不会自动修改配置。')
						.format(wans.length, wans.join('、'), selection), 'info');
			}).catch(function(err) {
				showActionResult(_('读取 WAN 失败：%s').format(err.message || err), 'error');
			});
		};

		o = s.option(form.Button, '_test', _('立即测试上报'));
		o.inputstyle = 'apply';
		o.description = _('使用已保存的 UCI 配置执行；修改字段后请先保存并应用。');
		o.onclick = function() {
			showActionResult(_('正在使用已保存配置测试上报……'), 'info');
			return fs.exec('/usr/libexec/po0-outbound-ip-report-control', [ 'test' ]).then(function(res) {
				var output = res.stdout || res.stderr || _('测试没有返回输出。');
				showActionResult(output, res.code === 0 ? 'info' : 'error');
			}).catch(function(err) {
				showActionResult(_('测试上报失败：%s').format(err.message || err), 'error');
			});
		};

		o = s.option(form.Button, '_test_force', _('忽略 SSID 立即上报'));
		o.inputstyle = 'apply';
		o.description = _('仅用于手动测试；本次忽略 Wi-Fi SSID 跳过列表。');
		o.onclick = function() {
			showActionResult(_('正在强制测试上报……'), 'info');
			return fs.exec('/usr/libexec/po0-outbound-ip-report-control', [ 'test-force' ]).then(function(res) {
				showActionResult(res.stdout || res.stderr || _('测试没有返回输出。'), res.code === 0 ? 'info' : 'error');
			}).catch(function(err) {
				showActionResult(_('强制测试上报失败：%s').format(err.message || err), 'error');
			});
		};

		o = s.option(form.Button, '_status', _('查看最近结果'));
		o.onclick = function() {
			showActionResult(_('正在读取最近结果……'), 'info');
			return fs.exec('/usr/libexec/po0-outbound-ip-report-control', [ 'status' ]).then(function(res) {
				var result = formatRecentResult(res.stdout || res.stderr || '');
				showActionResult(result.text, result.error ? 'error' : 'info');
			}).catch(function(err) {
				showActionResult(_('读取最近结果失败：%s').format(err.message || err), 'error');
			});
		};

		o = s.option(ActionResultValue, '_action_result', _('操作结果'));

		return m.render();
	}
});
