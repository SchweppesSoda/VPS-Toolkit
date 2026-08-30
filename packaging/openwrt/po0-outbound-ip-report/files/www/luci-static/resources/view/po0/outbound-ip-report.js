'use strict';
'require view';
'require form';
'require fs';

var CONTROL = '/usr/libexec/po0-outbound-ip-report-control';
var RESULT_CSS = [
	'.po0-result-card{border:1px solid rgba(127,127,127,.22);border-left:4px solid #5e72e4;border-radius:14px;padding:16px 18px;background:rgba(127,127,127,.06);box-shadow:0 8px 24px rgba(0,0,0,.06);transition:border-color .2s ease,background .2s ease;}',
	'.po0-result-head{display:flex;align-items:center;gap:12px;}',
	'.po0-result-icon{display:inline-flex;align-items:center;justify-content:center;width:28px;height:28px;border-radius:50%;background:#5e72e4;color:#fff;font-weight:700;flex:0 0 28px;}',
	'.po0-result-heading{display:flex;flex-direction:column;min-width:0;}',
	'.po0-result-title{font-size:1rem;line-height:1.35;}',
	'.po0-result-meta{margin-top:2px;opacity:.62;font-size:.82rem;}',
	'.po0-result-body{display:grid;gap:6px;margin:12px 0 0 40px;line-height:1.65;}',
	'.po0-result-line{overflow-wrap:anywhere;}',
	'.po0-result-spacer{height:3px;}',
	'.po0-result-card.is-success{border-left-color:#2dce89;background:rgba(45,206,137,.08);}',
	'.po0-result-card.is-success .po0-result-icon{background:#2dce89;}',
	'.po0-result-card.is-error{border-left-color:#f5365c;background:rgba(245,54,92,.08);}',
	'.po0-result-card.is-error .po0-result-icon{background:#f5365c;}',
	'.po0-result-card.is-working{border-left-color:#fb6340;background:rgba(251,99,64,.08);}',
	'.po0-result-card.is-working .po0-result-icon{background:#fb6340;}',
	'.po0-result-card.is-neutral{border-left-color:#8898aa;}',
	'.po0-result-card.is-neutral .po0-result-icon{background:#8898aa;}',
	'@media(max-width:600px){.po0-result-body{margin-left:0}.po0-result-card{padding:14px}}'
].join('');

var ResultSection = form.NamedSection.extend({
	render: function() {
		return Promise.resolve(E('div', { 'class': 'cbi-section po0-result-section' }, [
			E('style', {}, [ RESULT_CSS ]),
			E('h3', {}, [ _('操作结果') ]),
			E('div', {
				'id': 'po0-action-result',
				'class': 'po0-result-card is-neutral',
				'role': 'status',
				'aria-live': 'polite',
				'aria-busy': 'false'
			}, [
				E('div', { 'class': 'po0-result-head' }, [
					E('span', { 'id': 'po0-result-icon', 'class': 'po0-result-icon', 'aria-hidden': 'true' }, [ 'i' ]),
					E('div', { 'class': 'po0-result-heading' }, [
						E('strong', { 'id': 'po0-result-title', 'class': 'po0-result-title' }, [ _('等待操作') ]),
						E('span', { 'id': 'po0-result-meta', 'class': 'po0-result-meta' }, [ _('尚未执行任何操作') ])
					])
				]),
				E('div', { 'id': 'po0-result-body', 'class': 'po0-result-body' }, [
					E('div', { 'class': 'po0-result-line' }, [ _('读取 WAN、测试上报或查看最近结果后，反馈会显示在这里。') ])
				])
			])
		]));
	}
});

function showActionResult(title, message, level) {
	var node = document.getElementById('po0-action-result');
	if (!node)
		return;

	var states = {
		success: [ 'is-success', '✓' ],
		error: [ 'is-error', '!' ],
		working: [ 'is-working', '…' ],
		neutral: [ 'is-neutral', 'i' ]
	};
	var state = states[level] || states.neutral;
	var titleNode = document.getElementById('po0-result-title');
	var metaNode = document.getElementById('po0-result-meta');
	var iconNode = document.getElementById('po0-result-icon');
	var bodyNode = document.getElementById('po0-result-body');

	node.className = 'po0-result-card ' + state[0];
	node.setAttribute('aria-busy', level === 'working' ? 'true' : 'false');
	titleNode.textContent = title;
	metaNode.textContent = _('更新时间：%s').format(new Date().toLocaleTimeString());
	iconNode.textContent = state[1];

	while (bodyNode.firstChild)
		bodyNode.removeChild(bodyNode.firstChild);

	String(message || '').split(/\r?\n/).forEach(function(line) {
		bodyNode.appendChild(line
			? E('div', { 'class': 'po0-result-line' }, [ line ])
			: E('div', { 'class': 'po0-result-spacer', 'aria-hidden': 'true' }));
	});
}

