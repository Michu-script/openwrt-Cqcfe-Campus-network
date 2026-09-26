include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-campus-portal
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=Campus Portal Maintainer
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-campus-portal
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Campus portal auto login
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-compat +curl +coreutils-base64 +libubox
endef

define Package/luci-app-campus-portal/description
 LuCI page + daemon for campus portal keep-alive and auto login.
 The daemon checks cn.bing.com every 5 seconds. If failed, it checks
 portal online state and triggers portal login when offline.
endef

define Build/Compile
endef

define Package/luci-app-campus-portal/conffiles
/etc/config/campus_portal
endef

define Package/luci-app-campus-portal/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/campus_portal $(1)/etc/config/campus_portal

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/campus_portal $(1)/etc/init.d/campus_portal

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./root/usr/sbin/campus_portal_daemon.sh $(1)/usr/sbin/campus_portal_daemon.sh
	$(INSTALL_BIN) ./root/usr/sbin/campus_portal_detect.sh $(1)/usr/sbin/campus_portal_detect.sh

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/controller/campus_portal.lua $(1)/usr/lib/lua/luci/controller/campus_portal.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/model/cbi/campus_portal.lua $(1)/usr/lib/lua/luci/model/cbi/campus_portal.lua
endef

$(eval $(call BuildPackage,luci-app-campus-portal))
