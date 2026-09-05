'use strict';
'require view';
'require form';
'require fs';
'require uci';

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
	'.po0-official-status{margin-top:10px;overflow-x:auto;}',
	'.po0-official-status table{width:100%;border-collapse:collapse;min-width:760px;}',
	'.po0-official-status th,.po0-official-status td{padding:9px 10px;border-bottom:1px solid rgba(127,127,127,.18);text-align:left;vertical-align:top;}',
	'.po0-official-status th{font-weight:600;white-space:nowrap;}',
	'.po0-official-status td{overflow-wrap:anywhere;}',
	'.po0-official-status .po0-status-ok{color:#16834b;font-weight:600;}',
	'.po0-official-status .po0-status-error{color:#c62828;font-weight:600;}',
	'.po0-official-status .po0-status-working{color:#b54b14;font-weight:600;}',
	'.po0-official-status .po0-status-neutral{color:#687585;}',
	'.po0-official-status .po0-muted{opacity:.68;}',
	'.po0-official-status .po0-status-note{white-space:pre-wrap;max-width:320px;}',
	'.po0-official-help{margin:0 0 12px;line-height:1.65;}',
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

function safeOfficialText(value, fallback) {
	var text = String(value == null ? '' : value).trim();
	if (!text || /(?:token|secret|authorization|bearer|pgnfw[_-])/i.test(text))
		return fallback || '';
	return text;
}

function redactOfficialText(value) {
	return String(value == null ? '' : value)
		.replace(/pgnfw[_-][A-Za-z0-9._~-]+/gi, '[已隐藏]')
		.replace(/((?:token|secret|authorization|bearer)\s*[:=]\s*)[^\s,;]+/gi, '$1[已隐藏]')
		.replace(/https?:\/\/[^\s]*?(?:pgnfw[_-]|token|secret)[^\s]*/gi, '[官方请求地址已隐藏]');
}

function safeOfficialIp(value) {
	var text = String(value == null ? '' : value).trim();
	var parts;
	if (!/^\d{1,3}(?:\.\d{1,3}){3}(?:\/\d{1,2})?$/.test(text))
		return '';
	parts = text.split('/')[0].split('.');
	if (parts.some(function(part) { return parseInt(part, 10) > 255; }))
		return '';
	return text;
}

function officialArray(value) {
	if (Array.isArray(value))
		return value;
	if (typeof value === 'string')
		return value.split(/[;,\s]+/).filter(function(item) { return item; });
	return [];
}

function officialStatusLabel(value) {
	var status = String(value == null ? '' : value).toLowerCase();
	var labels = {
		ok: _('正常'),
		success: _('已完成'),
		already_present: _('已在白名单'),
		unchanged: _('无需更新'),
		checked: _('检查完成'),
		working: _('处理中'),
		disabled: _('已停用'),
		error: _('失败'),
		failed: _('失败'),
		missing: _('未加白'),
		unknown: _('未知')
	};
	return labels[status] || safeOfficialText(value, _('未知'));
}

function officialStatusClass(value) {
	var status = String(value == null ? '' : value).toLowerCase();
	if ([ 'ok', 'success', 'already_present', 'unchanged', 'checked' ].indexOf(status) >= 0)
		return 'po0-status-ok';
	if ([ 'error', 'failed' ].indexOf(status) >= 0)
		return 'po0-status-error';
	if (status === 'missing')
		return 'po0-status-neutral';
	if (status === 'working' || status === 'pending')
		return 'po0-status-working';
	return 'po0-status-neutral';
}

function officialTimeLabel(value) {
	var timestamp = parseInt(value, 10);
	var date;
	if (!timestamp || isNaN(timestamp))
		return '';
	if (timestamp < 100000000000)
		timestamp *= 1000;
	date = new Date(timestamp);
	return isNaN(date.getTime()) ? '' : formatLocalDateTime(date);
}

