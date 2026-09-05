'use strict';
'require view';
'require form';
'require fs';
'require uci';
'require rpc';

var commitReporter = rpc.declare({ object: 'uci', method: 'commit', params: [ 'config' ], reject: true });

var CONTROL = '/usr/libexec/po0-outbound-ip-report-control';
var channelActionRunning = false;
var RESULT_CSS = [
	'.po0-report-page [data-tab-active="false"]{display:none!important;}',
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
		var channel = this.channel || 'worker';
		return Promise.resolve(E('div', { 'class': 'cbi-section po0-result-section' }, [
			E('style', {}, [ RESULT_CSS ]),
			E('h3', {}, [ _('操作结果') ]),
			E('div', {
				'id': 'po0-' + channel + '-action-result',
				'class': 'po0-result-card is-neutral',
				'role': 'status',
				'aria-live': 'polite',
				'aria-busy': 'false'
			}, [
				E('div', { 'class': 'po0-result-head' }, [
					E('span', { 'id': 'po0-' + channel + '-result-icon', 'class': 'po0-result-icon', 'aria-hidden': 'true' }, [ 'i' ]),
					E('div', { 'class': 'po0-result-heading' }, [
						E('strong', { 'id': 'po0-' + channel + '-result-title', 'class': 'po0-result-title' }, [ _('等待操作') ]),
						E('span', { 'id': 'po0-' + channel + '-result-meta', 'class': 'po0-result-meta' }, [ _('尚未执行任何操作') ])
					])
				]),
				E('div', { 'id': 'po0-' + channel + '-result-body', 'class': 'po0-result-body' }, [
					E('div', { 'class': 'po0-result-line' }, [ _('本通道的执行进度和结果会显示在这里。') ])
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
			parsed.message || _('尚未读取官方状态。点击“保存并查询白名单”查看每个 WAN 的出口和白名单。')
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
				_('这里显示每个官方目标绑定的 WAN、当前出口 IPv4、白名单和 5 个名额的使用情况。同一目标最多 5 个槽位；这里展示实际出口、槽位和最近执行结果。')
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

function showActionResult(channel, title, message, level) {
	var node = document.getElementById('po0-' + channel + '-action-result');
	if (!node)
		return;

	var states = {
		success: [ 'is-success', '✓' ],
		error: [ 'is-error', '!' ],
		working: [ 'is-working', '…' ],
		neutral: [ 'is-neutral', 'i' ]
	};
	var state = states[level] || states.neutral;
	var titleNode = document.getElementById('po0-' + channel + '-result-title');
	var metaNode = document.getElementById('po0-' + channel + '-result-meta');
	var iconNode = document.getElementById('po0-' + channel + '-result-icon');
	var bodyNode = document.getElementById('po0-' + channel + '-result-body');

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
	var successPattern = /PO0 Outbound IP Report 已完成：(?:上游路由器 )?WAN ([^的\r\n]+)的公网出口 IPv4 ([0-9.]+) 已被 LAN Worker 接收[^\r\n]*/g;
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

function channelResult(channel, raw, code) {
	if (channel === 'worker') return formatRecentResult(raw);
	var parsed = renderOfficialStatus(raw);
	var running = /^status=running$/m.test(raw);
	var failed = code !== 0 || /^exit_code=[1-9]/m.test(raw) || parsed.rows.some(function(row) { return row.status === 'error'; });
	return {
		title: running ? _('官方上报中') : parsed.rows.length ? _('官方防火墙结果') : _('官方防火墙'),
		text: running ? _('正在查询当前出口，必要时加入白名单。') : officialActionSummary(parsed, 'official-report'),
		level: running ? 'working' : failed ? 'error' : parsed.rows.length ? 'success' : 'neutral',
		running: running
	};
}

function showChannelResult(channel, raw, code) {
	var result = channelResult(channel, raw, code || 0);
	showActionResult(channel, result.title, result.text, result.level);
	return result;
}

function pollChannelResult(channel, deadline) {
	return fs.exec(CONTROL, [ channel + '-progress' ]).then(function(res) {
		var result = showChannelResult(channel, (res.stdout || '') + '\n' + (res.stderr || ''), res.code);
		if (result.running && Date.now() < deadline)
			return waitFor(1500).then(function() { return pollChannelResult(channel, deadline); });
		if (result.running)
			showActionResult(channel, _('任务仍在运行'), _('稍后点击本通道的“最近结果”查看。'), 'working');
	}).catch(function(err) { showActionResult(channel, _('读取结果失败'), err.message || err, 'error'); });
}

function saveReporter(map) {
	return map.save().then(function() { return commitReporter('po0_outbound_ip_report'); }).then(function() {
        return Promise.all(['worker','official'].map(function(channel) { return refreshChannelResult(channel).catch(function() {}); }));
    });
}

function runChannelAction(map, channel, action) {
    if (channelActionRunning) {
        showActionResult(channel, _('已有操作正在执行'), _('请等当前上报或查询完成后，再操作这个通道。'), 'working');
        return Promise.resolve();
    }
    channelActionRunning = true;
	showActionResult(channel, _('正在保存并执行'), _('本次只操作当前通道。'), 'working');
	return saveReporter(map).then(function() { showActionResult(channel, _('正在执行'), _('正在处理本通道的请求。'), 'working'); return fs.exec(CONTROL, [ action ]); }).then(function(res) {
		var raw = (res.stdout || '') + '\n' + (res.stderr || '');
		if (action === 'official-status') {
			var parsed = renderOfficialStatus(raw);
			showActionResult(channel, _('官方状态'), officialActionSummary(parsed, action), res.code ? 'error' : 'neutral');
			return;
		}
		if (res.code) {
			showActionResult(channel, _('无法执行上报'), redactOfficialText(raw), 'error');
			return;
		}
		showChannelResult(channel, raw, res.code);
		return pollChannelResult(channel, Date.now() + 180000);
	}).catch(function(err) { showActionResult(channel, _('配置未保存或操作失败'), err.message || err, 'error'); }).finally(function() { channelActionRunning = false; });
}

function refreshChannelResult(channel) {
	return fs.exec(CONTROL, [ channel + '-result' ]).then(function(res) {
		showChannelResult(channel, (res.stdout || '') + '\n' + (res.stderr || ''), res.code);
	});
}

function normalizeOfficialToken(value) {
	var text = String(value == null ? '' : value).trim();
	var match = text.match(/^https:\/\/124\.221\.69\.228\/api\/firewall\/(pgnfw_[A-Za-z0-9._~-]{1,240})(?:\/add)?(?:\?slot=[0-4])?$/);
	return match ? match[1] : text;
}


return view.extend({
 render: function() {
  return uci.load('po0_outbound_ip_report').then(function() {
   var m = new form.Map('po0_outbound_ip_report', _('PO0 出口上报'),
    _('选择要使用的通道：自建防火墙经 LAN Worker 上报；官方防火墙直接向 PO0 加白。两者可单独使用，也可同时使用。'));
   var common = m.section(form.NamedSection, 'main', 'reporter', _('自动上报'));
   var o = common.option(form.Flag, 'enabled', _('启用自动上报服务'));
   o.default = '0'; o.rmempty = false;
   o.description = _('只控制后台定时任务。关闭后，两个通道仍可手动上报或查询。');
   var s = m.section(form.NamedSection, 'main', 'reporter', _('上报通道'));
   s.tab('worker', _('自建防火墙 · LAN Worker'));
   s.tab('official', _('PO0 官方防火墙'));
   s.tab('network', _('出口与探测'));
   function field(tab, type, key, title, description) {
    var item = s.taboption(tab, type, key, _(title));
    if (description) item.description = _(description);
    return item;
   }
   function resultSection(channel) {
    var result = s.taboption(channel, form.SectionValue, '_' + channel + '_result', ResultSection, 'main', 'reporter');
    result.subsection.channel = channel;
   }
   function actions(channel) {
    var button = field(channel, form.Button, '_' + channel + '_report', '保存并立即上报', '使用当前填写的配置，只上报本通道；无需开启自动上报。');
    button.inputstyle = 'apply';
    button.onclick = function() { return runChannelAction(m, channel, channel + '-report'); };
    if (channel === 'official') {
     button = field(channel, form.Button, '_official_check', '保存并查询白名单', '只查询，不新增或替换白名单槽位。');
     button.onclick = function() { return runChannelAction(m, channel, 'official-status'); };
    } else {
     button = field(channel, form.Button, '_worker_force', '忽略 SSID，保存并上报', '本次手动执行忽略下方的 Wi-Fi 跳过条件。');
     button.onclick = function() { return runChannelAction(m, channel, 'worker-force-report'); };
    }
    button = field(channel, form.Button, '_' + channel + '_recent', '最近结果', '读取本通道最近一次手动或自动执行记录。');
    button.onclick = function() { return refreshChannelResult(channel); };
    resultSection(channel);
   }
   o = field('worker', form.Flag, 'worker_enabled', '自动上报到 LAN Worker', '需要同时开启页面上方的自动上报服务。');
   o.default = '1'; o.rmempty = false;
   o = field('worker', form.Value, 'worker_url', 'LAN Worker 地址', '提交使用本机正常网络，遵循 OpenClash 规则；提交的公网 IP 由下方所选 WAN 独立探测。');
   o.placeholder = 'https://report.example.com/report'; o.rmempty = true;
   o = field('worker', form.Value, 'secret', 'LAN Worker 共享密钥');
   o.password = false; o.rmempty = true;
   o = field('worker', form.Value, 'source_id', '来源 ID', '用于标识这台设备；多 WAN 上报会自动追加 WAN 名称。');
   o.default = 'router-88-2'; o.rmempty = false;
   field('worker', form.Value, 'identity', '备注');
   o = field('worker', form.Value, 'wans', '上报哪些 WAN', '填写 wan1、wan2、wan1;wan2 或 all。出口对应关系在“出口与探测”中设置。');
   o.default = 'all'; o.value('wan1','WAN1'); o.value('wan2','WAN2'); o.value('wan1;wan2', _('WAN1 和 WAN2')); o.value('all', _('全部'));
   o = field('worker', form.Value, 'interval_seconds', '自动上报间隔（秒）');
   o.datatype = 'uinteger'; o.default = '3600'; o.rmempty = false;
   field('worker', form.Value, 'skip_wifi_ssids', '跳过 Wi-Fi SSID', '英文分号分隔；只影响本通道，路由器上的官方 WAN 上报不使用 SSID 条件。');
   o = field('worker', form.Flag, 'allow_http', '允许明文 HTTP（不推荐）', '仅 LAN Worker 地址使用 http:// 时需要。');
   o.default = '0';
   actions('worker');

   o = field('official', form.Flag, 'official_enabled', '自动上报到官方防火墙', '需要同时开启页面上方的自动上报服务；每 10 分钟查询，缺失或槽位不匹配时才加白。');
   o.default = '0'; o.rmempty = false;
   var targets = s.taboption('official', form.SectionValue, '_official_targets', form.TableSection, 'official_target', null, _('官方目标与 Token')).subsection;
   targets.anonymous = true; targets.addremove = true; targets.sortable = true;
   targets.description = _('每个目标对应 PO0 防火墙页面的一份完整 Token。输入 pgnfw_xxxx 整段，必须包含 pgnfw_ 前缀；也可粘贴完整加白链接。Token 在这里直接显示。');
   o = targets.option(form.Value, 'label', _('目标名称')); o.rmempty = false;
   o = targets.option(form.Flag, 'enabled', _('启用目标')); o.default = '1'; o.rmempty = false;
   o = targets.option(form.Value, 'token', _('完整官方 Token'));
   o.password = false; o.rmempty = true; o.placeholder = 'pgnfw_xxxxxxxxx';
   o.description = _('例如链接 /api/firewall/pgnfw_xxxx/add 中，应复制 pgnfw_xxxx，不包含 /add。');
   o.validate = function(section_id, value) {
    var token = normalizeOfficialToken(value);
    if (!token && uci.get('po0_outbound_ip_report', section_id, 'enabled') === '0') return true;
    return /^pgnfw_[A-Za-z0-9._~-]{1,240}$/.test(token) || _('请输入完整的 pgnfw_ 开头 Token，或粘贴官方加白链接。');
   };
   o.write = function(section_id, value) { return uci.set('po0_outbound_ip_report', section_id, 'token', normalizeOfficialToken(value)); };
   var bindings = s.taboption('official', form.SectionValue, '_official_bindings', form.TableSection, 'official_binding', null, _('出口与槽位')).subsection;
   bindings.anonymous = true; bindings.addremove = true; bindings.sortable = true;
   bindings.description = _('每行指定一个目标使用的出口。单线启用一行，双线启用两行；同一目标的不同设备或 WAN 请分配不同固定槽位，避免相互覆盖。');
   o = bindings.option(form.Flag, 'enabled', _('启用')); o.default = '1'; o.rmempty = false;
   o = bindings.option(form.ListValue, 'target', _('目标')); o.rmempty = false;
   o.renderWidget = function(section_id, option_index, cfgvalue) {
    this.keylist = []; this.vallist = [];
    var option = this;
    (uci.sections('po0_outbound_ip_report', 'official_target') || []).forEach(function(target) { option.value(target['.name'], target.label || target['.name']); });
    return form.ListValue.prototype.renderWidget.apply(this, arguments);
   };
   o = bindings.option(form.Value, 'wan', _('出口')); o.value('wan1','WAN1'); o.value('wan2','WAN2'); o.rmempty = false;
   o = bindings.option(form.ListValue, 'slot', _('槽位')); o.value('', _('自动（可能被轮换）'));
   for (var slot = 1; slot <= 5; slot++) o.value(String(slot - 1), _('固定槽位 %s').format(slot));
   o.description = _('界面槽位 1–5 对应 API 的 0–4；更换槽位可能替换该位置已有的网段。');
   actions('official');
   s.taboption('official', form.SectionValue, '_official_status', OfficialStatusSection, 'main', 'reporter');

   o = field('network', form.ListValue, 'probe_mode', '公网 IP 获取方式');
   o.value('source', _('本机按源地址直连探测（旁路网关）'));
   o.value('local', _('本机 WAN 接口探测（主路由）'));
   o.value('router', _('主路由 HTTP 探针（兼容）'));
   o.default = 'source'; o.rmempty = false;
   o.description = _('旁路网关自行探测真实 WAN 公网 IP，无需主路由 HTTP 服务。探测和官方查询/加白走所选 WAN 直连；提交到 LAN Worker 遵循本机 OpenClash 规则。');
   ['wan1','wan2'].forEach(function(wan) {
    var source = field('network', form.Value, 'official_source_' + wan, wan.toUpperCase() + ' 本机源地址', '一次配置 WAN 与本机专用 IPv4 的对应关系，用于真实 IP 探测和官方请求。上游按源地址固定到对应 WAN，透明代理须绕过这些源地址；不影响 LAN Worker 提交。');
    source.datatype = 'ip4addr'; source.rmempty = true;
    source.placeholder = wan === 'wan1' ? '192.168.88.250' : '192.168.88.251';
   });
   o = field('network', form.Value, 'router_probe_url', '主路由探针地址');
   o.depends('probe_mode','router'); o.placeholder = 'http://192.168.88.1/cgi-bin/po0-wan-probe'; o.rmempty = true;
   o = field('network', form.Value, 'ip_check_urls', '公网 IP 查询地址', '英文逗号分隔。源地址模式使用所选 WAN 直连探测；域名通过下方 DNS 服务器获取真实 IPv4。');
   o.depends('probe_mode','source'); o.depends('probe_mode','local'); o.placeholder = 'https://ip9.com.cn/get';
   o = field('network', form.Value, 'probe_dns_server', '探测 DNS 服务器', '向此服务器的 53 端口查询探测域名真实 IPv4，避免使用 Fake-IP；无需固定探测服务器 IP。');
   o.depends('probe_mode','source'); o.datatype = 'ip4addr'; o.default = '192.168.88.1'; o.rmempty = false;
   o = field('network', form.Button, '_discover', '查看可用 WAN');
   o.onclick = function() {
    return saveReporter(m).then(function() { return fs.exec(CONTROL,['discover-wans']); }).then(function(res) {
     showActionResult('worker', _('可用 WAN'), res.stdout || res.stderr || _('未发现可用 WAN'), res.code ? 'error' : 'neutral');
    });
   };
   return m.render().then(function(node) {
    node.classList.add('po0-report-page');
    window.setTimeout(function() {
     refreshChannelResult('worker'); refreshChannelResult('official');
    }, 0);
    return node;
   });
  });
 }
});
