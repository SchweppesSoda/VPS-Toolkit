include $(TOPDIR)/rules.mk

PKG_NAME:=po0-wan-probe
PKG_VERSION:=2026.08.30
PKG_RELEASE:=5
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/po0-wan-probe
  SECTION:=net
  CATEGORY:=Network
  TITLE:=PO0 multi-WAN public IPv4 probe
  DEPENDS:=+curl +jsonfilter +mwan3 +uhttpd +luci-base
endef

define Package/po0-wan-probe/description
 Read-only LAN CGI endpoint exposing public IPv4 addresses for enabled mwan3 WANs.
endef

define Package/po0-wan-probe/conffiles
/etc/config/po0_wan_probe
endef

define Build/Compile
endef

define Package/po0-wan-probe/install
	$(INSTALL_DIR) $(1)/www/cgi-bin $(1)/usr/libexec $(1)/etc/config
	$(INSTALL_BIN) $(TOPDIR)/po0-assets/po0-wan-probe.sh $(1)/www/cgi-bin/po0-wan-probe
	$(INSTALL_BIN) ./files/usr/libexec/po0-wan-probe-control $(1)/usr/libexec/po0-wan-probe-control
	$(INSTALL_CONF) ./files/etc/config/po0_wan_probe $(1)/etc/config/po0_wan_probe
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/luci/menu.d/po0-wan-probe.json $(1)/usr/share/luci/menu.d/po0-wan-probe.json
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/po0-wan-probe.json $(1)/usr/share/rpcd/acl.d/po0-wan-probe.json
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/po0
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/po0/wan-probe.js $(1)/www/luci-static/resources/view/po0/wan-probe.js
endef

define Package/po0-wan-probe/preinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
if [ -x /www/cgi-bin/po0-wan-probe ] && [ ! -e /usr/lib/po0/.wan-probe-packaged ]; then
	mkdir -p /usr/lib/po0/legacy
	cp -p /www/cgi-bin/po0-wan-probe /usr/lib/po0/legacy/po0-wan-probe.pre-apk 2>/dev/null || true
fi
exit 0
endef

define Package/po0-wan-probe/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
mkdir -p /usr/lib/po0
touch /usr/lib/po0/.wan-probe-packaged
/etc/init.d/uhttpd reload >/dev/null 2>&1 || true
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
exit 0
endef

$(eval $(call BuildPackage,po0-wan-probe))
