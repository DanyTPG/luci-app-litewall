include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for Xray-Rust client
LUCI_DEPENDS:=+luci-base +lua +luci-lib-jsonc
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-xray-rust
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Dan

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
