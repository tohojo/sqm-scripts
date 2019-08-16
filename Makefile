PREFIX:=/usr
DESTDIR:=
PLATFORM:=linux
LUCI_DIR:=$(DESTDIR)$(PREFIX)/lib/lua/luci
UNIT_DIR:=$(DESTDIR)$(PREFIX)/lib/systemd/system

all:
	@echo "Run 'make install' to install."

install: install-$(PLATFORM)


.PHONY: install-openwrt

install-openwrt: install-lib
	install -m 0755 -d $(DESTDIR)/etc/hotplug.d/iface $(DESTDIR)/etc/config \
		$(DESTDIR)/etc/init.d
	install -m 0755 platform/openwrt/sqm-hotplug $(DESTDIR)/etc/hotplug.d/iface/11-sqm
	install -m 0755 platform/openwrt/sqm-init $(DESTDIR)/etc/init.d/sqm
	install -m 0644 platform/openwrt/sqm-uci $(DESTDIR)/etc/config/sqm
	install -m 0744 src/run-openwrt.sh $(DESTDIR)$(PREFIX)/lib/sqm/run.sh

install-linux: install-lib
	install -m 0755 -d $(UNIT_DIR) $(DESTDIR)$(PREFIX)/lib/tmpfiles.d \
		$(DESTDIR)$(PREFIX)/bin
	install -m 0644  platform/linux/default.conf $(DESTDIR)/etc/sqm
	install -m 0644  platform/linux/sqm@.service $(UNIT_DIR)
	install -m 0644  platform/linux/sqm-tmpfiles.conf \
		$(DESTDIR)$(PREFIX)/lib/tmpfiles.d/sqm.conf
	install -m 0700 -d $(DESTDIR)/run/sqm
	install -m 0755 platform/linux/sqm-bin $(DESTDIR)$(PREFIX)/bin/sqm
	test -d $(DESTDIR)/etc/network/if-up.d && install -m 0755 platform/linux/sqm-ifup \
		$(DESTDIR)/etc/network/if-up.d/sqm || exit 0

.PHONY: install-lib

install-lib:
	install -m 0755 -d $(DESTDIR)/etc/sqm $(DESTDIR)$(PREFIX)/lib/sqm
	install -m 0644 platform/$(PLATFORM)/sqm.conf $(DESTDIR)/etc/sqm/sqm.conf
	install -m 0644  src/functions.sh src/defaults.sh \
		src/*.qos src/*.help $(DESTDIR)$(PREFIX)/lib/sqm
	install -m 0744  src/start-sqm src/stop-sqm src/update-available-qdiscs \
		$(DESTDIR)$(PREFIX)/lib/sqm

.PHONY: install-luci
install-luci:
	install -m 0755 -d $(LUCI_DIR)/controller $(LUCI_DIR)/model/cbi
	install -m 0644 luci/sqm-controller.lua $(LUCI_DIR)/controller/sqm.lua
	install -m 0644 luci/sqm-cbi.lua $(LUCI_DIR)/model/cbi/sqm.lua
	install -m 0755 -d $(DESTDIR)/etc/uci-defaults
	install -m 0755 luci/uci-defaults-sqm $(DESTDIR)/etc/uci-defaults/luci-sqm
