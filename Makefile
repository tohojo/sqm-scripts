PREFIX:=/usr
DESTDIR:=
PLATFORM:=linux
PKG_CONFIG:=$(shell which pkg-config 2>/dev/null)
UNIT_DIR:=$(if $(PKG_CONFIG),\
	$(DESTDIR)$(shell $(PKG_CONFIG) --variable systemdsystemunitdir systemd),\
	$(DESTDIR)$(PREFIX)/lib/systemd/system)

all:
	@echo "Run 'make install' to install."

.PHONY: install
install: install-$(PLATFORM)

.PHONY: install-openwrt
install-openwrt: install-lib
	install -m 0755 -d $(DESTDIR)/etc/hotplug.d/iface $(DESTDIR)/etc/config \
		$(DESTDIR)/etc/init.d
	install -m 0600 platform/openwrt/sqm-hotplug $(DESTDIR)/etc/hotplug.d/iface/11-sqm
	install -m 0755 platform/openwrt/sqm-init $(DESTDIR)/etc/init.d/sqm
	install -m 0644 platform/openwrt/sqm-uci $(DESTDIR)/etc/config/sqm
	install -m 0744 src/run-openwrt.sh $(DESTDIR)$(PREFIX)/lib/sqm/run.sh

.PHONY: install-linux
install-linux: install-lib
	install -m 0755 -d $(UNIT_DIR) $(DESTDIR)$(PREFIX)/lib/tmpfiles.d \
		$(DESTDIR)$(PREFIX)/bin
	install -m 0644 -C -b platform/linux/default.conf $(DESTDIR)/etc/sqm
	install -m 0644  platform/linux/sqm@.service $(UNIT_DIR)
	install -m 0644  platform/linux/sqm-tmpfiles.conf \
		$(DESTDIR)$(PREFIX)/lib/tmpfiles.d/sqm.conf
	install -m 0755 platform/linux/sqm-bin $(DESTDIR)$(PREFIX)/bin/sqm
	test -d $(DESTDIR)/etc/network/if-up.d && install -m 0755 platform/linux/sqm-ifup \
		$(DESTDIR)/etc/network/if-up.d/sqm || exit 0

.PHONY: install-lib
install-lib:
	install -m 0755 -d $(DESTDIR)/etc/sqm $(DESTDIR)$(PREFIX)/lib/sqm
	install -m 0644 -C -b platform/$(PLATFORM)/sqm.conf $(DESTDIR)/etc/sqm/sqm.conf
	install -m 0644  src/functions.sh src/defaults.sh \
		src/*.qos src/*.help $(DESTDIR)$(PREFIX)/lib/sqm
	install -m 0744  src/start-sqm src/stop-sqm src/update-available-qdiscs \
		$(DESTDIR)$(PREFIX)/lib/sqm

.PHONY: uninstall
uninstall: uninstall-$(PLATFORM)

.PHONY: uninstall-openwrt
uninstall-openwrt: uninstall-lib
	@for f in $(DESTDIR)/etc/hotplug.d/iface/11-sqm $(DESTDIR)/etc/init.d/sqm; do \
		if [ -f "$$f" ]; then rm -vf "$$f"; fi; done
	@echo "Not removing config in $(DESTDIR)/etc/sqm and  $(DESTDIR)/etc/config/sqm - remove manually if needed"

.PHONY: uninstall-linux
uninstall-linux: uninstall-lib
	@for f in $(UNIT_DIR)/sqm@.service $(DESTDIR)$(PREFIX)/lib/tmpfiles.d/sqm.conf \
		$(DESTDIR)$(PREFIX)/bin/sqm $(DESTDIR)/etc/network/if-up.d/sqm; do \
		if [ -f "$$f" ]; then rm -vf "$$f"; fi; done
	@echo "Not removing config in $(DESTDIR)/etc/sqm - remove manually if needed"

.PHONY: uninstall-lib
uninstall-lib:
	@for f in $(DESTDIR)$(PREFIX)/lib/sqm/*; do \
		if [ -f "$$f" ]; then rm -vf "$$f"; fi; done
	@rmdir -v $(DESTDIR)$(PREFIX)/lib/sqm
