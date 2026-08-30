'use strict';
'require view';
'require form';
'require fs';
'require ui';

return view.extend({
	render: function() {
		var m = new form.Map('po0_wan_probe', _('PO0 WAN 探针'),
			_('只向允许的内网设备返回 mwan3 WAN 的公网 IPv4，不执行上报。'));
		var s = m.section(form.NamedSection, 'main', 'probe', _('探针设置'));
		s.anonymous = true;

		var o = s.option(form.Flag, 'enabled', _('启用探针'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.DynamicList, 'allowed_source', _('允许的来源 IP'));
		o.datatype = 'ip4addr';
		o.default = '192.168.88.2';
		o.rmempty = false;

		o = s.option(form.DynamicList, 'wan', _('允许查询的 WAN'));
		o.placeholder = _('留空表示全部已启用的 mwan3 WAN');

		o = s.option(form.Value, 'ip_check_urls', _('公网 IP 检测地址'));
		o.default = 'https://ip9.com.cn/get,https://myip.ipip.net/json';
		o.rmempty = false;

		o = s.option(form.Button, '_test', _('实时测试'));
		o.inputstyle = 'apply';
		o.onclick = function() {
			return fs.exec('/usr/libexec/po0-wan-probe-control', [ 'test' ]).then(function(res) {
				ui.addNotification(null, E('pre', {}, [ res.stdout || res.stderr || _('没有输出') ]));
			});
		};

		return m.render();
	}
});

