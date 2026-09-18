PREFIX ?= $(HOME)/.local
LIBDIR ?= $(PREFIX)/lib/chatgpt-arch-updater
UNITDIR ?= $(HOME)/.config/systemd/user
UPDATER_PKGBUILD_DIR ?= $(if $(XDG_CACHE_HOME),$(XDG_CACHE_HOME),$(HOME)/.cache)/chatgpt-arch-updater/updater-package

.PHONY: install-user uninstall-user updater-package install-updater activate-user check

updater-package:
	install -d "$(UPDATER_PKGBUILD_DIR)/build" "$(UPDATER_PKGBUILD_DIR)/dist" "$(UPDATER_PKGBUILD_DIR)/sources"
	cd packaging/updater && BUILDDIR="$(UPDATER_PKGBUILD_DIR)/build" PKGDEST="$(UPDATER_PKGBUILD_DIR)/dist" SRCDEST="$(UPDATER_PKGBUILD_DIR)/sources" makepkg --nodeps --force --noconfirm
	@printf 'Updater package built in %s/dist\n' "$(UPDATER_PKGBUILD_DIR)"

install-updater: updater-package
	@set -e; package=$$(find "$(UPDATER_PKGBUILD_DIR)/dist" -maxdepth 1 -type f -name 'chatgpt-arch-updater-*.pkg.tar.*' -print | sort -V | tail -n1); test -n "$$package"; sudo pacman -U "$$package"
	$(MAKE) activate-user

activate-user:
	systemctl --user daemon-reload
	systemctl --user enable --now chatgpt-arch-updater.timer
	systemctl --user start chatgpt-arch-updater.service

install-user:
	install -d "$(PREFIX)/bin" "$(LIBDIR)" "$(UNITDIR)"
	install -m 755 bin/chatgpt-arch-updater "$(PREFIX)/bin/chatgpt-arch-updater"
	install -m 644 lib/chatgpt_arch_updater/*.sh "$(LIBDIR)/"
	install -m 644 systemd/user/*.service systemd/user/*.timer "$(UNITDIR)/"
	$(MAKE) activate-user

uninstall-user:
	rm -f "$(PREFIX)/bin/chatgpt-arch-updater" "$(UNITDIR)/chatgpt-arch-updater.service" "$(UNITDIR)/chatgpt-arch-updater.timer"
	rm -rf "$(LIBDIR)"

check:
	bash -n bin/chatgpt-arch-updater lib/chatgpt_arch_updater/*.sh
	bash ./tests/shell/run.sh
