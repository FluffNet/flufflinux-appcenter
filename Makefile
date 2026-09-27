PREFIX ?= /usr
SYSCONFDIR ?= /etc
DESTDIR ?=
# Pacman merges shared MIME defaults from its install script, not its file list.
REGISTER_MIME ?= 1
# Include the machine's curated exclusions in archiso/fakeroot staging. Set
# EXCLUSIONS_FILE=data/exclusions.conf for a reproducible defaults-only package.
EXCLUSIONS_FILE ?= $(if $(wildcard $(SYSCONFDIR)/flufflinux-appcenter/exclusions.conf),$(SYSCONFDIR)/flufflinux-appcenter/exclusions.conf,data/exclusions.conf)

ifneq ($(shell uname -s),Linux)
$(error App Center can only be built on Fluff Linux/Arch Linux)
endif

.PHONY: build install uninstall clean set-default-handler

build: target/release/flufflinux-appcenter-source-helper
	cargo build --release

target/release/flufflinux-appcenter: Cargo.toml Cargo.lock VERSION build.rs data/exclusions.conf $(wildcard src/*.rs src/*.cpp src/*.h)
	cargo build --release

target/release/flufflinux-appcenter-source-helper: src/source_helper.cpp src/source_removal.h src/flatpak_sources.h
	mkdir -p target/release
	$(CXX) -std=c++17 -O2 -fPIC -Wall -Wextra src/source_helper.cpp -o $@ $$(pkg-config --cflags --libs Qt6Core flatpak ostree-1)

install: target/release/flufflinux-appcenter target/release/flufflinux-appcenter-source-helper
	@if [ -z "$(DESTDIR)" ] && [ "$(PREFIX)" = /usr ] && command -v pacman >/dev/null 2>&1; then \
		if pacman -Qq discover >/dev/null 2>&1 || pacman -Qq flufflinux-discover >/dev/null 2>&1 || pacman -Qq flufflinux-appcenter >/dev/null 2>&1; then \
			echo 'Use the pacman package to replace/upgrade a package-managed software center.' >&2; exit 1; \
		fi; \
	fi
	mkdir -p "$(DESTDIR)$(PREFIX)/bin" "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml"
	mkdir -p "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps" "$(DESTDIR)$(PREFIX)/share/applications"
	install -m755 target/release/flufflinux-appcenter "$(DESTDIR)$(PREFIX)/bin/flufflinux-appcenter"
	for alias in plasma-discover discover flufflinux-discover; do ln -sfn flufflinux-appcenter "$(DESTDIR)$(PREFIX)/bin/$$alias"; done
	mkdir -p "$(DESTDIR)$(PREFIX)/lib/flufflinux-appcenter" "$(DESTDIR)$(PREFIX)/share/polkit-1/actions"
	install -m755 target/release/flufflinux-appcenter-source-helper "$(DESTDIR)$(PREFIX)/lib/flufflinux-appcenter/source-helper"
	install -m755 scripts/register-flatpak-handler.sh "$(DESTDIR)$(PREFIX)/lib/flufflinux-appcenter/register-flatpak-handler"
	sed 's|@PREFIX@|$(PREFIX)|g' data/com.flufflinux.appcenter.policy.in > "$(DESTDIR)$(PREFIX)/share/polkit-1/actions/com.flufflinux.appcenter.policy"
	chmod 644 "$(DESTDIR)$(PREFIX)/share/polkit-1/actions/com.flufflinux.appcenter.policy"
	install -m644 LICENSE "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/LICENSE"
	install -m644 qml/*.qml "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml/"
	install -m644 qml/*.svg "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml/"
	install -m644 assets/flufflinux-appcenter.svg "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml/flufflinux-appcenter.svg"
	install -m644 assets/flufflinux-appcenter.svg "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/flufflinux-appcenter.svg"
	for alias in flufflinuxplasmadiscover plasmadiscover; do ln -sfn flufflinux-appcenter.svg "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/$$alias.svg"; done
	install -m644 data/flufflinux-appcenter.desktop "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/flufflinux-appcenter.desktop"
	ln -sfn ../flufflinux-appcenter/flufflinux-appcenter.desktop "$(DESTDIR)$(PREFIX)/share/applications/org.kde.discover.desktop"
	sed 's/^NoDisplay=false$$/NoDisplay=true/' data/flufflinux-appcenter.desktop > "$(DESTDIR)$(PREFIX)/share/applications/flufflinux-appcenter.desktop"
	chmod 644 "$(DESTDIR)$(PREFIX)/share/applications/flufflinux-appcenter.desktop"
	ln -sfn flufflinux-appcenter.desktop "$(DESTDIR)$(PREFIX)/share/applications/org.kde.discover.flatpak.desktop"
	mkdir -p "$(DESTDIR)$(SYSCONFDIR)/flufflinux-appcenter"
	@if [ -n "$(DESTDIR)" ] || [ ! -e "$(DESTDIR)$(SYSCONFDIR)/flufflinux-appcenter/exclusions.conf" ]; then install -m644 "$(EXCLUSIONS_FILE)" "$(DESTDIR)$(SYSCONFDIR)/flufflinux-appcenter/exclusions.conf"; fi
	@if [ "$(REGISTER_MIME)" = 1 ]; then sh scripts/register-flatpak-handler.sh "$(DESTDIR)$(SYSCONFDIR)/xdg/mimeapps.list"; fi
	@if [ -z "$(DESTDIR)" ]; then update-desktop-database "$(PREFIX)/share/applications"; gtk-update-icon-cache -f -t "$(PREFIX)/share/icons/hicolor"; fi

# Run as the desktop user after installation, not via sudo. Respect other MIME
# defaults: only these Flatpak file types and URI schemes are associated.
set-default-handler:
	xdg-mime default flufflinux-appcenter.desktop application/vnd.flatpak application/vnd.flatpak.ref application/vnd.flatpak.repo x-scheme-handler/flatpak x-scheme-handler/flatpak+https

uninstall:
	sh scripts/register-flatpak-handler.sh "$(DESTDIR)$(SYSCONFDIR)/xdg/mimeapps.list" remove
	rm -f "$(DESTDIR)$(PREFIX)/bin/flufflinux-appcenter"
	for alias in plasma-discover discover flufflinux-discover; do rm -f "$(DESTDIR)$(PREFIX)/bin/$$alias"; done
	rm -f "$(DESTDIR)$(PREFIX)/lib/flufflinux-appcenter/source-helper"
	rm -f "$(DESTDIR)$(PREFIX)/lib/flufflinux-appcenter/register-flatpak-handler"
	rm -f "$(DESTDIR)$(PREFIX)/share/polkit-1/actions/com.flufflinux.appcenter.policy"
	rm -rf "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter"
	rm -f "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/flufflinux-appcenter.svg"
	rm -f "$(DESTDIR)$(PREFIX)/share/applications/flufflinux-appcenter.desktop"
	rm -f "$(DESTDIR)$(PREFIX)/share/applications/org.kde.discover.desktop" "$(DESTDIR)$(PREFIX)/share/applications/org.kde.discover.flatpak.desktop"
	for alias in flufflinuxplasmadiscover plasmadiscover; do rm -f "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/$$alias.svg"; done

clean:
	cargo clean
