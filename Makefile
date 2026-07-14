# KWin Patch Manager
# Usage: make [build|install|revert|status|clean|help]

BUILD_DIR   := build
BUILD_BIN   := $(BUILD_DIR)/bin/kwin_wayland
BUILD_LIB   := $(BUILD_DIR)/bin/libkwin.so
SYSTEM_KWIN := /usr/bin/kwin_wayland
BACKUP_KWIN := /usr/bin/kwin_wayland.orig
BACKUP_LIB  := /usr/lib/libkwin.so.orig

.PHONY: build install revert status clean help

help:
	@echo "KWin Patch Manager"
	@echo ""
	@echo "  make build    - Build patched KWin (no RUNPATH)"
	@echo "  make install  - Install patched KWin (backups original first)"
	@echo "  make revert   - Restore original system KWin"
	@echo "  make status   - Show current status"
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

clean:
	rm -rf $(BUILD_DIR)