function formatRecentResult(raw) {
	var running = /^status=running$/m.test(raw);
	var idle = /^status=idle$/m.test(raw);
	var observed = raw.match(/^observed_at=([0-9]+)$/m);
	var exitCode = raw.match(/^exit_code=([0-9]+)$/m);
	var successPattern = /PO0 Outbound IP Report 已完成：上游路由器 WAN ([^的\r\n]+)的公网出口 IPv4 ([0-9.]+) 已被 LAN Worker 接收[^\r\n]*/g;
	var failurePattern = /PO0 Outbound IP Report 未完成：([^\r\n]+)/g;
	var summaryMatch = raw.match(/WAN 上报结束：成功 ([0-9]+) 条，失败 ([0-9]+) 条/);
	var lines = [];
	var wanLines = [];
	var failureLines = [];
	var match;

	if (idle)
		return { title: _('暂无上报记录'), text: _('服务尚未生成运行记录。'), level: 'neutral', running: false };

	if (observed) {
		var date = new Date(parseInt(observed[1], 10) * 1000);
		if (!isNaN(date.getTime()))
			lines.push(_('上报时间：%s').format(date.toLocaleString()));
	}
	if (running) {
		lines.push(_('后台任务正在执行，页面会自动刷新结果。'));
		return { title: _('正在测试上报'), text: lines.join('\n'), level: 'working', running: true };
	}
	if (exitCode)
		lines.push(exitCode[1] === '0' ? _('执行状态：成功') : _('执行状态：失败（exit %s）').format(exitCode[1]));

	while ((match = successPattern.exec(raw)) !== null)
		wanLines.push(_('%s：成功 · 公网 IPv4 %s').format(match[1], match[2]));
	while ((match = failurePattern.exec(raw)) !== null) {
		if (match[1].indexOf('WAN 上报结束：') !== 0)
			failureLines.push(match[1]);
	}

	if (wanLines.length) {
		lines.push('');
		lines.push(_('WAN 结果'));
		lines = lines.concat(wanLines);
	}
	if (failureLines.length) {
		lines.push('');
		lines.push(_('失败信息'));
		lines = lines.concat(failureLines.slice(-5));
	}
	if (summaryMatch) {
		lines.push('');
		lines.push(_('汇总：成功 %s 条 · 失败 %s 条').format(summaryMatch[1], summaryMatch[2]));
	}
	if (!wanLines.length && !failureLines.length && !summaryMatch)
		lines.push(_('没有找到可识别的上报明细。'));

	var failed = !!(exitCode && exitCode[1] !== '0');
	return {
		title: failed ? _('上报失败') : _('上报成功'),
		text: lines.join('\n') || _('暂无运行记录'),
		level: failed ? 'error' : 'success',
		running: false
	};
}

function waitFor(milliseconds) {
	return new Promise(function(resolve) {
		window.setTimeout(resolve, milliseconds);
	});
}

function pollManualResult(deadline, failures) {
	return fs.exec(CONTROL, [ 'test-status' ]).then(function(res) {
		var raw = res.stdout || res.stderr || '';
		var result = formatRecentResult(raw);

		if (result.running) {
			if (Date.now() >= deadline) {
				showActionResult(
					_('测试仍在后台运行'),
					_('已等待 180 秒。任务没有被取消，请稍后点击“查看最近结果”。'),
					'working');
				return;
			}
			showActionResult(result.title, result.text, result.level);
			return waitFor(1500).then(function() {
				return pollManualResult(deadline, 0);
			});
		}

		showActionResult(result.title, result.text, result.level);
	}).catch(function(err) {
		if (failures < 2 && Date.now() < deadline) {
			showActionResult(_('正在读取测试结果'), _('状态读取暂时失败，正在自动重试……'), 'working');
			return waitFor(2000).then(function() {
				return pollManualResult(deadline, failures + 1);
			});
		}
		showActionResult(_('读取测试结果失败'), err.message || err, 'error');
	});
}

function startManualTest(force) {
	showActionResult(
		force ? _('正在启动强制测试') : _('正在启动测试上报'),
		_('任务将在后台执行，页面会自动读取进度，不会再等待一个长时间 XHR。'),
		'working');

	return fs.exec(CONTROL, [ force ? 'test-force-start' : 'test-start' ]).then(function(res) {
		if (res.code !== 0) {
			showActionResult(_('无法启动测试'), res.stderr || res.stdout || _('控制程序返回错误。'), 'error');
			return;
		}
		return pollManualResult(Date.now() + 180000, 0);
	}).catch(function(err) {
		showActionResult(_('无法启动测试'), err.message || err, 'error');
	});
}

