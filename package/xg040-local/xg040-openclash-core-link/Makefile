include $(TOPDIR)/rules.mk

PKG_NAME:=xg040-openclash-core-link
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=net
  CATEGORY:=Network
  TITLE:=XG-040G-MD local OpenClash Meta core link
  DEPENDS:=+mihomo-meta +luci-app-openclash
endef

define Package/$(PKG_NAME)/description
 Pre-configures the locally cross-compiled Mihomo Meta binary as OpenClash's
 Meta core.  It installs no service and has no Docker dependency.
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/99-xg040-openclash-core-link $(1)/etc/uci-defaults/99-xg040-openclash-core-link
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
