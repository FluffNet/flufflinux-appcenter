PREFIX ?= /usr
DESTDIR ?=

ifneq ($(shell uname -s),Linux)
$(error App Center can only be built on Fluff Linux/Arch Linux)
endif

.PHONY: build install uninstall clean

build:
	cargo build --release

install: build
	mkdir -p "$(DESTDIR)$(PREFIX)/bin" "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml"
	mkdir -p "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps" "$(DESTDIR)$(PREFIX)/share/applications"
	install -m755 target/release/flufflinux-appcenter "$(DESTDIR)$(PREFIX)/bin/flufflinux-appcenter"
	install -m644 qml/*.qml "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml/"
	install -m644 qml/trash-red.svg "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml/"
	install -m644 assets/flufflinux-appcenter.svg "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter/qml/flufflinux-appcenter.svg"
	install -m644 assets/flufflinux-appcenter.svg "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/flufflinux-appcenter.svg"
	install -m644 data/flufflinux-appcenter.desktop "$(DESTDIR)$(PREFIX)/share/applications/flufflinux-appcenter.desktop"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/flufflinux-appcenter"
	rm -rf "$(DESTDIR)$(PREFIX)/share/flufflinux-appcenter"
	rm -f "$(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/flufflinux-appcenter.svg"
	rm -f "$(DESTDIR)$(PREFIX)/share/applications/flufflinux-appcenter.desktop"

clean:
	cargo clean
