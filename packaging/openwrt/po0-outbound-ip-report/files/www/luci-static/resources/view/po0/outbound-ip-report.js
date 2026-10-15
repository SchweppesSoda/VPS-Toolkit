'use strict';
'require view';
'require form';
'require fs';
'require uci';
'require rpc';

var commitReporter = rpc.declare({ object: 'uci', method: 'commit', params: [ 'config' ], reject: true });

var CONTROL = '/usr/libexec/po0-outbound-ip-report-control';
var channelActionRunning = {};
var lastOfficialResult = '';
var RESULT_CSS = [
	".po0-report-page div[id$=\".secret\"]>.control-group,.po0-report-page div[id$=\".token\"]>.control-group{display:flex;flex-wrap:nowrap;align-items:center;gap:.4em;}",
	".po0-report-page div[id$=\".secret\"]>.control-group>.cbi-input-password,.po0-report-page div[id$=\".token\"]>.control-group>.cbi-input-password{flex:1 1 0;min-width:0!important;width:0!important;margin:0;}",
	".po0-report-page div[id$=\".secret\"]>.control-group>button,.po0-report-page div[id$=\".token\"]>.control-group>button{flex:0 0 auto;width:auto;margin:0;white-space:nowrap;}",
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
	'.po0-order-controls{display:inline-flex;gap:4px;margin-right:8px;}',
	'.po0-order-controls button{min-width:32px;min-height:32px;}',
	'.po0-order-handle{cursor:grab;}',
	'.po0-wan-group th{padding:10px;text-align:left;background:rgba(127,127,127,.1);}',
	'.po0-drop-before{box-shadow:inset 0 3px #5e72e4;}',
	'.po0-drop-after{box-shadow:inset 0 -3px #5e72e4;}',
	'@media(max-width:600px){.po0-result-body{margin-left:0}.po0-result-card{padding:14px}}'
].join('');

