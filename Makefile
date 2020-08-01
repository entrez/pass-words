EXTENSION ?= words
PREFIX ?= /usr
DESTDIR ?=
LIBDIR ?= $(PREFIX)/lib
SYSTEM_EXTENSION_DIR ?= $(LIBDIR)/password-store/extensions

all:
	@echo "pass-$(EXTENSION) is a shell script and does not need compilation, it can be simply executed."
	@echo ""
	@echo "To install it try \"make install\" instead."
	@echo
	@echo "To run pass $(EXTENSION) one needs to have some tools installed on the system:"
	@echo "     password store"

install:
	@install -v -d "$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/"
	@install -v -m0755 src/$(EXTENSION).bash "$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/$(EXTENSION).bash"
	@echo
	@echo "pass-$(EXTENSION) is installed succesfully"
	@echo

uninstall:
	@rm -vrf \
		"$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/$(EXTENSION).bash" \

lint:
	shellcheck -s bash src/$(EXTENSION).bash

.PHONY: install uninstall lint

