PREFIX:=/usr
DESTDIR:=
PLATFORM:=linux
sbindir:=$(DESTDIR)$(PREFIX)/sbin
sysconfdir:=$(DESTDIR)/etc
libdir:=$(DESTDIR)$(PREFIX)/lib
LUCI_DIR:=$(libdir)/lua/luci

all:
	@echo "Run 'make install' to install."

install: install-$(PLATFORM)


.PHONY: install-openwrt

install-openwrt: install-lib
	install -m 0755 -d $(sysconfdir)/hotplug.d/iface $(sysconfdir)/config \
		$(sysconfdir)/init.d
	install -m 0755 platform/openwrt/sqm-hotplug $(sysconfdir)/hotplug.d/iface/11-sqm
	install -m 0755 platform/openwrt/sqm-init $(sysconfdir)/init.d/sqm
	install -m 0644 platform/openwrt/sqm-uci $(sysconfdir)/config/sqm
	install -m 0744 src/run-openwrt.sh $(libdir)/sqm/run.sh

install-linux: install-lib
	install -m 0755 -d $(sbindir)
	install -m 0644 platform/linux/eth0.iface.conf.example $(sysconfdir)/sqm
	install -m 0755 platform/linux/sqm-bin $(sbindir)/sqm
	test -d $(libdir)/systemd/system && install -m 0644 platform/linux/sqm@.service \
                $(libdir)/systemd/system || exit 0
	test -d $(sysconfdir)/network/if-up.d && install -m 0755 platform/linux/sqm-ifup \
		$(sysconfdir)/network/if-up.d/sqm || exit 0

.PHONY: install-lib

install-lib:
	install -m 0755 -d $(sysconfdir)/sqm $(libdir)/sqm
	install -m 0644 platform/$(PLATFORM)/sqm.conf $(sysconfdir)/sqm/sqm.conf
	install -m 0644  src/functions.sh src/defaults.sh \
		src/*.qos src/*.help $(libdir)/sqm
	install -m 0744  src/start-sqm src/stop-sqm src/update-available-qdiscs \
		$(libdir)/sqm

.PHONY: install-luci
install-luci:
	install -m 0755 -d $(LUCI_DIR)/controller $(LUCI_DIR)/model/cbi
	install -m 0644 luci/sqm-controller.lua $(LUCI_DIR)/controller/sqm.lua
	install -m 0644 luci/sqm-cbi.lua $(LUCI_DIR)/model/cbi/sqm.lua
	install -m 0755 -d $(sysconfdir)/uci-defaults
	install -m 0755 luci/uci-defaults-sqm $(sysconfdir)/uci-defaults/luci-sqm
