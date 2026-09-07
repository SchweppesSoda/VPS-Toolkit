'use strict';
'require view';
'require form';
'require fs';
'require uci';
'require rpc';

var commitReporter = rpc.declare({ object: 'uci', method: 'commit', params: [ 'config' ], reject: true });

var CONTROL = '/usr/libexec/po0-outbound-ip-report-control';
var channelActionRunning = {};
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
		return _('槽位 %s（@%s）').format(numericSlot, slot);
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
			parsed.message || _('尚未读取官方状态。点击“查询官方白名单”查看每个 WAN 的出口和白名单。')
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

// Form edits stay in the native JSON data adapter until an explicit channel save.
// In particular, TableSection add/remove must not stage another channel in UCI.
function reporterFormData() {
 var data = {};
 uci.sections('po0_outbound_ip_report', null, function(section) {
  var type = section['.type'];
  if (!data[type]) data[type] = [];
  data[type].push(JSON.parse(JSON.stringify(section)));
 });
 return data;
}

function persistReporterChannel(map) {
 var config = 'po0_outbound_ip_report';
 var channel = map.po0SaveChannel;
 return Promise.resolve().then(function() {
  uci.unload(config);
  return uci.load(config);
 }).then(function() {
  (map.channelKeys[channel] || []).forEach(function(key) {
   uci.set(config, 'main', key, map.data.get(config, 'main', key));
  });
  if (channel === 'official') ['official_target', 'official_binding'].forEach(function(type) {
   var rows = map.data.sections(config, type);
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
	return map.save().then(function() { return map.persistChannel ? map.persistChannel() : null; }).then(function() { return commitReporter('po0_outbound_ip_report'); }).then(function() {
        return Promise.all(['official'].map(function(channel) { return refreshChannelResult(channel).catch(function() {}); }));
    });
}

function runChannelAction(map, channel, action) {
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
   var m = new form.Map('po0_outbound_ip_report', _('PO0 出口上报'),
    _('官方防火墙按已配置 WAN 查询白名单，缺失时才加白。目标、槽位与源地址在本机保存。'));
   m.data = new form.JSONMap(reporterFormData()).data;
   m.channelKeys = { official: [], network: ['enabled'] };
   m.persistChannel = function() { return persistReporterChannel(m); };
   var addSection = m.data.add;
   m.data.add = function(config, type, name) {
    if (!name) do { name = type + '_' + Math.random().toString(16).slice(2, 10); } while (this.get(config, name));
    return addSection.call(this, config, type, name);
   };
   var common = m.section(form.NamedSection, 'main', 'reporter', _('自动上报'));
   var o = common.option(form.Flag, 'enabled', _('启用自动上报服务'));
   o.default = '0'; o.rmempty = false;
   o.description = _('后台服务总开关；定期上报和网络变化可分别设置。');
   var commonParse = common.parse;
   common.parse = function() { return m.po0SaveChannel && m.po0SaveChannel !== 'network' ? Promise.resolve() : commonParse.apply(this, arguments); };
   var s = m.section(form.NamedSection, 'main', 'reporter', _('上报通道'));
   s.tab('official', _('PO0 官方防火墙'));
   s.tab('network', _('出口与探测'));
   function field(tab, type, key, title, description) {
    var item = type === form.SectionValue
     ? s.taboption.apply(s, arguments)
     : s.taboption(tab, type, key, _(title));
    if (description && type !== form.SectionValue) item.description = _(description);
    if (key[0] !== '_') m.channelKeys[tab].push(key);
    var parse = item.parse;
    item.parse = function() { return m.po0SaveChannel && m.po0SaveChannel !== tab ? Promise.resolve() : parse.apply(this, arguments); };
    return item;
   }
   function resultSection(channel) {
    var result = s.taboption(channel, form.SectionValue, '_' + channel + '_result', ResultSection, 'main', 'reporter');
    result.subsection.channel = channel;
   }
   function scopeTable(table) {
    ['handleAdd', 'handleRemove'].forEach(function(method) {
     var original = table[method];
     table[method] = function() {
      if (m.po0Saving) return Promise.resolve();
      m.po0Saving = true; m.po0SaveChannel = 'official';
      var self = this, args = arguments;
      return Promise.resolve().then(function() { return original.apply(self, args); })
       .finally(function() { delete m.po0SaveChannel; m.po0Saving = false; });
     };
    });
   }
   function saveChannel(channel) {
    if (m.po0Saving) return Promise.resolve();
    m.po0Saving = true; m.po0SaveChannel = channel;
    return saveReporter(m).then(function() { return fs.exec(CONTROL, ['reload']); })
     .then(function(res) { showActionResult(channel === 'network' ? 'official' : channel, res.code ? _('配置已保存，任务更新失败') : _('配置已保存'), _('本次未上报；后台按已有开关继续运行。'), res.code ? 'error' : 'success'); })
     .catch(function(err) { showActionResult(channel === 'network' ? 'official' : channel, _('保存失败'), err.message || err, 'error'); })
     .finally(function() { delete m.po0SaveChannel; m.po0Saving = false; });
   }
   function actions(channel) {
    var button = field(channel, form.Button, '_' + channel + '_save', '保存配置', '只保存本通道参数；不发起上报。');
    button.onclick = function() { return saveChannel(channel); };
    button = field(channel, form.Button, '_' + channel + '_report', '立即上报', '使用已保存配置，只上报本通道；无需开启自动上报，不等待间隔。');
    button.inputstyle = 'apply';
    button.onclick = function() { return runChannelAction(m, channel, channel + '-report'); };
    if (channel === 'official') {
     button = field(channel, form.Button, '_official_check', '查询官方白名单', '使用已保存配置；只查询，不保存配置，不新增或替换白名单槽位。');
     button.onclick = function() { return runChannelAction(m, channel, 'official-status'); };
    }
    button = field(channel, form.Button, '_' + channel + '_force', '强制上报', '使用已保存配置；绕过本机自动开关、间隔和受支持的 SSID 跳过条件，仍先查询官方白名单。');
    button.onclick = function() { return runChannelAction(m, channel, 'official-force-report'); };
    button = field(channel, form.Button, '_' + channel + '_config', '查看本机配置', '显示路由器上已保存的配置，不保存当前输入，不发起上报。');
    button.onclick = function() {
     var rows = [];
uci.sections('po0_outbound_ip_report','official_target',function(section) { rows.push((section.label || _('未命名目标')) + ' · ' + (section.enabled === '0' ? _('已停用') : _('已启用'))); });
     var key = 'official_interval_seconds';
     var seconds = uci.get('po0_outbound_ip_report','main',key);
     var enabled = uci.get('po0_outbound_ip_report','main',channel + '_timer_enabled') !== '0' && seconds !== '0';
     rows.push(_('上报间隔：') + (seconds && seconds !== '0' ? seconds : '600') + _(' 秒') + (enabled ? '' : _('（暂不使用）')));
     showActionResult(channel, _('本机配置'), rows.join('\n'), 'neutral');
    };
    button = field(channel, form.Button, '_' + channel + '_clear', '清除本通道配置', '只清除本通道目标和凭据并停用自动上报。');
    button.inputstyle = 'remove';
    button.onclick = function() {
     if (!window.confirm(_('确认清除此通道的目标和凭据？'))) return Promise.resolve();
     return fs.exec(CONTROL, [ channel + '-clear' ]).then(function(res) {
      showActionResult(channel, res.code ? _('清除失败') : _('配置已清除'), (res.stdout || '') + (res.stderr || ''), res.code ? 'error' : 'success');
      if (!res.code) window.location.reload();
     });
    };
    button = field(channel, form.Button, '_' + channel + '_recent', '查看最近结果', '只读取本通道最近一次手动或自动执行记录，不发起上报。');
    button.onclick = function() { return refreshChannelResult(channel); };
    resultSection(channel);
   }
   o = field('official', form.Flag, 'official_enabled', '官方自动上报', '需要同时开启页面上方的自动上报服务；先查询，缺失或槽位不匹配时才加白。');
   o.default = '0'; o.rmempty = false;
   o = field('official', form.Flag, 'official_timer_enabled', '启用定期上报', '关闭只停止本通道定期上报；保留网络变化触发和原间隔。');
   o.default = '1'; o.rmempty = false;
   o.cfgvalue = function(section_id) { var flag = m.data.get('po0_outbound_ip_report', section_id, 'official_timer_enabled'); return m.data.get('po0_outbound_ip_report', section_id, 'official_interval_seconds') === '0' ? '0' : flag == null ? '1' : flag; };
   o = field('official', form.Value, 'official_interval_seconds', '上报间隔（秒）', '默认 600 秒；关闭定期上报时暂不使用，保留此值供恢复使用。');
   o.datatype = 'and(uinteger,min(60))'; o.default = '600'; o.rmempty = false;
   o.cfgvalue = function(section_id) { var seconds = m.data.get('po0_outbound_ip_report', section_id, 'official_interval_seconds'); return seconds === '0' ? '600' : seconds; };
   o = field('official', form.DummyValue, '_official_expiry', '白名单有效期（TTL）');
   o.rawhtml = false; o.cfgvalue = function() { return _('由官方服务管理'); };
   o = field('official', form.Flag, 'official_network_enabled', '网络变化时上报', '本机接口上线、地址或路由变化时检查白名单，不受上报间隔限制。旁路网关无法直接收到上游 WAN 事件，建议保留定期上报。');
   o.default = '1'; o.rmempty = false;
   var targets = field('official', form.SectionValue, '_official_targets', form.TableSection, 'official_target', null, _('官方目标与 Token')).subsection;
   scopeTable(targets);
   targets.anonymous = true; targets.addremove = true; targets.sortable = true;
   targets.description = _('每个目标对应 PO0 防火墙页面的一份完整 Token。输入 pgnfw_xxxx 整段，必须包含 pgnfw_ 前缀；也可粘贴完整加白链接。Token 在这里直接显示。');
   o = targets.option(form.Value, 'label', _('目标名称')); o.rmempty = false;
   o = targets.option(form.Flag, 'enabled', _('启用目标')); o.default = '1'; o.rmempty = false;
   o = targets.option(form.Value, 'token', _('完整官方 Token'));
   o.password = false; o.rmempty = true; o.placeholder = 'pgnfw_xxxxxxxxx';
   o.description = _('例如链接 /api/firewall/pgnfw_xxxx/add 中，应复制 pgnfw_xxxx，不包含 /add。');
   o.validate = function(section_id, value) {
    var token = normalizeOfficialToken(value);
    if (!token && m.data.get('po0_outbound_ip_report', section_id, 'enabled') === '0') return true;
    return /^pgnfw_[A-Za-z0-9._~-]{1,240}$/.test(token) || _('请输入完整的 pgnfw_ 开头 Token，或粘贴官方加白链接。');
   };
   o.write = function(section_id, value) { return m.data.set('po0_outbound_ip_report', section_id, 'token', normalizeOfficialToken(value)); };
   var bindings = field('official', form.SectionValue, '_official_bindings', form.TableSection, 'official_binding', null, _('出口与槽位')).subsection;
   scopeTable(bindings);
   bindings.anonymous = true; bindings.addremove = true; bindings.sortable = true;
   bindings.description = _('每行指定一个目标使用的出口。单线启用一行，双线启用两行；同一目标的不同设备或 WAN 请分配不同固定槽位，避免相互覆盖。');
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
   o.description = _('槽位 1 = @0，槽位 2 = @1，槽位 3 = @2，槽位 4 = @3，槽位 5 = @4，与其它客户端 Token 后的 @编号一一对应。“自动”不指定固定槽位；本页 Token 只填 Token，槽位在此选择。更换槽位可能替换该位置已有的网段。');
   actions('official');
   s.taboption('official', form.SectionValue, '_official_status', OfficialStatusSection, 'main', 'reporter');

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
   o = field('network', form.Button, '_network_save', '保存通用配置', '只保存后台总开关及官方使用的出口与探测参数；不发起上报。');
   o.onclick = function() { return saveChannel('network'); };
   o = field('network', form.Button, '_discover', '查看可用 WAN');
   o.onclick = function() {
    return fs.exec(CONTROL,['discover-wans']).then(function(res) {
     showActionResult('official', _('可用 WAN'), res.stdout || res.stderr || _('未发现可用 WAN'), res.code ? 'error' : 'neutral');
    });
   };
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