function officialRowFromObject(item, defaultLimit) {
	var whitelist = officialArray(item && (item.whitelist || item.whitelist_ips || item.whitelistIps || item.ips));
	var used = parseInt(item && (item.used != null ? item.used : item.used_slots), 10);
	var limit = parseInt(item && item.limit, 10);
	var status = item && (item.status || item.state || item.result);
	whitelist = whitelist.map(safeOfficialIp).filter(function(ip) { return ip; });
	if (isNaN(used) || used < 0)
		used = whitelist.length;
	if (isNaN(limit) || limit < 1 || limit > 5)
		limit = defaultLimit || 5;
	return {
		target: safeOfficialText(item && (item.target || item.target_id || item.targetId), _('未命名目标')),
		label: safeOfficialText(item && (item.label || item.target_label || item.target_name), ''),
		wan: safeOfficialText(item && (item.wan || item.interface || item.logical_wan), _('未指定')),
		slot: item && item.slot != null ? String(item.slot) : '',
		enabled: item && (item.enabled === false || String(item.enabled) === '0') ? false : true,
		currentIp: safeOfficialIp(item && (item.current_ip || item.currentIp || item.ip)) || _('未读到'),
		whitelist: whitelist,
		used: Math.min(5, used),
		limit: limit,
		status: String(status == null ? 'unknown' : status).toLowerCase(),
		message: redactOfficialText(item && (item.message || item.error || item.detail || '')),
		checkedAt: officialTimeLabel(item && (item.checked_at || item.checkedAt || item.timestamp || item.time))
	};
}

function parseOfficialStatus(raw) {
	var text = String(raw == null ? '' : raw).trim();
	var payload = null;
	var rows = [];
	var message = '';
	var limit = 5;
	try {
		payload = text ? JSON.parse(text) : null;
	} catch (e) {
		payload = null;
	}
	if (payload) {
		limit = parseInt(payload.limit, 10);
		if (isNaN(limit) || limit < 1 || limit > 5)
			limit = 5;
		rows = payload.bindings || payload.results || payload.items || payload.entries || [];
		if (!Array.isArray(rows) && (payload.target || payload.wan || payload.currentIp || payload.current_ip))
			rows = [ payload ];
		if (!Array.isArray(rows))
			rows = [];
		rows = rows.map(function(item) { return officialRowFromObject(item, limit); });
		message = redactOfficialText(payload.message || payload.error || '');
	} else {
		/* Also accept the deliberately simple key=value format used by the shell
		 * control helper. Never copy unknown values into the page verbatim. */
		var current = {};
		var flush = function() {
			if (Object.keys(current).length)
				rows.push(officialRowFromObject(current, 5));
			current = {};
		};
		text.split(/\r?\n/).forEach(function(line) {
			var match = line.match(/^([A-Za-z0-9_.-]+)=(.*)$/);
			if (!line.trim()) {
				flush();
				return;
			}
			if (!match)
				return;
			if (/token|secret|authorization|bearer/i.test(match[1]))
				return;
			if (/^(?:binding|entry)(?:[_.-]|$)/i.test(match[1])) {
				var key = match[1].replace(/^(?:binding|entry)[_.-]?/i, '');
				if (key === 'target' && Object.keys(current).length)
					flush();
				current[key] = match[2];
			} else if (match[1] === 'message' || match[1] === 'error') {
				message = redactOfficialText(match[2]);
			}
		});
		flush();
	}
	return { rows: rows, message: message, raw: text };
}

function officialSlotLabel(value) {
	var slot = String(value == null ? '' : value).trim();
	var numericSlot;
	if (!slot)
		return _('自动');
	if (/^[0-4]$/.test(slot)) {
		numericSlot = parseInt(slot, 10) + 1;
		return _('槽位 %s').format(numericSlot);
	}
	return _('未知');
}