var ResultSection = form.NamedSection.extend({
	render: function() {
		var channel = this.channel || 'official';
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
					E('div', { 'class': 'po0-result-line' }, [ _('执行进度和结果会显示在这里。') ])
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
		binding: safeOfficialText(item && (item.binding || item.binding_id), ''),
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
				if ((key === 'target' && current.target) || (key === 'binding' && current.binding))
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
		return _('槽位 %s（@%s）').format(numericSlot, slot);
	}
	return _('未知');
}

function renderOfficialStatus(raw) {
	var box = document.getElementById('po0-official-status');
	var parsed = parseOfficialStatus(raw);
	lastOfficialResult = raw;
	var displayRows = orderedOfficialRows(parsed.rows);
	var table;
	var tbody;
	if (!box)
		return parsed;
	while (box.firstChild)
		box.removeChild(box.firstChild);
	if (!displayRows.length) {
		box.appendChild(E('p', { 'class': 'po0-muted' }, [
			parsed.message || _('添加目标和 WAN 后，点击“查询白名单”查看状态。')
		]));
		return parsed;
	}
	table = E('table', { 'class': 'table' }, [
		E('thead', {}, [ E('tr', {}, [
			E('th', {}, [ _('目标') ]),
			E('th', {}, [ _('WAN') ]),
			E('th', {}, [ _('槽位') ]),
			E('th', {}, [ _('出口 IP') ]),
			E('th', {}, [ _('白名单') ]),
			E('th', {}, [ _('结果') ])
		]) ]),
		tbody = E('tbody', {})
	]);
	displayRows.forEach(function(row) {
		var statusClass = officialStatusClass(row.status);
		var statusParts = [ E('strong', { 'class': statusClass }, [ officialStatusLabel(row.status) ]) ];
		var targetLabel = row.label || row.target;
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
			E('h3', {}, [ _('状态') ]),
			E('p', { 'class': 'po0-official-help' }, [
				_('按已保存的目标和 WAN 顺序显示最近结果。每个目标最多 5 个槽位；保存只调整配置和显示顺序，不查询或上报。')
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
	var parsed = renderOfficialStatus(raw);
	var running = /^status=running$/m.test(raw);
	var failed = code !== 0 || /^exit_code=[1-9]/m.test(raw) || parsed.rows.some(function(row) { return row.status === 'error'; });
	return {
		title: running ? _('上报中') : parsed.rows.length ? _('上报结果') : _('暂无结果'),
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
			showActionResult(channel, _('任务仍在运行'), _('稍后点击“最近结果”查看。'), 'working');
	}).catch(function(err) { showActionResult(channel, _('读取结果失败'), err.message || err, 'error'); });
}

// All edits, including add/remove/reorder, stay local until the one apply action.
function reporterFormData() {
 var data = {};
 uci.sections('po0_outbound_ip_report', null, function(section) {
  var type = section['.type'];
  if (!data[type]) data[type] = [];
  data[type].push(JSON.parse(JSON.stringify(section)));
 });
 return data;
}

function orderedBindings(data, config) {
 var targets = data.sections(config, 'official_target').map(function(row) { return row['.name']; });
 return data.sections(config, 'official_binding').map(function(row, index) {
  var rank = targets.indexOf(row.target);
  return { row: row, rank: rank < 0 ? targets.length : rank, index: index };
 }).sort(function(a, b) { return a.rank - b.rank || a.index - b.index; })
  .map(function(item) { return item.row; });
}

// Cached results follow saved configuration, including after a pure reorder.
// A changed target/WAN/slot must not inherit the previous binding's success.
function orderedOfficialRows(rows) {
 var config = 'po0_outbound_ip_report';
 return orderedBindings(uci, config).map(function(binding) {
  var target = uci.get(config, binding.target) || {};
  var cached = rows.find(function(row) {
   return (!row.binding || row.binding === binding['.name']) && row.target === binding.target &&
    row.wan === binding.wan && row.slot === String(binding.slot || '');
  });
  var enabled = binding.enabled !== '0' && target.enabled !== '0';
  return Object.assign(officialRowFromObject({
   target: binding.target, wan: binding.wan, slot: binding.slot,
   status: enabled ? 'unknown' : 'disabled', message: enabled ? _('尚未查询此配置。') : ''
  }, 5), cached || {}, {
   label: safeOfficialText(target.label, ''), enabled: enabled
  });
 });
}

function moveReporterRow(map, type, id, neighbor, after) {
 var config = 'po0_outbound_ip_report';
 var row = map.data.get(config, id);
 var other = map.data.get(config, neighbor);
 if (!row || !other || id === neighbor || row['.type'] !== type || other['.type'] !== type)
  return false;
 if (type === 'official_binding' && row.target !== other.target)
  return false;
 return map.data.move(config, id, neighbor, after);
}

var OrderedTableSection = form.TableSection.extend({
 cfgsections: function() {
  return (this.sectiontype === 'official_binding'
   ? orderedBindings(this.map.data, this.map.config)
   : this.map.data.sections(this.map.config, this.sectiontype))
   .map(function(row) { return row['.name']; });
 },
 peers: function(id) {
  var table = this;
  var target = table.map.data.get(table.map.config, id, 'target');
  return table.cfgsections().filter(function(candidate) {
   return table.sectiontype !== 'official_binding' || table.map.data.get(table.map.config, candidate, 'target') === target;
  });
 },
 moveRow: function(id, neighbor, after) {
  var table = this, map = this.map;
  if (map.po0Saving || map.readonly) return Promise.resolve();
  map.po0Saving = true;
  return map.save(function() {
   moveReporterRow(map, table.sectiontype, id, neighbor, after);
  }, true).then(function() {
   renderOfficialStatus(lastOfficialResult);
   showActionResult('official', _('顺序尚未保存'), _('点击“保存并应用配置”后，状态区和后续执行将使用新顺序。'), 'neutral');
  }).catch(function(err) {
   showActionResult('official', _('无法调整顺序'), err.message || err, 'error');
  }).finally(function() { map.po0Saving = false; });
 },
 renderRowActions: function(id) {
  var table = this;
  var cell = form.TableSection.prototype.renderRowActions.apply(this, arguments);
  var peers = this.peers(id), index = peers.indexOf(id);
  var controls = E('span', { 'class': 'po0-order-controls' }, [
   E('button', {
    'type': 'button', 'class': 'cbi-button po0-order-handle', 'title': _('拖动调整顺序'),
    'aria-label': _('拖动调整顺序'), 'draggable': !this.map.readonly,
    'disabled': this.map.readonly || null,
    'dragstart': function(ev) { table.draggedRow = id; ev.dataTransfer.setData('text/plain', id); ev.dataTransfer.effectAllowed = 'move'; },
    'dragend': function() { table.draggedRow = null; }
   }, [ '☰' ])
  ]);
  [-1, 1].forEach(function(offset) {
   var neighbor = peers[index + offset];
   controls.appendChild(E('button', {
    'type': 'button', 'class': 'cbi-button', 'title': offset < 0 ? _('上移') : _('下移'),
    'aria-label': offset < 0 ? _('上移') : _('下移'),
    'disabled': !neighbor || table.map.readonly || null,
    'click': function() { return table.moveRow(id, neighbor, offset > 0); }
   }, [ offset < 0 ? '↑' : '↓' ]));
  });
  cell.firstChild.insertBefore(controls, cell.firstChild.firstChild);
  return cell;
 },
 renderContents: function(ids, nodes) {
  var table = this;
  var node = form.TableSection.prototype.renderContents.apply(this, arguments);
  var previousTarget = null;
  node.querySelectorAll('tr[data-sid]').forEach(function(row) {
   var id = row.getAttribute('data-sid');
   var clearDrop = function() { row.classList.remove('po0-drop-before', 'po0-drop-after'); };
   row.addEventListener('dragover', function(ev) {
    if (!table.draggedRow || table.draggedRow === id || table.peers(id).indexOf(table.draggedRow) < 0) return;
    ev.preventDefault(); clearDrop();
    row.classList.add(ev.clientY > row.getBoundingClientRect().top + row.offsetHeight / 2 ? 'po0-drop-after' : 'po0-drop-before');
   });
   row.addEventListener('dragleave', clearDrop);
   row.addEventListener('drop', function(ev) {
    ev.preventDefault();
    var after = row.classList.contains('po0-drop-after');
    clearDrop();
    var dragged = table.draggedRow;
    table.draggedRow = null;
    if (dragged && table.peers(id).indexOf(dragged) >= 0) table.moveRow(dragged, id, after);
   });
   if (table.sectiontype !== 'official_binding') return;
   var target = table.map.data.get(table.map.config, id, 'target') || '';
   if (target !== previousTarget) {
    var label = table.map.data.get(table.map.config, target, 'label') || _('未选择目标');
    row.parentNode.insertBefore(E('tr', { 'class': 'po0-wan-group' }, [
     E('th', { 'colspan': row.children.length, 'scope': 'rowgroup' }, [ label ])
    ]), row);
    previousTarget = target;
   }
  });
  return node;
 }
});

function persistReporterConfig(map) {
 var config = 'po0_outbound_ip_report';
 return Promise.resolve().then(function() {
  uci.unload(config);
  return uci.load(config);
 }).then(function() {
  map.configKeys.forEach(function(key) {
   uci.set(config, 'main', key, map.data.get(config, 'main', key));
  });
  ['official_target', 'official_binding'].forEach(function(type) {
   var rows = type === 'official_binding' ? orderedBindings(map.data, config) : map.data.sections(config, type);
   var ids = rows.map(function(row) { return row['.name']; });
   uci.sections(config, type).forEach(function(row) {
    if (ids.indexOf(row['.name']) < 0) uci.remove(config, row['.name']);
   });
   rows.forEach(function(row, index) {
    var id = row['.name'];
    var previous = uci.get(config, id);
    if (!previous) uci.add(config, type, id);
    Object.keys(Object.assign({}, previous || {}, row)).forEach(function(key) {
     if (key[0] !== '.') uci.set(config, id, key, row[key]);
    });
    if (index) uci.move(config, id, ids[index - 1], true);
   });
  });
  return uci.save();
 });
}

function saveReporter(map) {
	return map.save().then(function() { return persistReporterConfig(map); })
		.then(function() { return commitReporter('po0_outbound_ip_report'); })
		.then(function() { return fs.exec(CONTROL, ['reload']); })
		.then(function(res) {
			renderOfficialStatus(lastOfficialResult);
			return res;
		});
}

function runChannelAction(map, channel, action) {
    if (map.po0Saving) return Promise.resolve();
    if (channelActionRunning[channel]) {
        showActionResult(channel, _('已有操作正在执行'), _('请等当前上报或查询完成后，再操作这个通道。'), 'working');
        return Promise.resolve();
    }
    channelActionRunning[channel] = true;
	showActionResult(channel, _('正在执行'), _('使用已保存配置，只操作当前通道。'), 'working');
	return fs.exec(CONTROL, [ action ]).then(function(res) {
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
	}).catch(function(err) { showActionResult(channel, _('操作失败'), err.message || err, 'error'); }).finally(function() { channelActionRunning[channel] = false; });
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
 handleSave: null,
 handleSaveApply: null,
 handleReset: null,
 render: function() {
  return uci.load('po0_outbound_ip_report').then(function() {
   var m = new form.Map('po0_outbound_ip_report', _('PO0 防火墙'),
    _('官方防火墙按已配置 WAN 查询白名单，缺失时才加白。目标、槽位与源地址在本机保存。'));
   m.data = new form.JSONMap(reporterFormData()).data;
   m.configKeys = ['enabled'];
   var addSection = m.data.add;
   m.data.add = function(config, type, name) {
    if (!name) do { name = type + '_' + Math.random().toString(16).slice(2, 10); } while (this.get(config, name));
    return addSection.call(this, config, type, name);
   };
   var common = m.section(form.NamedSection, 'main', 'reporter', _('自动上报'));
   var o = common.option(form.Flag, 'enabled', _('启用自动上报'));
   o.default = '0'; o.rmempty = false;
   o.description = _('后台服务总开关；定期上报和网络变化可分别设置。');
   var s = m.section(form.NamedSection, 'main', 'reporter');
   s.tab('official', _('目标与上报'));
   s.tab('network', _('出口与探测'));
   function field(tab, type, key, title, description) {
    var item = type === form.SectionValue
     ? s.taboption.apply(s, arguments)
     : s.taboption(tab, type, key, _(title));
    if (description && type !== form.SectionValue) item.description = _(description);
    if (key[0] !== '_') m.configKeys.push(key);
    return item;
   }
   function guardTableEdits(table) {
    ['handleAdd', 'handleRemove'].forEach(function(method) {
     var original = table[method];
     table[method] = function() {
      if (m.po0Saving) return Promise.resolve();
      m.po0Saving = true;
      var self = this, args = arguments;
      return Promise.resolve().then(function() { return original.apply(self, args); })
       .then(function() { renderOfficialStatus(lastOfficialResult); })
       .finally(function() { m.po0Saving = false; });
     };
    });
   }
   function saveConfiguration() {
    if (m.po0Saving) return Promise.resolve();
    m.po0Saving = true;
    return saveReporter(m)
     .then(function(res) { showActionResult('official', res.code ? _('配置已保存，应用失败') : _('配置已生效'), res.code ? _('后台任务未能更新，请重试保存。') : _('未主动触发上报。已运行的自动任务按计划继续；新启动的定期任务先等待一个周期。'), res.code ? 'error' : 'success'); })
     .catch(function(err) { showActionResult('official', _('保存失败'), err.message || err, 'error'); })
     .finally(function() { m.po0Saving = false; });
   }
   function actions(channel) {
    var button = field(channel, form.Button, '_' + channel + '_report', '立即上报', '使用已保存配置；无需开启自动上报，不等待间隔。');
    button.inputstyle = 'apply';
    button.onclick = function() { return runChannelAction(m, channel, channel + '-report'); };
    if (channel === 'official') {
     button = field(channel, form.Button, '_official_check', '查询白名单', '使用已保存配置；只查询，不保存配置，不新增或替换白名单槽位。');
     button.onclick = function() { return runChannelAction(m, channel, 'official-status'); };
    }
    button = field(channel, form.Button, '_' + channel + '_force', '强制上报', '使用已保存配置；绕过本机自动开关、间隔和受支持的 SSID 跳过条件，仍先查询官方白名单。');
    button.onclick = function() { return runChannelAction(m, channel, 'official-force-report'); };
    button = field(channel, form.Button, '_' + channel + '_config', '已保存配置', '显示已保存的目标和间隔，不保存当前输入，不发起上报。');
    button.onclick = function() {
     var rows = [];
     uci.sections('po0_outbound_ip_report','official_target',function(section) { rows.push((section.label || _('未命名目标')) + ' · ' + (section.enabled === '0' ? _('已停用') : _('已启用'))); });
     var key = 'official_interval_seconds';
     var seconds = uci.get('po0_outbound_ip_report','main',key);
     var enabled = uci.get('po0_outbound_ip_report','main',channel + '_timer_enabled') !== '0' && seconds !== '0';
     rows.push(_('上报间隔：') + (seconds && seconds !== '0' ? seconds : '600') + _(' 秒') + (enabled ? '' : _('（暂不使用）')));
     showActionResult(channel, _('本机配置'), rows.join('\n'), 'neutral');
    };
    button = field(channel, form.Button, '_' + channel + '_clear', '清除目标', '清除目标和凭据，并停用官方自动上报。');
    button.inputstyle = 'remove';
    button.onclick = function() {
     if (!window.confirm(_('确认清除全部目标和凭据？'))) return Promise.resolve();
     return fs.exec(CONTROL, [ channel + '-clear' ]).then(function(res) {
      showActionResult(channel, res.code ? _('清除失败') : _('配置已清除'), (res.stdout || '') + (res.stderr || ''), res.code ? 'error' : 'success');
      if (!res.code) window.location.reload();
     });
    };
    button = field(channel, form.Button, '_' + channel + '_recent', '最近结果', '读取最近一次手动或自动执行记录，不发起上报。');
    button.onclick = function() { return refreshChannelResult(channel); };
   }
   o = field('official', form.Flag, 'official_enabled', '自动上报此列表', '需同时开启上方总开关。先查询，缺失或槽位不匹配时才加白。');
   o.default = '0'; o.rmempty = false;
   o = field('official', form.Flag, 'official_timer_enabled', '定期上报', '关闭后保留原间隔，网络变化触发单独控制。');
   o.default = '1'; o.rmempty = false;
   o.cfgvalue = function(section_id) { var flag = m.data.get('po0_outbound_ip_report', section_id, 'official_timer_enabled'); return m.data.get('po0_outbound_ip_report', section_id, 'official_interval_seconds') === '0' ? '0' : flag == null ? '1' : flag; };
   o = field('official', form.Value, 'official_interval_seconds', '上报间隔（秒）', '默认 600 秒；关闭定期上报时暂不使用，保留此值供恢复使用。');
   o.datatype = 'and(uinteger,min(60))'; o.default = '600'; o.rmempty = false;
   o.cfgvalue = function(section_id) { var seconds = m.data.get('po0_outbound_ip_report', section_id, 'official_interval_seconds'); return seconds === '0' ? '600' : seconds; };
   o = field('official', form.DummyValue, '_official_expiry', '白名单有效期（TTL）');
   o.rawhtml = false; o.cfgvalue = function() { return _('由官方服务管理'); };
   o = field('official', form.Flag, 'official_network_enabled', '网络变化时上报', '本机接口上线、地址或路由变化时检查白名单，不受上报间隔限制。旁路网关无法直接收到上游 WAN 事件，建议保留定期上报。');
   o.default = '1'; o.rmempty = false;
   var targets = field('official', form.SectionValue, '_official_targets', OrderedTableSection, 'official_target', null, _('目标')).subsection;
   guardTableEdits(targets);
   targets.anonymous = true; targets.addremove = true;
   targets.description = _('拖动或用箭头调整目标顺序，下方 WAN 分组随之排列。每个目标填写一份完整 Token，必须包含 pgnfw_ 前缀；也可粘贴加白链接。');
   o = targets.option(form.Value, 'label', _('名称')); o.rmempty = false;
   o = targets.option(form.Flag, 'enabled', _('启用')); o.default = '1'; o.rmempty = false;
   o = targets.option(form.Value, 'token', _('Token'));
   o.password = false; o.rmempty = true; o.placeholder = 'pgnfw_xxxxxxxxx';
   o.description = _('例如链接 /api/firewall/pgnfw_xxxx/add 中，应复制 pgnfw_xxxx，不包含 /add。');
   o.validate = function(section_id, value) {
    var token = normalizeOfficialToken(value);
    if (!token && m.data.get('po0_outbound_ip_report', section_id, 'enabled') === '0') return true;
    return /^pgnfw_[A-Za-z0-9._~-]{1,240}$/.test(token) || _('请输入完整的 pgnfw_ 开头 Token，或粘贴官方加白链接。');
   };
   o.write = function(section_id, value) { return m.data.set('po0_outbound_ip_report', section_id, 'token', normalizeOfficialToken(value)); };
   var bindings = field('official', form.SectionValue, '_official_bindings', OrderedTableSection, 'official_binding', null, _('WAN 与槽位')).subsection;
   guardTableEdits(bindings);
   bindings.anonymous = true; bindings.addremove = true;
   bindings.description = _('按上方目标顺序分组，同一目标内可拖动或用箭头调整 WAN。不同设备或 WAN 请使用不同固定槽位，避免相互覆盖。');
   o = bindings.option(form.Flag, 'enabled', _('启用')); o.default = '1'; o.rmempty = false;
   o = bindings.option(form.ListValue, 'target', _('目标')); o.rmempty = false;
   o.renderWidget = function(section_id, option_index, cfgvalue) {
    this.keylist = []; this.vallist = [];
    var option = this;
    (m.data.sections('po0_outbound_ip_report', 'official_target') || []).forEach(function(target) { option.value(target['.name'], target.label || target['.name']); });
    return form.ListValue.prototype.renderWidget.apply(this, arguments);
   };
   o = bindings.option(form.Value, 'wan', _('出口')); o.value('wan1','WAN1'); o.value('wan2','WAN2'); o.rmempty = false;
   o = bindings.option(form.ListValue, 'slot', _('槽位')); o.value('', _('自动（可能被轮换）'));
   for (var slot = 1; slot <= 5; slot++) o.value(String(slot - 1), _('固定槽位 %s（@%s）').format(slot, slot - 1));
   o.description = _('槽位 1～5 对应其它客户端的 @0～@4；“自动”不固定位置。更换槽位可能替换该位置已有的网段。');
   actions('official');

   o = field('network', form.ListValue, 'probe_mode', '公网 IP 获取方式');
   o.value('source', _('本机按源地址直连探测（旁路网关）'));
   o.value('local', _('本机 WAN 接口探测（主路由）'));
   o.value('router', _('主路由 HTTP 探针（兼容）'));
   o.default = 'source'; o.rmempty = false;
   o.description = _('旁路网关自行探测真实 WAN 公网 IP，无需主路由 HTTP 服务。探测和官方查询/加白走所选 WAN 直连。');
   ['wan1','wan2'].forEach(function(wan) {
    var source = field('network', form.Value, 'official_source_' + wan, wan.toUpperCase() + ' 本机源地址', '一次配置 WAN 与本机专用 IPv4 的对应关系，用于真实 IP 探测和官方请求。上游按源地址固定到对应 WAN，透明代理须绕过这些源地址。');
    source.datatype = 'ip4addr'; source.rmempty = true;
    source.placeholder = wan === 'wan1' ? '192.168.88.250' : '192.168.88.251';
   });
   o = field('network', form.Value, 'router_probe_url', '主路由探针地址');
   o.depends('probe_mode','router'); o.placeholder = 'http://192.168.88.1/cgi-bin/po0-wan-probe'; o.rmempty = true;
   o = field('network', form.Value, 'ip_check_urls', '公网 IP 查询地址', '英文逗号分隔。源地址模式使用所选 WAN 直连探测；域名通过下方 DNS 服务器获取真实 IPv4。');
   o.depends('probe_mode','source'); o.depends('probe_mode','local'); o.placeholder = 'https://ip9.com.cn/get';
   o = field('network', form.Value, 'probe_dns_server', '探测 DNS 服务器', '向此服务器的 53 端口查询探测域名真实 IPv4，避免使用 Fake-IP；无需固定探测服务器 IP。');
   o.depends('probe_mode','source'); o.datatype = 'ip4addr'; o.default = '192.168.88.1'; o.rmempty = false;
   o = field('network', form.Button, '_discover', '可用 WAN');
   o.onclick = function() {
    return fs.exec(CONTROL,['discover-wans']).then(function(res) {
     showActionResult('official', _('可用 WAN'), res.stdout || res.stderr || _('未发现可用 WAN'), res.code ? 'error' : 'neutral');
    });
   };
   var apply = m.section(form.NamedSection, 'main', 'reporter');
   o = apply.option(form.Button, '_save', _('保存并应用配置'), _('保存全部设置和顺序，不主动触发上报。'));
   o.inputstyle = 'apply'; o.onclick = saveConfiguration;
   m.section(ResultSection, 'main', 'reporter');
   m.section(OfficialStatusSection, 'main', 'reporter');
   return m.render().then(function(node) {
    node.classList.add('po0-report-page');
    window.setTimeout(function() {
     refreshChannelResult('official');
    }, 0);
    return node;
   });
  });
 }
});
