PREFIX:=/usr
PLATFORM:=linux
sysconfdir:=$(DESTDIR)/etc
libdir:=$(DESTDIR)$(PREFIX)/lib
sbindir:=$(DESTDIR)$(PREFIX)/bin
LUCI_DIR:=$(libdir)/lua/luci

all:
	@echo "Run 'make install' to install."

install: install-$(PLATFORM)

.PHONY: install-openwrt
install-openwrt: install-lib
	install -d $(sysconfdir)/hotplug.d/iface $(sysconfdir)/init.d \
		$(sysconfdir)/config $(libdir)/sqm
	install -m 0755 platform/$(PLATFORM)/sqm-hotplug $(sysconfdir)/hotplug.d/iface/11-sqm
	install -m 0755 platform/$(PLATFORM)/sqm-init $(sysconfdir)/init.d/sqm
	install -m 0644 platform/$(PLATFORM)/sqm-uci $(sysconfdir)/config/sqm
	install -m 0744 src/run-openwrt.sh $(libdir)/sqm/run.sh

install-linux: install-lib
	install -d $(libdir)/systemd/system
	install -D -m 0644 platform/$(PLATFORM)/eth0.iface.conf.example $(sysconfdir)/sqm
	install -m 0644 platform/$(PLATFORM)/sqm@.service $(libdir)/systemd/system
	install -D -m 0644 platform/$(PLATFORM)/sqm-tmpfiles.conf $(libdir)/tmpfiles.d/sqm.conf
	install -D -m 0755 platform/$(PLATFORM)/sqm-bin $(sbindir)/sqm
	test -d $(sysconfdir)/network/if-up.d && install -D -m 0755 platform/$(PLATFORM)/sqm-ifup \
		$(sysconfdir)/network/if-up.d/sqm || exit 0

.PHONY: install-lib
install-lib:
	install -d $(libdir)/sqm
	install -D -m 0644 platform/$(PLATFORM)/sqm.conf $(sysconfdir)/sqm/sqm.conf
	install -m 0644 src/functions.sh src/defaults.sh \
		src/*.qos src/*.help $(libdir)/sqm
	install -m 0744 src/start-sqm src/stop-sqm src/update-available-qdiscs \
		$(libdir)/sqm

.PHONY: install-luci
install-luci:
	install -D -m 0644 luci/sqm-controller.lua $(LUCI_DIR)/controller/sqm.lua
	install -D -m 0644 luci/sqm-cbi.lua $(LUCI_DIR)/model/cbi/sqm.lua
	install -D -m 0755 luci/uci-defaults-sqm $(sysconfdir)/uci-defaults/luci-sqm

