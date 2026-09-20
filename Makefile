include $(TOPDIR)/rules.mk

PKG_NAME:=openwrt-wireless-helper
PKG_VERSION:=1.2.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=matthewlu070111

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=OpenWrt 无线设备与 DNS 自愈助手
  DEPENDS:=+luci-base +jsonfilter
  PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
  检测并恢复 USB Wi-Fi radio 异常，同步接管 dnsmasq 到 Clash/Mihomo DNS。
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/wireless_helper.lua $(1)/usr/lib/lua/luci/controller/wireless_helper.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./luasrc/model/cbi/wireless_helper.lua $(1)/usr/lib/lua/luci/model/cbi/wireless_helper.lua

	$(CP) ./root/* $(1)/
	$(INSTALL_BIN) ./root/usr/libexec/wireless-helper $(1)/usr/libexec/wireless-helper
	$(INSTALL_BIN) ./root/etc/init.d/wireless_helper $(1)/etc/init.d/wireless_helper
	$(INSTALL_BIN) ./root/etc/hotplug.d/usb/99-wireless-helper $(1)/etc/hotplug.d/usb/99-wireless-helper
	$(INSTALL_BIN) ./root/etc/uci-defaults/99-wireless-helper-permissions $(1)/etc/uci-defaults/99-wireless-helper-permissions
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
chmod 0755 "$${IPKG_INSTROOT}/usr/libexec/wireless-helper" \
	"$${IPKG_INSTROOT}/etc/init.d/wireless_helper" \
	"$${IPKG_INSTROOT}/etc/hotplug.d/usb/99-wireless-helper" \
	"$${IPKG_INSTROOT}/etc/uci-defaults/99-wireless-helper-permissions" 2>/dev/null
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
