PREFIX ?= /usr/local

.PHONY: build install uninstall test clean

build:
	swift build -c release

install: build
	install -d "$(PREFIX)/bin"
	install -m 755 .build/release/whodis "$(PREFIX)/bin/whodis"

uninstall:
	rm -f "$(PREFIX)/bin/whodis"

test:
	swift test

clean:
	rm -rf .build
