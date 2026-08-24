# KWin Patch Manager
# Usage: make [build|install|revert|status|clean|help]

BUILD_DIR   := build
BUILD_BIN   := $(BUILD_DIR)/bin/kwin_wayland
BUILD_LIB   := $(BUILD_DIR)/bin/libkwin.so
SYSTEM_KWIN := /usr/bin/kwin_wayland
BACKUP_KWIN := /usr/bin/kwin_wayland.orig
BACKUP_LIB  := /usr/lib/libkwin.so.orig

.PHONY: build install revert status clean upgrade force-upgrade help

help:
	@echo "KWin Patch Manager"
	@echo ""
	@echo "  make build    - Build patched KWin (no RUNPATH)"
	@echo "  make install  - Install patched KWin (backups original first)"
	@echo "  make revert   - Restore original system KWin"
	@echo "  make status   - Show current status"
	@echo "  make upgrade       - Rebase patch onto new kwin version (usage: make upgrade [VER=6.7.4] [FORCE=1])"
	@echo "                       Detects rebuilt binaries via sha256 even if version string is unchanged."
	@echo "  make force-upgrade - Force upgrade even if kwin appears unchanged (same as FORCE=1)"
	@echo "  make clean    - Remove build directory"

build:
	cmake -B $(BUILD_DIR) -S . -DCMAKE_BUILD_TYPE=Release -DCMAKE_SKIP_RPATH=ON -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON
	cmake --build $(BUILD_DIR) --target kwin_wayland
	strip --strip-unneeded $(BUILD_BIN)
	strip --strip-unneeded $(BUILD_LIB).6.*
	@echo ""
	@RUNPATH=$$(readelf -d $(BUILD_BIN) 2>/dev/null | grep RUNPATH || true); \
	if [ -n "$$RUNPATH" ]; then \
		echo "WARNING: Binary has RUNPATH: $$RUNPATH"; \
		echo "Run: make clean && make build"; \
	else \
		echo "Build complete (no RUNPATH, stripped)."; \
	fi

