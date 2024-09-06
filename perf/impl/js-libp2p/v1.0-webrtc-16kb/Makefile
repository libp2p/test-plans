all: perf

# https://blog.nicoandres.dev/use-playwright-in-arch-linux/
perf:
	sudo pacman -S --needed core/nss core/nspr extra/at-spi2-core extra/libcups extra/libdrm core/dbus extra/libxcb extra/libxkbcommon extra/at-spi2-core extra/libx11 extra/libxcomposite extra/libxdamage extra/libxext extra/libxfixes extra/libxrandr extra/mesa extra/pango extra/cairo extra/alsa-lib extra/xorg-server-xvfb
	npm ci

clean:
	rm -rf node_modules

.PHONY: all clean perf