return view.extend({
	render: function() {
		var m = new form.Map('po0_outbound_ip_report', _('PO0 出口 IP 上报'),
			_('从上游路由探针读取一个或多个 WAN 公网 IPv4，并由本机提交到 LAN Worker。'));
		var s = m.section(form.NamedSection, 'main', 'reporter', _('上报设置'));
		s.anonymous = true;
		s.tab('basic', _('基础设置'));
		s.tab('advanced', _('高级设置'));

		var o = s.taboption('basic', form.Flag, 'enabled', _('启用 procd 定时上报'));
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('basic', form.Value, 'worker_url', _('LAN Worker URL'));
		o.placeholder = 'https://report.example.com/report';
		o.rmempty = false;

		o = s.taboption('basic', form.Value, 'source_id', _('来源 ID'));
		o.default = 'router-88-1';
		o.rmempty = false;

		o = s.taboption('basic', form.Value, 'identity', _('身份标签'));
		o.default = 'router-88-1-via-gateway';

		o = s.taboption('basic', form.Value, 'interval_seconds', _('上报间隔（秒）'));
		o.datatype = 'uinteger';
		o.default = '3600';
		o.rmempty = false;

		o = s.taboption('advanced', form.Value, 'secret', _('共享密钥'));
		o.password = true;
		o.rmempty = true;

		o = s.taboption('advanced', form.Flag, 'allow_http', _('允许明文 HTTP（不推荐）'));
		o.default = '0';
		o.description = _('仅当 Worker URL 以 http:// 开头时才需要开启。HTTP 会明文传输上报数据；使用 https:// 时请保持关闭。');

		o = s.taboption('advanced', form.Value, 'router_probe_url', _('主路由探针 URL'));
		o.default = 'http://192.168.88.1/cgi-bin/po0-wan-probe';
		o.rmempty = false;

		var wanOption = s.taboption('advanced', form.Value, 'wans', _('WAN 选择'));
		wanOption.default = 'all';
		wanOption.description = _('使用 all，或用英文分号分隔 wan1;wan2。');

		o = s.taboption('advanced', form.Value, 'ip_check_urls', _('公网 IP 探测 URL'));
		o.placeholder = 'https://ip9.com.cn/get';
		o.description = _('仅未使用上游路由探针时生效；多个 URL 用英文逗号分隔。');

		o = s.taboption('advanced', form.Value, 'skip_wifi_ssids', _('跳过 Wi-Fi SSID'));
		o.description = _('多个 SSID 用英文分号分隔；当前设备连接这些 Wi-Fi 时跳过定时上报。');

		var actions = m.section(form.NamedSection, 'main', 'reporter', _('手动操作'));
		actions.anonymous = true;

		o = actions.option(form.Button, '_discover', _('读取 WAN 列表'));
		o.inputstyle = 'apply';
		o.description = _('只读取上游探针，不修改当前 WAN 选择。');
		o.onclick = function() {
			showActionResult(_('正在读取 WAN'), _('正在连接上游路由探针……'), 'working');
			return fs.exec(CONTROL, [ 'discover-wans' ]).then(function(res) {
				var raw = (res.stdout || '').trim();
				var wans = raw ? raw.split(/\s+/) : [];
				var selection = wanOption.formvalue('main') || wanOption.cfgvalue('main') || 'all';
				if (!wans.length) {
					showActionResult(_('WAN 读取失败'), res.stderr || _('上游探针没有返回 WAN。'), 'error');
					return;
				}
				showActionResult(
					_('WAN 读取成功'),
					_('发现 %d 个 WAN：%s\n当前选择：%s\n本次读取没有修改配置。')
						.format(wans.length, wans.join('、'), selection),
					'success');
			}).catch(function(err) {
				showActionResult(_('WAN 读取失败'), err.message || err, 'error');
			});
		};

		o = actions.option(form.Button, '_test', _('立即测试上报'));
		o.inputstyle = 'apply';
		o.description = _('使用已保存的 UCI 配置启动后台测试；修改字段后请先保存并应用。');
		o.onclick = function() {
			return startManualTest(false);
		};

		o = actions.option(form.Button, '_test_force', _('忽略 SSID 立即上报'));
		o.inputstyle = 'apply';
		o.description = _('仅用于手动测试；本次忽略 Wi-Fi SSID 跳过列表。');
		o.onclick = function() {
			return startManualTest(true);
		};

		o = actions.option(form.Button, '_status', _('查看最近结果'));
		o.onclick = function() {
			showActionResult(_('正在读取结果'), _('正在读取最近一次自动或手动上报记录……'), 'working');
			return fs.exec(CONTROL, [ 'status' ]).then(function(res) {
				var result = formatRecentResult(res.stdout || res.stderr || '');
				showActionResult(result.title, result.text, result.level);
			}).catch(function(err) {
				showActionResult(_('读取最近结果失败'), err.message || err, 'error');
			});
		};

		m.section(ResultSection, 'main', 'reporter', _('操作结果'));
		return m.render();
	}
});