function renderOfficialStatus(raw) {
	var box = document.getElementById('po0-official-status');
	var parsed = parseOfficialStatus(raw);
	var table;
	var tbody;
	if (!box)
		return parsed;
	while (box.firstChild)
		box.removeChild(box.firstChild);
	if (!parsed.rows.length) {
		box.appendChild(E('p', { 'class': 'po0-muted' }, [
			parsed.message || _('尚未读取官方状态。点击“只读检查官方状态”查看每个 WAN 的出口和白名单。')
		]));
		return parsed;
	}
	table = E('table', { 'class': 'table' }, [
		E('thead', {}, [ E('tr', {}, [
			E('th', {}, [ _('目标') ]),
			E('th', {}, [ _('逻辑 WAN') ]),
			E('th', {}, [ _('固定槽位') ]),
			E('th', {}, [ _('当前出口') ]),
			E('th', {}, [ _('官方白名单') ]),
			E('th', {}, [ _('最近状态') ])
		]) ]),
		tbody = E('tbody', {})
	]);
	parsed.rows.forEach(function(row) {
		var statusClass = officialStatusClass(row.status);
		var statusParts = [ E('strong', { 'class': statusClass }, [ officialStatusLabel(row.status) ]) ];
		var targetLabel = row.label ? row.label + ' (' + row.target + ')' : row.target;
		if (!row.enabled)
			statusParts.unshift(E('span', { 'class': 'po0-muted' }, [ _('已停用') + ' · ' ]));
		if (row.message)
			statusParts.push(E('div', { 'class': 'po0-status-note' }, [ row.message ]));
		if (row.checkedAt)
			statusParts.push(E('div', { 'class': 'po0-muted' }, [ row.checkedAt ]));
		tbody.appendChild(E('tr', {}, [
			E('td', {}, [ targetLabel ]),
			E('td', {}, [ row.wan ]),
			E('td', {}, [ officialSlotLabel(row.slot) ]),
			E('td', {}, [ row.currentIp ]),
			E('td', {}, [ row.whitelist.length ? row.whitelist.join('、') : _('空'), ' · ', String(row.used), '/', String(row.limit) ]),
			E('td', {}, statusParts)
		]));
	});
	box.appendChild(table);
	return parsed;
}

var OfficialStatusSection = form.NamedSection.extend({
	render: function() {
		return Promise.resolve(E('div', { 'class': 'cbi-section po0-official-status-section' }, [
			E('h3', {}, [ _('PO0 官方防火墙状态') ]),
			E('p', { 'class': 'po0-official-help' }, [
				_('这里显示每个官方目标绑定的 WAN、当前出口 IPv4、白名单和 5 个名额的使用情况。主路由上的官方 WAN 绑定不套用客户端 SSID 跳过；SSID 只影响手机、电脑等本机上报。')
			]),
			E('div', { 'id': 'po0-official-status', 'class': 'po0-official-status', 'aria-live': 'polite' }, [
				E('p', { 'class': 'po0-muted' }, [ _('尚未读取官方状态。') ])
			])
		]));
	}
});

function pad2(value) {
	return String(value).padStart(2, '0');
}

function formatLocalDateTime(date) {
	return '%d-%s-%s %s:%s:%s'.format(
		date.getFullYear(),
		pad2(date.getMonth() + 1),
		pad2(date.getDate()),
		pad2(date.getHours()),
		pad2(date.getMinutes()),
		pad2(date.getSeconds()));
}

