include $(TOPDIR)/rules.mk

PKG_NAME:=openwrt-wireless-helper
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

LUCI_TITLE:=OpenWrt 无线设备重复项管理助手
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/postinst
#!/bin/sh
chmod 0755 "$${IPKG_INSTROOT}/usr/libexec/wireless-helper" \
	"$${IPKG_INSTROOT}/etc/init.d/wireless_helper" \
	"$${IPKG_INSTROOT}/etc/hotplug.d/usb/99-wireless-helper" \
	"$${IPKG_INSTROOT}/etc/uci-defaults/99-wireless-helper-permissions" 2>/dev/null
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