install:
	@set -e; \
	if [ ! -f $(BUILD_BIN) ]; then \
		echo "Error: Build not found. Run 'make build' first."; \
		exit 1; \
	fi; \
	if [ ! -f $(BUILD_LIB) ]; then \
		echo "Error: Build library not found. Run 'make build' first."; \
		exit 1; \
	fi; \
	SONAME=$$(readelf -d $(BUILD_LIB) | grep SONAME | sed 's/.*\[\(.*\)\].*/\1/'); \
	BUILD_LIB_REAL=$$(readlink -f $(BUILD_LIB)); \
	BUILD_LIB_NAME=$$(basename "$$BUILD_LIB_REAL"); \
	if [ -z "$$SONAME" ]; then \
		echo "Error: Could not detect SONAME from build library."; \
		exit 1; \
	fi; \
	if [ -z "$$BUILD_LIB_REAL" ]; then \
		echo "Error: Could not resolve build library path."; \
		exit 1; \
	fi; \
	SYSTEM_LIB_REAL=$$(readlink -f /usr/lib/libkwin.so 2>/dev/null || true); \
	if [ -z "$$SYSTEM_LIB_REAL" ]; then \
		echo "WARNING: System library symlinks broken. Falling back to build filename."; \
		SYSTEM_LIB_REAL="/usr/lib/$$BUILD_LIB_NAME"; \
		SYSTEM_LIB_NAME="$$BUILD_LIB_NAME"; \
	else \
		SYSTEM_LIB_NAME=$$(basename "$$SYSTEM_LIB_REAL"); \
	fi; \
	echo "  SONAME:     $$SONAME"; \
	echo "  Build lib:  $$BUILD_LIB_NAME"; \
	echo "  System lib: $$SYSTEM_LIB_NAME"; \
	echo ""; \
	if [ "$$SYSTEM_LIB_NAME" != "$$BUILD_LIB_NAME" ]; then \
		echo "WARNING: Version mismatch!"; \
		echo "  System: $$SYSTEM_LIB_NAME"; \
		echo "  Build:  $$BUILD_LIB_NAME"; \
		echo "Rebase to the correct version and rebuild to avoid ABI issues."; \
		read -p "Continue anyway? [y/N] " -r < /dev/tty; \
		if [ "$$REPLY" != "y" ] && [ "$$REPLY" != "Y" ]; then exit 1; fi; \
		echo ""; \
	fi; \
	if [ ! -f $(BACKUP_KWIN) ]; then \
		if [ ! -f "$$SYSTEM_LIB_REAL" ] && [ ! -L "$$SYSTEM_LIB_REAL" ]; then \
			echo "Error: System library not found at $$SYSTEM_LIB_REAL. Cannot create backup."; \
			exit 1; \
		fi; \
		echo "Creating backup of original system KWin..."; \
		sudo cp $(SYSTEM_KWIN) $(BACKUP_KWIN); \
		sudo cp "$$SYSTEM_LIB_REAL" $(BACKUP_LIB); \
		echo "Backed up to $(BACKUP_KWIN) and $(BACKUP_LIB)"; \
		echo ""; \
	fi; \
	echo "Installing patched KWin..."; \
	sudo mv $(SYSTEM_KWIN) $(SYSTEM_KWIN).tmp 2>/dev/null || true; \
	sudo cp $(BUILD_BIN) $(SYSTEM_KWIN); \
	sudo rm -f $(SYSTEM_KWIN).tmp; \
	sudo cp "$$BUILD_LIB_REAL" "$$SYSTEM_LIB_REAL"; \
	if [ "$$SYSTEM_LIB_NAME" != "$$SONAME" ]; then \
		sudo ln -sf "$$SYSTEM_LIB_NAME" "/usr/lib/$$SONAME"; \
	fi; \
	sudo ln -sf "$$SONAME" "/usr/lib/libkwin.so"; \
	sudo ldconfig; \
	echo "Patched KWin installed."; \
	echo ""; \
	read -p "Restart KWin now? [y/N] " -r < /dev/tty; \
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
		kwin_wayland --replace & \
	fi

revert:
	@set -e; \
	if [ ! -f $(BACKUP_KWIN) ] || [ ! -f $(BACKUP_LIB) ]; then \
		echo "Error: No backup found. Cannot revert."; \
		exit 1; \
	fi; \
	BACKUP_SONAME=$$(readelf -d $(BACKUP_LIB) | grep SONAME | sed 's/.*\[\(.*\)\].*/\1/'); \
	if [ -z "$$BACKUP_SONAME" ]; then \
		echo "Error: Could not detect SONAME from backup library."; \
		exit 1; \
	fi; \
	SYSTEM_LIB_REAL=$$(readlink -f /usr/lib/libkwin.so 2>/dev/null || true); \
	if [ -z "$$SYSTEM_LIB_REAL" ]; then \
		echo "WARNING: System library symlinks broken. Falling back to SONAME filename."; \
		SYSTEM_LIB_REAL="/usr/lib/$$BACKUP_SONAME"; \
		SYSTEM_LIB_NAME="$$BACKUP_SONAME"; \
	else \
		SYSTEM_LIB_NAME=$$(basename "$$SYSTEM_LIB_REAL"); \
	fi; \
	echo "Restoring original system KWin..."; \
	sudo mv $(SYSTEM_KWIN) $(SYSTEM_KWIN).tmp 2>/dev/null || true; \
	sudo cp $(BACKUP_KWIN) $(SYSTEM_KWIN); \
	sudo rm -f $(SYSTEM_KWIN).tmp; \
	sudo cp $(BACKUP_LIB) "$$SYSTEM_LIB_REAL"; \
	if [ "$$SYSTEM_LIB_NAME" != "$$BACKUP_SONAME" ]; then \
		sudo ln -sf "$$SYSTEM_LIB_NAME" "/usr/lib/$$BACKUP_SONAME"; \
	fi; \
	sudo ln -sf "$$BACKUP_SONAME" "/usr/lib/libkwin.so"; \
	sudo ldconfig; \
	echo "Original system KWin restored."; \
	echo ""; \
	read -p "Restart KWin now? [y/N] " -r < /dev/tty; \
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
		kwin_wayland --replace & \
	fi

