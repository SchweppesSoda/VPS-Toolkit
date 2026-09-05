include $(TOPDIR)/rules.mk

PKG_NAME:=po0-outbound-ip-report
PKG_VERSION:=2026.09.05
PKG_RELEASE:=4
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/po0-outbound-ip-report
  SECTION:=net
  CATEGORY:=Network
  TITLE:=PO0 outbound IPv4 reporter
  DEPENDS:=+bash +curl +ca-bundle +jsonfilter +luci-base
endef

define Package/po0-outbound-ip-report/description
 Report selected WAN public IPv4 addresses to a PO0 LAN Worker and, optionally, the PO0 official firewall whitelist.
endef

define Package/po0-outbound-ip-report/conffiles
/etc/config/po0_outbound_ip_report
endef

define Build/Compile
endef

define Package/po0-outbound-ip-report/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/libexec $(1)/etc/init.d $(1)/etc/config $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) ./files/usr/sbin/po0-outbound-ip-report $(1)/usr/sbin/po0-outbound-ip-report
	$(INSTALL_BIN) $(TOPDIR)/po0-assets/po0-outbound-ip-report.sh $(1)/usr/libexec/po0-outbound-ip-report-engine
	$(INSTALL_BIN) ./files/usr/libexec/po0-outbound-ip-report-uci $(1)/usr/libexec/po0-outbound-ip-report-uci
	$(INSTALL_BIN) ./files/usr/libexec/po0-outbound-ip-report-service $(1)/usr/libexec/po0-outbound-ip-report-service
	$(INSTALL_BIN) ./files/usr/libexec/po0-outbound-ip-report-control $(1)/usr/libexec/po0-outbound-ip-report-control
	$(INSTALL_BIN) ./files/usr/libexec/po0-outbound-ip-report-manual-runner $(1)/usr/libexec/po0-outbound-ip-report-manual-runner
	$(INSTALL_BIN) ./files/usr/libexec/po0-outbound-ip-report-migrate $(1)/usr/libexec/po0-outbound-ip-report-migrate
	$(INSTALL_BIN) ./files/usr/libexec/po0-official-firewall-request $(1)/usr/libexec/po0-official-firewall-request
	$(INSTALL_BIN) ./files/usr/libexec/po0-official-firewall-runner $(1)/usr/libexec/po0-official-firewall-runner
	$(INSTALL_BIN) ./files/etc/hotplug.d/iface/95-po0-outbound-ip-report $(1)/etc/hotplug.d/iface/95-po0-outbound-ip-report
	chmod 0700 $(1)/usr/libexec/po0-outbound-ip-report-uci $(1)/usr/libexec/po0-official-firewall-request $(1)/usr/libexec/po0-official-firewall-runner
	$(INSTALL_BIN) ./files/etc/init.d/po0-outbound-ip-report $(1)/etc/init.d/po0-outbound-ip-report
	$(INSTALL_CONF) ./files/etc/config/po0_outbound_ip_report $(1)/etc/config/po0_outbound_ip_report
	chmod 600 $(1)/etc/config/po0_outbound_ip_report
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/luci/menu.d/po0-outbound-ip-report.json $(1)/usr/share/luci/menu.d/po0-outbound-ip-report.json
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/po0-outbound-ip-report.json $(1)/usr/share/rpcd/acl.d/po0-outbound-ip-report.json
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/po0
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/po0/outbound-ip-report.js $(1)/www/luci-static/resources/view/po0/outbound-ip-report-v8.js
endef

define Package/po0-outbound-ip-report/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
	/usr/libexec/po0-outbound-ip-report-migrate || true
	/etc/init.d/po0-outbound-ip-report enable >/dev/null 2>&1 || true
	enabled="$$(uci -q get po0_outbound_ip_report.main.enabled 2>/dev/null || printf '0')"
	case "$$enabled" in
		1|true|yes|on)
			# prerm stops the old process during an upgrade. Recover it only
			# when the preserved total switch was already enabled.
			/etc/init.d/po0-outbound-ip-report restart >/dev/null 2>&1 || \
				/etc/init.d/po0-outbound-ip-report start >/dev/null 2>&1 || true
			;;
	esac
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
exit 0
endef

define Package/po0-outbound-ip-report/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
/etc/init.d/po0-outbound-ip-report stop >/dev/null 2>&1 || true
/etc/init.d/po0-outbound-ip-report disable >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,po0-outbound-ip-report))
