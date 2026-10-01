include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for LiteWall (Xray-Rust proxy client)
LUCI_DEPENDS:=+luci-base +lua +luci-lib-jsonc +nftables +curl
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-litewall
PKG_VERSION:=26.10.01
PKG_RELEASE:=1
PKG_MAINTAINER:=Dan

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
