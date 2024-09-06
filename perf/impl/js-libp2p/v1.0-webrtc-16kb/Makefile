all: perf

perf:
# https://github.com/microsoft/playwright/issues/2621#issuecomment-1798390973
# Install Playwright dependencies
	sudo yum install -y atk at-spi2-atk libdrm libXcomposite libXdamage libXfixes libXrandr mesa-libgbm alsa-lib cups-libs libXScrnSaver pango xorg-x11-fonts-100dpi xorg-x11-fonts-75dpi xorg-x11-utils xorg-x11-fonts-cyrillic xorg-x11-fonts-Type1 xorg-x11-fonts-misc

# Install Xvfb for headless execution
	sudo yum install -y xorg-x11-server-Xvfb

	npm ci

clean:
	rm -rf node_modules

.PHONY: all clean perf