status:
	@echo "=== KWin Patch Status ==="
	@echo ""
	@echo "Build:"
	@if [ -f $(BUILD_BIN) ]; then \
		BUILD_VER=$$(LD_LIBRARY_PATH=$(BUILD_DIR)/bin $(BUILD_BIN) --version 2>/dev/null || echo "unknown"); \
		BUILD_LIB=$$(basename "$$(readlink -f $(BUILD_DIR)/bin/libkwin.so 2>/dev/null)" 2>/dev/null); \
		RUNPATH=$$(readelf -d $(BUILD_BIN) 2>/dev/null | grep RUNPATH || echo "none"); \
		echo "  Version:  $$BUILD_VER"; \
		echo "  Library:  $$BUILD_LIB"; \
		echo "  RUNPATH:  $$RUNPATH"; \
		if echo "$$RUNPATH" | grep -qv "none"; then \
			echo "  WARNING: RUNPATH set! Run: make clean && make build"; \
		fi; \
	else \
		echo "  Not built. Run 'make build'."; \
	fi
	@echo ""
	@echo "System:"
	@SYSTEM_VER=$$($(SYSTEM_KWIN) --version 2>/dev/null || echo "unknown"); \
	SYSTEM_LIB=$$(basename "$$(readlink -f /usr/lib/libkwin.so 2>/dev/null)" 2>/dev/null); \
	echo "  Version:  $$SYSTEM_VER"; \
	echo "  Library:  $$SYSTEM_LIB"
	@echo ""
	@echo "Backup:"
	@if [ -f $(BACKUP_KWIN) ]; then \
		BACKUP_VER=$$($(BACKUP_KWIN) --version 2>/dev/null || echo "unknown"); \
		echo "  Version:  $$BACKUP_VER"; \
	else \
		echo "  No backup. Run 'make install' to create one."; \
	fi
	@echo ""
	@BUILD_HASH=$$(md5sum $(BUILD_BIN) 2>/dev/null | cut -d' ' -f1); \
	SYSTEM_HASH=$$(md5sum $(SYSTEM_KWIN) 2>/dev/null | cut -d' ' -f1); \
	BACKUP_HASH=$$(md5sum $(BACKUP_KWIN) 2>/dev/null | cut -d' ' -f1); \
	if [ "$$BUILD_HASH" = "$$SYSTEM_HASH" ] && [ -n "$$BUILD_HASH" ]; then \
		echo "Current: Patched (development version)"; \
	elif [ "$$BACKUP_HASH" = "$$SYSTEM_HASH" ] && [ -n "$$BACKUP_HASH" ]; then \
		echo "Current: System (original version)"; \
	else \
		echo "Current: Unknown (neither build nor backup matches system)"; \
	fi

