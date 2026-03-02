# nOS Build System — Nosface Wayland DE
# GNU Make

NOSVERSION  ?= 1.0.0
ARCH        ?= amd64
FBSD_VER    ?= 14.1-RELEASE
FBSD_BRANCH ?= releng/14.1
SRCDIR      ?= /usr/src
OBJDIR      ?= /usr/obj
DISTDIR     ?= $(PWD)/dist

# Compositor build directory
COMP_DIR    := compositor
COMP_BUILD  := $(COMP_DIR)/build

.PHONY: all deps fetch world kernel build image compositor compositor-clean \
        install-shell clean

all: compositor build image

# ---------------------------------------------------------------------------
# Build dependencies (run on build host)
# ---------------------------------------------------------------------------
deps:
	pkg install -y \
	    git-lite \
	    dialog \
	    xorriso \
	    grub2 \
	    qemu-utils \
	    meson \
	    ninja \
	    pkgconf \
	    wlroots \
	    wayland \
	    libinput \
	    pixman \
	    libxkbcommon \
	    mesa-libs \
	    egl-wayland \
	    python3 \
	    py39-gobject3 \
	    gtk3 \
	    gtk-layer-shell

# ---------------------------------------------------------------------------
# noscomp compositor (Meson/Ninja)
# ---------------------------------------------------------------------------
compositor: $(COMP_BUILD)/build.ninja
	@echo ">>> Building noscomp compositor..."
	ninja -C $(COMP_BUILD)

$(COMP_BUILD)/build.ninja: $(COMP_DIR)/meson.build
	@echo ">>> Configuring noscomp with Meson..."
	meson setup $(COMP_BUILD) $(COMP_DIR) --buildtype=release

compositor-clean:
	rm -rf $(COMP_BUILD)
	@echo "noscomp build directory removed."

# ---------------------------------------------------------------------------
# FreeBSD base system
# ---------------------------------------------------------------------------
fetch:
	@[ -d $(SRCDIR)/.git ] || git clone \
	    --depth 1 \
	    --branch $(FBSD_BRANCH) \
	    https://git.FreeBSD.org/src.git \
	    $(SRCDIR)

world: fetch
	@echo ">>> Building FreeBSD world..."
	cd $(SRCDIR) && make -j$(shell sysctl -n hw.ncpu 2>/dev/null || nproc) buildworld \
	    SRCCONF=$(PWD)/build/config/src.conf \
	    TARGET=$(ARCH)

kernel: fetch
	@echo ">>> Building nOS kernel..."
	cd $(SRCDIR) && make -j$(shell sysctl -n hw.ncpu 2>/dev/null || nproc) buildkernel \
	    KERNCONF=NOSKERNEL \
	    KERNCONFDIR=$(PWD)/build/config \
	    TARGET=$(ARCH)

build: world kernel
	@sh build/build.sh $(ARCH) $(FBSD_VER)

image:
	@echo ">>> Creating bootable image..."
	@sh build/mkimage.sh $(ARCH) $(NOSVERSION)

# ---------------------------------------------------------------------------
# Install shell components locally (for development)
# ---------------------------------------------------------------------------
install-shell:
	@echo ">>> Installing Nosface shell components..."
	install -Dm755 shell/nosface-bar/bar.py       /usr/local/lib/nosface/shell/nosface-bar/bar.py
	install -Dm644 shell/nosface-bar/style.css    /usr/local/lib/nosface/shell/nosface-bar/style.css
	install -Dm755 shell/nosface-dock/dock.py     /usr/local/lib/nosface/shell/nosface-dock/dock.py
	install -Dm644 shell/nosface-dock/style.css   /usr/local/lib/nosface/shell/nosface-dock/style.css
	install -Dm755 shell/nosface-launcher/launcher.py /usr/local/lib/nosface/shell/nosface-launcher/launcher.py
	install -Dm644 shell/nosface-launcher/style.css   /usr/local/lib/nosface/shell/nosface-launcher/style.css
	install -Dm755 shell/nosface-notify/notify.py  /usr/local/lib/nosface/shell/nosface-notify/notify.py
	install -Dm644 shell/nosface-notify/style.css  /usr/local/lib/nosface/shell/nosface-notify/style.css
	# Themes
	install -Dm644 themes/dark/theme.css   /usr/local/share/nosface/themes/dark/theme.css
	install -Dm755 themes/dark/colors.sh  /usr/local/share/nosface/themes/dark/colors.sh
	install -Dm644 themes/light/theme.css  /usr/local/share/nosface/themes/light/theme.css
	install -Dm755 themes/light/colors.sh /usr/local/share/nosface/themes/light/colors.sh
	# Wrappers
	@for comp in nosface-bar nosface-dock nosface-launcher nosface-notify; do \
	    script="$$(echo $$comp | sed 's/nosface-//')"; \
	    printf '#!/bin/sh\nexec python3 /usr/local/lib/nosface/shell/%s/%s.py "$$@"\n' \
	        $$comp $$script > /usr/local/bin/$$comp; \
	    chmod +x /usr/local/bin/$$comp; \
	done
	@echo "Shell components installed."

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
clean: compositor-clean
	rm -rf $(DISTDIR)
	@echo "Clean complete."