function formatDuration(totalSeconds) {
	var seconds = Math.max(0, Math.floor(totalSeconds));
	var hours = Math.floor(seconds / 3600);
	var minutes = Math.floor((seconds % 3600) / 60);
	var remainder = seconds % 60;

	if (hours)
		return _('%s 小时 %s 分 %s 秒').format(hours, minutes, remainder);
	if (minutes)
		return _('%s 分 %s 秒').format(minutes, remainder);
	return _('%s 秒').format(remainder);
}

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
	metaNode.textContent = _('页面刷新时间：%s').format(formatLocalDateTime(new Date()));
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
	var finished = raw.match(/^finished_at=([0-9]+)$/m);
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
		var startedAt = parseInt(observed[1], 10);
		var startedDate = new Date(startedAt * 1000);
		if (!isNaN(startedDate.getTime()))
			lines.push(_('任务开始时间：%s').format(formatLocalDateTime(startedDate)));
	}
	if (running) {
		lines.push(_('后台任务正在执行，页面会自动刷新结果。'));
		return { title: _('正在测试上报'), text: lines.join('\n'), level: 'working', running: true };
	}
	if (finished) {
		var finishedAt = parseInt(finished[1], 10);
		var finishedDate = new Date(finishedAt * 1000);
		if (!isNaN(finishedDate.getTime()))
			lines.push(_('任务完成时间：%s').format(formatLocalDateTime(finishedDate)));
		if (observed && finishedAt >= startedAt)
			lines.push(_('执行耗时：%s').format(formatDuration(finishedAt - startedAt)));
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

function officialActionSummary(parsed, action) {
	var rows = parsed.rows || [];
	var ok = rows.filter(function(row) {
		return [ 'ok', 'success', 'already_present', 'unchanged', 'checked' ].indexOf(row.status) >= 0;
	}).length;
	var failed = rows.filter(function(row) {
		return [ 'error', 'failed' ].indexOf(row.status) >= 0;
	}).length;
	var missing = rows.filter(function(row) {
		return row.status === 'missing';
	}).length;
	if (action === 'official-report') {
		if (rows.length)
			return _('官方上报完成：%s/%s 条成功%s。').format(ok, rows.length, failed ? _('，%s 条失败').format(failed) : '');
		return parsed.message || _('官方上报命令已完成，但没有返回可显示的明细。');
	}
	if (rows.length)
		if (missing)
			return _('官方状态读取完成：已读取 %s 条 WAN 绑定，其中 %s 个当前出口尚未加白。').format(rows.length, missing);
	if (rows.length)
		return _('官方状态读取完成：已读取 %s 条 WAN 绑定。').format(rows.length);
	return parsed.message || _('官方状态读取完成，但没有配置可显示的绑定。');
}

function runOfficialAction(action) {
	var isReport = action === 'official-report';
	showActionResult(
		isReport ? _('正在执行官方上报') : _('正在读取官方状态'),
		isReport
			? _('本次为手动执行；自动通道启用后按计划运行。只读检查不会修改白名单。')
			: _('只读取当前官方状态，不修改白名单。'),
		'working');
	return fs.exec(CONTROL, [ action ]).then(function(res) {
		var raw = res.stdout || res.stderr || '';
		var parsed = renderOfficialStatus(raw);
		if (res.code !== 0) {
			showActionResult(
				isReport ? _('官方上报失败') : _('读取官方状态失败'),
				redactOfficialText(parsed.message || _('后端命令返回错误；请查看服务日志。')),
				'error');
			return;
		}
		showActionResult(
			isReport ? _('官方上报完成') : _('官方状态读取完成'),
			officialActionSummary(parsed, action),
			'success');
	}).catch(function(err) {
		showActionResult(
			isReport ? _('官方上报失败') : _('读取官方状态失败'),
			redactOfficialText(err && err.message ? err.message : _('无法调用控制程序。')),
			'error');
	});
}

function refreshOfficialStatus() {
	return fs.exec(CONTROL, [ 'official-status' ]).then(function(res) {
		var raw = res.stdout || res.stderr || '';
		if (res.code === 0)
			renderOfficialStatus(raw);
		else
			renderOfficialStatus('message=' + redactOfficialText(_('官方状态暂时不可用；请使用“只读检查官方状态”重试。')));
	}).catch(function() {
		renderOfficialStatus('message=' + _('官方状态暂时不可用；请使用“只读检查官方状态”重试。'));
	});
}

return view.extend({
	render: function() {
		return uci.load('po0_outbound_ip_report').then(function() {
		var m = new form.Map('po0_outbound_ip_report', _('PO0 出口 IP 上报'),
			_('现有 LAN Worker 上报与 PO0 官方防火墙上报在同一页面独立配置。'));
		var s = m.section(form.NamedSection, 'main', 'reporter', _('上报设置'));
		s.anonymous = true;
		s.tab('basic', _('基础设置'));
		s.tab('advanced', _('高级设置'));

		var o = s.taboption('basic', form.Flag, 'enabled', _('启用 procd 定时上报'));
		o.default = '0';
		o.rmempty = false;
		o.description = _('总开关；关闭后现有 LAN Worker 和 PO0 官方两条自动通道都暂停。');

		o = s.taboption('basic', form.Flag, 'worker_enabled', _('启用 LAN Worker 上报'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('只控制现有 LAN Worker 通道；不影响 PO0 官方防火墙通道。');

		o = s.taboption('basic', form.Flag, 'official_enabled', _('启用 PO0 官方防火墙上报'));
		o.default = '0';
		o.rmempty = false;
		o.description = _('与 LAN Worker 上报独立；主路由上的每个官方 WAN 绑定会从指定 WAN 发出请求。官方自动通道固定每 600 秒检查一次。');

		o = s.taboption('basic', form.Value, 'worker_url', _('LAN Worker URL'));
		o.placeholder = 'https://report.example.com/report';
		o.rmempty = true;
		o.description = _('现有通道使用；只启用 PO0 官方上报时可以留空。');

		o = s.taboption('basic', form.Value, 'source_id', _('来源 ID'));
		o.default = 'router-88-1';
		o.rmempty = false;

		o = s.taboption('basic', form.Value, 'identity', _('身份标签'));
		o.default = 'router-88-1-via-gateway';

		o = s.taboption('basic', form.Value, 'interval_seconds', _('上报间隔（秒）'));
		o.datatype = 'uinteger';
		o.default = '3600';
		o.rmempty = false;
		o.description = _('只控制现有 LAN Worker 自动上报间隔；PO0 官方通道固定每 600 秒检查一次。');

		o = s.taboption('advanced', form.Value, 'secret', _('共享密钥'));
		o.password = true;
		o.rmempty = true;

		o = s.taboption('advanced', form.Flag, 'allow_http', _('允许明文 HTTP（不推荐）'));
		o.default = '0';
		o.description = _('仅当 Worker URL 以 http:// 开头时才需要开启。HTTP 会明文传输上报数据；使用 https:// 时请保持关闭。');

		o = s.taboption('advanced', form.Value, 'router_probe_url', _('主路由探针 URL'));
		o.default = 'http://192.168.88.1/cgi-bin/po0-wan-probe';
		o.rmempty = true;
		o.description = _('仅给现有 LAN Worker 通道读取上游 WAN；PO0 官方通道直接在实际主路由执行，不经过这个只读探针。');

		var wanOption = s.taboption('advanced', form.Value, 'wans', _('WAN 选择'));
		wanOption.default = 'all';
		wanOption.description = _('使用 all，或用英文分号分隔 wan1;wan2。');

		o = s.taboption('advanced', form.Value, 'ip_check_urls', _('公网 IP 探测 URL'));
		o.placeholder = 'https://ip9.com.cn/get';
		o.description = _('仅未使用上游路由探针时生效；多个 URL 用英文逗号分隔。');

		o = s.taboption('advanced', form.Value, 'skip_wifi_ssids', _('跳过 Wi-Fi SSID'));
		o.description = _('多个 SSID 用英文分号分隔；只影响当前设备上的客户端上报。主路由的 PO0 官方 WAN 绑定不套用 SSID 跳过。');

		var officialTargets = uci.sections('po0_outbound_ip_report', 'official_target') || [];
		var officialTargetSection = m.section(form.TableSection, 'official_target', _('PO0 官方目标'));
		officialTargetSection.anonymous = true;
		officialTargetSection.addremove = true;
		officialTargetSection.sortable = true;
		officialTargetSection.description = _('每行代表一个官方账号或小鸡目标。token 只保存到本机配置，不在页面回显；已有 token 留空即可保留。');

		o = officialTargetSection.option(form.Value, 'label', _('目标名称'));
		o.rmempty = false;
		o.placeholder = _('例如：新加坡小鸡');

		o = officialTargetSection.option(form.Flag, 'enabled', _('启用'));
		o.default = '1';
		o.rmempty = false;

		o = officialTargetSection.option(form.Value, 'token', _('官方 token'));
		o.password = true;
		o.rmempty = true;
		o.placeholder = _('已保存；留空保持不变');
		o.description = _('不会显示已保存内容；只有输入新值并保存才会替换。');
		o.cfgvalue = function() {
			return '';
		};
		o.write = function(section_id, value) {
			value = String(value == null ? '' : value).trim();
			if (!value)
				return Promise.resolve();
			return uci.set('po0_outbound_ip_report', section_id, 'token', value);
		};

		var officialBindingSection = m.section(form.TableSection, 'official_binding', _('PO0 官方 WAN 绑定'));
		officialBindingSection.anonymous = true;
		officialBindingSection.addremove = true;
		officialBindingSection.sortable = true;
		officialBindingSection.description = _('把同一个官方目标分别绑定到实际逻辑 WAN。每个绑定最多占用官方 5 个白名单名额中的一个；指定 WAN 失败时不会自动改走其他 WAN。');

		o = officialBindingSection.option(form.Flag, 'enabled', _('启用'));
		o.default = '1';
		o.rmempty = false;

		o = officialBindingSection.option(form.ListValue, 'target', _('官方目标'));
		o.rmempty = false;
		if (officialTargets.length) {
			officialTargets.forEach(function(section) {
				var id = section['.name'];
				var label = String(section.label || '').trim();
				if (!label)
					label = id;
				o.value(id, label);
			});
		} else {
			o.value('', _('请先添加官方目标'));
		}

		o = officialBindingSection.option(form.Value, 'wan', _('逻辑 WAN'));
		o.rmempty = false;
		o.placeholder = 'wan1';
		o.description = _('例如 wan1、wan2；必须是主路由上实际启用的 mwan3 逻辑接口。');

		o = officialBindingSection.option(form.ListValue, 'slot', _('固定槽位'));
		o.value('', _('自动选择'));
		for (var slot = 1; slot <= 5; slot++)
			o.value(String(slot - 1), _('槽位 %s').format(slot));
		o.default = '';
		o.description = _('留空由官方接口按默认规则处理；固定槽位 1-5 便于 WAN1/WAN2 长期一一对应。');

		m.section(OfficialStatusSection, 'main', 'reporter', _('PO0 官方状态'));

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

		o = actions.option(form.Button, '_official_status', _('只读检查官方状态'));
		o.inputstyle = 'apply';
		o.description = _('只读取每个官方 WAN 绑定的当前出口、白名单和名额，不执行加白。');
		o.onclick = function() {
			return runOfficialAction('official-status');
		};

	o = actions.option(form.Button, '_official_report', _('立即官方上报'));
		o.inputstyle = 'apply';
		o.description = _('本次为手动执行；自动通道启用后按计划运行。只读检查不会修改白名单。');
		o.onclick = function() {
			return runOfficialAction('official-report');
		};

		m.section(ResultSection, 'main', 'reporter', _('操作结果'));
		return m.render().then(function(node) {
			renderOfficialStatus('');
			window.setTimeout(refreshOfficialStatus, 0);
			return node;
		});
		});
	}
});
