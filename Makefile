SHELL := /usr/bin/env bash

IMAGE ?= output/thorch-arch-aarch64.img
DEVICE ?=
ROCKNIX_REF ?= next
BOOT_DIR ?=
ROOT_DIR ?=
KERNEL_REF ?= $(ROCKNIX_REF)
THORCH_SUDO_ENV := THORCH_USER,THORCH_PASSWORD,THORCH_IMAGE_SIZE,THORCH_IMAGE_AUTO_HEADROOM,THORCH_BOOT_SIZE,THORCH_DEFAULT_SESSION,THORCH_IMAGE_PACKAGES,THORCH_BUILD_DIR,THORCH_OUTPUT_DIR,THORCH_LOCAL_REPO_DIR,THORCH_ROCKNIX_DIR,THORCH_FIRMWARE_DIR,THORCH_ROCKNIX_KERNEL_DIR,THORCH_ROCKNIX_RUNTIME_DIR,THORCH_KERNEL_SOURCE_BUILD,THORCH_KERNEL_REPO,THORCH_KERNEL_REF,THORCH_KERNEL_TARBALL_URL,THORCH_KERNEL_TARBALL_SHA256,THORCH_KERNEL_CONFIG,THORCH_KERNEL_CONFIG_FRAGMENT,THORCH_KERNEL_PATCH_DIRS,THORCH_KERNEL_DTS_DIR,THORCH_KERNEL_SOURCE_DIR,THORCH_KERNEL_BUILD_DIR,THORCH_KERNEL_CROSS_COMPILE,THORCH_KERNEL_JOBS,ROCKNIX_REF,ROCKNIX_REPO,ROCKNIX_KERNEL_SOURCE,ROCKNIX_KERNEL_RELEASE,ROCKNIX_KERNEL_PLATFORM,ROCKNIX_KERNEL_IMAGE_URL,ROCKNIX_KERNEL_SHA256_URL,ROCKNIX_KERNEL_ALLOW_UNVERIFIED,ROCKNIX_KERNEL_CACHE_DIR,ALARM_ROOTFS_URL,ALARM_ROOTFS_SIG_URL,ALARM_ROOTFS_SHA256,ALARM_ROOTFS_SIGNING_KEYS,ALARM_ROOTFS_KEYRING_URL,ALARM_ROOTFS_KEYSERVER,ALARM_ROOTFS_KEY_FETCH_TIMEOUT,ALARM_MIRRORS,ALARM_MIRROR
THORCH_SUDO := sudo --preserve-env=$(THORCH_SUDO_ENV)

.PHONY: help audit sync firmware kernel import-kernel packages packages-userspace build fast test test-rust check write clean

help:
	@printf '%s\n' \
	  'Thorch build targets:' \
	  '  make sync                         Sync ROCKNIX sources and firmware' \
	  '  make firmware                     Sync firmware only' \
	  '  make kernel                       Sync ROCKNIX runtime, then source-build BinderFS Thor kernel' \
	  '  make import-kernel BOOT_DIR=... ROOT_DIR=... [KERNEL_REF=...]' \
	  '  make packages                     Build all local packages' \
	  '  make packages-userspace           Build local packages except linux-thorch' \
	  '  make build                        Build output/thorch-arch-aarch64.img' \
	  '  make fast                         Fast rebuild after one full build' \
	  '  make test                         Run local test suites' \
	  '  make test-rust                    Run Rust component unit tests' \
	  '  make check [IMAGE=...]            Validate a raw image or block device' \
	  '  make write DEVICE=/dev/sdX        Write IMAGE to removable media' \
	  '  make audit                        Run release/source checks' \
	  '  make clean                        Remove generated build/output artifacts'

audit:
	./scripts/audit-release.sh

sync:
	./scripts/sync-rocknix-sources.sh --ref "$(ROCKNIX_REF)" --with-firmware

firmware:
	./scripts/sync-rocknix-firmware.sh --ref "$(ROCKNIX_REF)"

kernel:
	$(THORCH_SUDO) ./scripts/sync-rocknix-kernel.sh

import-kernel:
	@test -n "$(BOOT_DIR)" || { echo 'BOOT_DIR is required'; exit 2; }
	@test -n "$(ROOT_DIR)" || { echo 'ROOT_DIR is required'; exit 2; }
	./scripts/import-rocknix-kernel.sh --boot-dir "$(BOOT_DIR)" --root-dir "$(ROOT_DIR)" --ref "$(KERNEL_REF)"
	./scripts/import-rocknix-runtime.sh --root-dir "$(ROOT_DIR)" --ref "$(KERNEL_REF)"
	@if [[ "$${THORCH_KERNEL_SOURCE_BUILD:-1}" != "0" ]]; then \
	  $(THORCH_SUDO) ./scripts/build-thorch-kernel.sh; \
	else \
	  echo 'skipping Thorch kernel source build; Waydroid BinderFS support is not guaranteed'; \
	fi

packages:
	$(THORCH_SUDO) ./scripts/build-packages.sh

packages-userspace:
	$(THORCH_SUDO) ./scripts/build-packages.sh --skip-kernel

build:
	$(THORCH_SUDO) ./scripts/build-image.sh

fast:
	$(THORCH_SUDO) ./scripts/build-image-fast.sh

test:
	@for test in tests/*.bash; do \
	  printf '== %s ==\n' "$$test"; \
	  bash "$$test"; \
	done

test-rust:
	./scripts/test-rust-components.sh

check:
	./scripts/check-thorch-image.sh "$(IMAGE)"

write:
	@test -n "$(DEVICE)" || { echo 'DEVICE is required, for example DEVICE=/dev/sdX'; exit 2; }
	./scripts/check-thorch-image.sh "$(IMAGE)"
	$(THORCH_SUDO) ./scripts/write-image.sh "$(IMAGE)" "$(DEVICE)"

clean:
	sudo rm -rf build output
