PREFIX ?= /usr
SYSCONFDIR ?= /etc
DESTDIR ?=

ifneq ($(shell uname -s),Linux)
$(error App Center can only be built on Fluff Linux/Arch Linux)
endif

.PHONY: build install uninstall clean set-default-handler

build: target/release/flufflinux-appcenter-source-helper
	cargo build --release

target/release/flufflinux-appcenter: Cargo.toml Cargo.lock VERSION build.rs $(wildcard src/*.rs src/*.cpp src/*.h)
	cargo build --release

target/release/flufflinux-appcenter-source-helper: src/source_helper.cpp src/source_removal.h src/flatpak_sources.h
	mkdir -p target/release
	$(CXX) -std=c++17 -O2 -fPIC -Wall -Wextra src/source_helper.cpp -o $@ $$(pkg-config --cflags --libs Qt6Core flatpak ostree-1)

install: target/release/flufflinux-appcenter target/release/flufflinux-appcenter-source-helper
	mkdir -p "$(DESTDIR)$(PREFIX)/bin" "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml"
	mkdir -p "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps" "$(DESTDIR)$(PREFIX)/share/applications"
	install -m755 target/release/flufflinux-appcenter "$(DESTDIR)$(PREFIX)/bin/flufflinux-appcenter"
	mkdir -p "$(DESTDIR)$(PREFIX)/lib/flufflinux-appcenter" "$(DESTDIR)$(PREFIX)/share/polkit-1/actions"
	install -m755 target/release/flufflinux-appcenter-source-helper "$(DESTDIR)$(PREFIX)/lib/flufflinux-appcenter/source-helper"
	sed 's|@PREFIX@|$(PREFIX)|g' data/com.flufflinux.appcenter.policy.in > "$(DESTDIR)$(PREFIX)/share/polkit-1/actions/com.flufflinux.appcenter.policy"
	chmod 644 "$(DESTDIR)$(PREFIX)/share/polkit-1/actions/com.flufflinux.appcenter.policy"
	install -m644 LICENSE "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/LICENSE"
	install -m644 qml/*.qml "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml/"
	install -m644 qml/*.svg "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml/"
	install -m644 assets/flufflinux-appcenter.svg "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml/flufflinux-appcenter.svg"
	install -m644 assets/flufflinux-appcenter.svg "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/flufflinux-appcenter.svg"
	install -m644 data/flufflinux-appcenter.desktop "$(DESTDIR)$(PREFIX)/share/applications/flufflinux-appcenter.desktop"
	sh scripts/register-flatpak-handler.sh "$(DESTDIR)$(SYSCONFDIR)/xdg/mimeapps.list"
	@if [ -z "$(DESTDIR)" ]; then update-desktop-database "$(PREFIX)/share/applications"; gtk-update-icon-cache -f -t "$(PREFIX)/share/icons/hicolor"; fi

# Run as the desktop user after installation, not via sudo. Respect other MIME
# defaults: only these Flatpak file types and URI schemes are associated.
set-default-handler:
	xdg-mime default flufflinux-appcenter.desktop application/vnd.flatpak application/vnd.flatpak.ref application/vnd.flatpak.repo x-scheme-handler/flatpak x-scheme-handler/flatpak+https

uninstall:
	sh scripts/register-flatpak-handler.sh "$(DESTDIR)$(SYSCONFDIR)/xdg/mimeapps.list" remove
	rm -f "$(DESTDIR)$(PREFIX)/bin/flufflinux-appcenter"
	rm -f "$(DESTDIR)$(PREFIX)/lib/flufflinux-appcenter/source-helper"
	rm -f "$(DESTDIR)$(PREFIX)/share/polkit-1/actions/com.flufflinux.appcenter.policy"
	rm -rf "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter"
	rm -f "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/flufflinux-appcenter.svg"
	rm -f "$(DESTDIR)$(PREFIX)/share/applications/flufflinux-appcenter.desktop"

clean:
	cargo clean