upgrade:
	@set -e; \
	TARGET_VER="$(VER)"; \
	if [ -z "$$TARGET_VER" ]; then \
		TARGET_VER=$$($(SYSTEM_KWIN) --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
	fi; \
	if [ -z "$$TARGET_VER" ]; then \
		echo "Error: could not detect installed kwin version. Run: make upgrade VER=6.7.3"; \
		exit 1; \
	fi; \
	TARGET_TAG="v$$TARGET_VER"; \
	CURRENT_BASE=$$(git tag --sort=-v:refname --merged HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$' | head -1); \
	if [ -z "$$CURRENT_BASE" ]; then \
		echo "Error: could not detect current patch base tag."; \
		exit 1; \
	fi; \
	echo "  Current base: $$CURRENT_BASE"; \
	echo "  Target:       $$TARGET_TAG"; \
	echo ""; \
	echo "Fetching upstream tags..."; \
	git fetch upstream --tags --quiet; \
	if ! git rev-parse -q --verify "refs/tags/$$TARGET_TAG" >/dev/null 2>&1; then \
		echo "Error: tag $$TARGET_TAG not found after fetch."; \
		exit 1; \
	fi; \
	INSTALLED=$$($(SYSTEM_KWIN) --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
	if [ "$$INSTALLED" != "$$TARGET_VER" ]; then \
		echo "WARNING: target $$TARGET_VER != installed kwin $$INSTALLED"; \
		echo "  Building against a non-matching tag risks ABI mismatch (the original bug)."; \
		read -p "Continue anyway? [y/N] " -r < /dev/tty; \
		if [ "$$REPLY" != "y" ] && [ "$$REPLY" != "Y" ]; then exit 1; fi; \
		echo ""; \
	fi; \
	SYS_BIN_HASH=$$(sha256sum $(SYSTEM_KWIN) 2>/dev/null | cut -d' ' -f1); \
	BACKUP_BIN_HASH=$$(sha256sum $(BACKUP_KWIN) 2>/dev/null | cut -d' ' -f1); \
	SYS_LIB_REAL_UPGRADE=$$(readlink -f /usr/lib/libkwin.so 2>/dev/null || true); \
	SYS_LIB_HASH=$$(sha256sum "$$SYS_LIB_REAL_UPGRADE" 2>/dev/null | cut -d' ' -f1); \
	BACKUP_LIB_HASH=$$(sha256sum $(BACKUP_LIB) 2>/dev/null | cut -d' ' -f1); \
	CHANGED=0; \
	if [ -f $(BACKUP_KWIN) ] || [ -f $(BACKUP_LIB) ]; then \
		if [ "$$SYS_BIN_HASH" != "$$BACKUP_BIN_HASH" ] || [ "$$SYS_LIB_HASH" != "$$BACKUP_LIB_HASH" ]; then \
			CHANGED=1; \
		fi; \
	fi; \
	if [ "$(FORCE)" = "1" ]; then \
		CHANGED=1; \
	fi; \
	if [ "$$CURRENT_BASE" = "$$TARGET_TAG" ] && [ "$$CHANGED" != "1" ]; then \
		echo "Already on $$TARGET_TAG. Nothing to upgrade."; \
		exit 0; \
	fi; \
	if [ "$$CHANGED" = "1" ] && [ "$$CURRENT_BASE" = "$$TARGET_TAG" ]; then \
		echo "NOTE: System KWin binaries changed on disk (hash mismatch vs backup)"; \
		echo "  although version is still $$TARGET_VER."; \
		echo "  Rebasing is a no-op, but a rebuild+reinstall is needed:"; \
		echo ""; \
	fi; \
	if [ "$$CURRENT_BASE" = "$$TARGET_TAG" ]; then \
		echo "Already based on $$TARGET_TAG. No rebase needed."; \
		echo ""; \
		echo "Next steps:"; \
		echo "  make build && make install"; \
		echo "  (then logout/login to apply)"; \
	else \
		echo "Rebasing $$CURRENT_BASE -> $$TARGET_TAG..."; \
		if git rebase --onto "$$TARGET_TAG" "$$CURRENT_BASE"; then \
			echo ""; \
			echo "Upgrade successful: $$CURRENT_BASE -> $$TARGET_TAG"; \
			echo ""; \
			echo "Next steps:"; \
			echo "  make build && make install"; \
			echo "  (then logout/login to apply)"; \
		else \
			echo ""; \
			echo "CONFLICT during rebase. Resolve, then:"; \
			echo "  git rebase --continue && make build && make install"; \
			echo "To abort: git rebase --abort"; \
			exit 1; \
		fi; \
	fi

force-upgrade:
	@$(MAKE) --no-print-directory upgrade FORCE=1

clean:
	rm -rf $(BUILD_DIR)
