PREFIX ?= /usr
SYSCONFDIR ?= /etc
DESTDIR ?=

ifneq ($(shell uname -s),Linux)
$(error App Center can only be built on Fluff Linux/Arch Linux)
endif

.PHONY: build install uninstall clean set-default-handler

build:
	cargo build --release

target/release/flufflinux-appcenter: Cargo.toml build.rs $(wildcard src/*.rs src/*.cpp src/*.h)
	cargo build --release

install: target/release/flufflinux-appcenter
	mkdir -p "$(DESTDIR)$(PREFIX)/bin" "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml"
	mkdir -p "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps" "$(DESTDIR)$(PREFIX)/share/applications"
	install -m755 target/release/flufflinux-appcenter "$(DESTDIR)$(PREFIX)/bin/flufflinux-appcenter"
	install -m644 qml/*.qml "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml/"
	install -m644 qml/trash-red.svg "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml/"
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
	rm -rf "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter"
	rm -f "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/flufflinux-appcenter.svg"
	rm -f "$(DESTDIR)$(PREFIX)/share/applications/flufflinux-appcenter.desktop"

clean:
	cargo clean
