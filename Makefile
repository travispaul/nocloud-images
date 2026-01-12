#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2025 Edgecast Cloud LLC.
#

#
# nocloud-images Makefile
#
# Build SmartOS/Triton-compatible nocloud VM images from upstream
# distribution cloud images.
#
# Usage:
#   make IMAGE=alpine      Build a single image
#   make all               Build all discovered images
#   make clean             Remove all build artifacts
#   make clean-zvol UUID=x Remove a stale zvol manually
#

SHELL = /bin/bash
.SHELLFLAGS = -euo pipefail -c

TOP := $(shell pwd)
BUILD_DIR := $(TOP)/build
MANIFEST_TEMPLATE := $(TOP)/manifest.nocloud.in
IMGCONFIGS := $(TOP)/imgconfigs.json
ZVOL_SIZE := 10240

# Auto-discover all image directories (those with a Makefile, excluding root)
IMAGE_DIRS := $(patsubst %/Makefile,%,$(filter-out Makefile,$(wildcard */Makefile)))

# Default target: if IMAGE is set, build it; otherwise show help
ifdef IMAGE
.DEFAULT_GOAL := build
else
.DEFAULT_GOAL := help
endif

.PHONY: help
help:
	@echo "nocloud-images build system"
	@echo ""
	@echo "Usage:"
	@echo "  make IMAGE=<name>    Build a single image"
	@echo "  make all             Build all images"
	@echo "  make clean           Remove all build artifacts"
	@echo "  make clean-zvol UUID=<uuid>  Remove a stale zvol"
	@echo "  make list            List available images"
	@echo "  make publish         Upload built images to Manta"
	@echo ""
	@echo "Available images:"
	@for img in $(IMAGE_DIRS); do echo "  $$img"; done

.PHONY: list
list:
	@for img in $(IMAGE_DIRS); do echo "$$img"; done

# Platform check - must run on SmartOS
.PHONY: check-platform
check-platform:
	@if ! command -v zonename >/dev/null 2>&1; then \
		echo "Error: This build system requires SmartOS."; \
		echo "The 'zonename' command was not found."; \
		exit 1; \
	fi
	@echo "Platform check passed: SmartOS"

# Build all images
.PHONY: all
all: check-platform
	@if [ -z "$(IMAGE_DIRS)" ]; then \
		echo "Error: No image directories found."; \
		echo "Create <name>/Makefile with URL, VERSION, and optionally CHECKSUM."; \
		exit 1; \
	fi
	@for img in $(IMAGE_DIRS); do \
		echo ""; \
		echo "========================================"; \
		echo "Building: $$img"; \
		echo "========================================"; \
		$(MAKE) IMAGE=$$img build-image || exit 1; \
	done
	@echo ""
	@echo "All images built successfully."

# Build a single image
.PHONY: build
build: check-platform
ifndef IMAGE
	$(error IMAGE is not set. Usage: make IMAGE=<name>)
endif
	@$(MAKE) IMAGE=$(IMAGE) build-image

# Internal target that does the actual build
.PHONY: build-image
build-image:
ifndef IMAGE
	$(error IMAGE is not set)
endif
	@# Check image directory exists
	@if [ ! -d "$(TOP)/$(IMAGE)" ]; then \
		echo "Error: Image directory '$(IMAGE)/' not found."; \
		exit 1; \
	fi
	@# Check image Makefile exists
	@if [ ! -f "$(TOP)/$(IMAGE)/Makefile" ]; then \
		echo "Error: $(IMAGE)/Makefile not found."; \
		echo "Create it with URL, VERSION, and optionally CHECKSUM variables."; \
		exit 1; \
	fi
	@# Check imgconfigs.json has entry for this image
	@if ! json -f "$(IMGCONFIGS)" '["$(IMAGE)"]' >/dev/null 2>&1; then \
		echo "Error: No entry for '$(IMAGE)' in imgconfigs.json"; \
		exit 1; \
	fi
	@# Run the build
	@$(MAKE) -f $(TOP)/Makefile.build \
		TOP="$(TOP)" \
		BUILD_DIR="$(BUILD_DIR)" \
		MANIFEST_TEMPLATE="$(MANIFEST_TEMPLATE)" \
		IMGCONFIGS="$(IMGCONFIGS)" \
		ZVOL_SIZE="$(ZVOL_SIZE)" \
		IMAGE="$(IMAGE)" \
		do-build

# Clean all build artifacts
.PHONY: clean
clean:
	@echo "Removing build directory..."
	rm -rf "$(BUILD_DIR)"
	@echo "Clean complete."

# Manual zvol cleanup
.PHONY: clean-zvol
clean-zvol:
ifndef UUID
	$(error UUID is not set. Usage: make clean-zvol UUID=<uuid>)
endif
	@echo "Destroying zvol: zones/$$(zonename)/data/$(UUID)"
	pfexec zfs destroy "zones/$$(zonename)/data/$(UUID)"
	@echo "Zvol destroyed."

# Publish built images to Manta
.PHONY: publish
publish:
	@if [ ! -d "$(BUILD_DIR)" ]; then \
		echo "Error: Build directory not found. Run 'make all' first."; \
		exit 1; \
	fi
	@for f in $(BUILD_DIR)/*/*; do \
		echo "Uploading: $$f"; \
		mput -f "$$f" ~~/public/nocloud/; \
	done
	@echo "Publish complete."
