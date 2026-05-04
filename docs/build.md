# Build Notes

Thorch v1 intentionally reuses the kernel artifacts from a working ROCKNIX SM8550
build. Thorch supplies the Arch Linux ARM root filesystem, KDE defaults,
firmware package, initramfs, and installer tooling.

Before building packages or images, sync the public ROCKNIX SM8550 firmware and
metadata:

```bash
make sync ROCKNIX_REF=<rocknix-commit>
```

This populates `vendor/rocknix-sm8550` with inputplumber overlays and firmware.
The `SOURCE_PROVENANCE` and `firmware/THORCH_FIRMWARE_PROVENANCE` files record
the requested and resolved ROCKNIX refs.

The ROCKNIX kernel sync requires `curl`, `jq`, `losetup`, `mount`,
`sha256sum`, `unsquashfs`, and `python3` on the build host. On Arch-like hosts,
`unsquashfs` is provided by `squashfs-tools`.

Then import the prebuilt ROCKNIX kernel and runtime artifacts from an official
ROCKNIX image. This is a required clean-build input; `make sync` only downloads
public source overlays and firmware, not a bootable prebuilt kernel tree or FEX
runtime. By default, the kernel sync downloads the latest official ROCKNIX SM8550
nightly, verifies its `.sha256`, extracts `/KERNEL` and `/SYSTEM`, and
normalizes the result into `vendor/rocknix-kernel` and
`vendor/rocknix-runtime`:

```bash
make kernel
```

You can also import from a mounted or extracted ROCKNIX image. The importer
expects `KERNEL`, `Image`, and matching `usr/lib/modules/<kernel-release>/`:

```bash
make import-kernel BOOT_DIR=/mnt/rocknix-boot ROOT_DIR=/mnt/rocknix-root KERNEL_REF=<rocknix-build-label>
```

Package and image builders reject smoke-test or local `makepkg` kernel
provenance. Re-import the kernel from a real ROCKNIX image before preparing
release artifacts.

For clean-room testing, do not import from previous Thorch output directories,
copied `vendor/rocknix-kernel` trees, or locally built package payloads. Use a
freshly mounted or freshly extracted ROCKNIX image and keep the `KERNEL_REF`
label tied to that input.

`make build` and `make packages` run `scripts/sync-rocknix-kernel.sh`
automatically when `vendor/rocknix-kernel/boot/KERNEL`,
`vendor/rocknix-kernel/boot/Image`, or the imported FEX runtime is missing. To
pin a specific upstream image, set one of:

```bash
ROCKNIX_KERNEL_SOURCE=stable ROCKNIX_KERNEL_RELEASE=latest make kernel
ROCKNIX_KERNEL_RELEASE=nightly-20260430 make kernel
ROCKNIX_KERNEL_RELEASE=nightly-20260428 make kernel
ROCKNIX_KERNEL_IMAGE_URL=https://.../ROCKNIX-SM8550.aarch64-YYYYMMDD.img.gz make kernel
```

`ROCKNIX_KERNEL_SOURCE` defaults to `nightly`; use `stable` when importing from
the latest stable ROCKNIX release stream. If an upstream image has no matching
`.sha256` asset, the sync refuses the import unless you provide
`ROCKNIX_KERNEL_SHA256_URL` or explicitly set `ROCKNIX_KERNEL_ALLOW_UNVERIFIED=1`
for a local experiment.

Package builds happen in an Arch Linux ARM aarch64 rootfs through
`systemd-nspawn` and `qemu-aarch64-static`. The builder copies Thorch package
inputs into the rootfs instead of bind-mounting the repository:

```bash
make packages
```

During userspace iteration, skip repackaging the imported kernel:

```bash
make packages-userspace
```

The full image build downloads the Arch Linux ARM aarch64 rootfs, prunes stock
kernel/firmware packages from the chroot, installs the selected local Thorch
packages, creates a GPT raw image, and generates the ABL `/KERNEL` boot image:

```bash
make build
```

The generated `/KERNEL` is repacked from the imported ROCKNIX boot image.
`thorch-rebuild-abl-kernel` preserves ROCKNIX's kernel payload, including the
embedded Thor DTB, and replaces the ramdisk plus root UUID command line for the
generated image. An imported ROCKNIX `/KERNEL` is required.

The image builder assembles FAT and ext4 filesystem images directly and writes
them into a raw GPT image. It does not mount image partitions or bind-mount host
API filesystems.

The boot partition defaults to 512 MiB and the raw image defaults to 8 GiB. Use
`THORCH_BOOT_SIZE` and `THORCH_IMAGE_SIZE` when a different layout is needed.

If the build host cannot show interactive `sudo` prompts, invoke the scripts
through PolicyKit so the desktop authentication agent can prompt visibly:

```bash
pkexec ./scripts/build-image.sh
pkexec ./scripts/sync-rocknix-kernel.sh
```

For userspace package/default/service changes, use the fast rebuild path:

```bash
make fast
```

This wrapper rebuilds only missing or stale local Thorch packages, refreshes
`build/image-rootfs` when it exists, regenerates initramfs and `/boot/KERNEL`,
and reassembles `output/thorch-arch-aarch64.img`. If `build/image-rootfs` does
not exist yet, it is created from the local package repo after the package
refresh. If imported ROCKNIX kernel artifacts changed, run
`scripts/build-image-fast.sh --with-kernel`.

The default image package set is:

```bash
linux-thorch thorch-bsp thorch-firmware-rocknix thorch-kde-defaults thorch-installer thorch-fex-bin thorch-gamescope thorch-gaming-installers thorch-inputplumber thorch-rocknix-quirks thorch-mangohud
```

`thorch-kde-defaults` installs Firefox and the core KDE desktop applications:
Ark, Dolphin, Gwenview, Kate, KCalc, Konsole, Okular, and Spectacle.

Override `THORCH_IMAGE_PACKAGES` with the complete local package set when you
want a custom image, for example:

```bash
THORCH_IMAGE_PACKAGES='linux-thorch thorch-bsp thorch-firmware-rocknix thorch-kde-defaults thorch-installer' make build
```

To write an image to SD, use the removable-device writer. It refuses mounted,
read-only, non-removable, or partition targets and does not mount or unmount
anything. The `make write` target runs `make check` first so a stale or
incorrect `/KERNEL` is caught before the card is overwritten:

```bash
make write DEVICE=/dev/sdX
```

With PolicyKit instead of `sudo`:

```bash
pkexec ./scripts/write-image.sh output/thorch-arch-aarch64.img /dev/sdX
```

To validate a card after writing, pass the whole SD block device:

```bash
make check IMAGE=/dev/sdX
```

If Thor shows `no match found for DTB!`, the bootloader has selected the FAT
boot partition but rejected `/KERNEL`. Check the SD with `make check
IMAGE=/dev/sdX`; the `/KERNEL` check must report that it embeds the Thor DTB.

## Important Environment

- `ROCKNIX_REF`: ROCKNIX branch, tag, or commit to sync.
- `ROCKNIX_REPO`: ROCKNIX distribution repository URL.
- `ROCKNIX_KERNEL_SOURCE`: ROCKNIX image release stream, `nightly` by default; can be `stable`.
- `ROCKNIX_KERNEL_RELEASE`: release tag/date to import, default `latest`.
- `ROCKNIX_KERNEL_PLATFORM`: ROCKNIX platform name, default `SM8550`.
- `ROCKNIX_KERNEL_IMAGE_URL`: explicit ROCKNIX `.img` or `.img.gz` URL.
- `ROCKNIX_KERNEL_SHA256_URL`: explicit checksum URL for the ROCKNIX image.
- `ROCKNIX_KERNEL_CACHE_DIR`: download/decompression cache, default `build/cache/rocknix`.
- `THORCH_USER`: default image user, default `thorch`.
- `THORCH_PASSWORD`: password/PIN for the default user and root, default `1234`.
- `THORCH_IMAGE_SIZE`: raw image size, default `8G`.
- `THORCH_BOOT_SIZE`: FAT boot partition size, default `512M`.
- `THORCH_DEFAULT_SESSION`: `plasma-desktop` by default; use `plasma-mobile` to test the mobile shell.
- `THORCH_IMAGE_PACKAGES`: local packages installed into the image.
- `THORCH_BUILD_DIR`: build work directory, default `build`.
- `THORCH_OUTPUT_DIR`: image/package output directory, default `output`.
- `THORCH_LOCAL_REPO_DIR`: local package repository path, default `output/repo`.
- `THORCH_ROCKNIX_DIR`: synced ROCKNIX source/overlay directory.
- `THORCH_FIRMWARE_DIR`: synced ROCKNIX firmware directory.
- `THORCH_ROCKNIX_KERNEL_DIR`: imported ROCKNIX kernel artifact directory.
- `THORCH_ROCKNIX_RUNTIME_DIR`: imported ROCKNIX runtime/FEX artifact directory.
- `ALARM_ROOTFS_URL`: Arch Linux ARM aarch64 rootfs URL.
- `ALARM_ROOTFS_SIG_URL`: detached signature URL for the Arch Linux ARM rootfs.
- `ALARM_ROOTFS_SIGNING_KEYS`: pinned trusted rootfs signing fingerprints.
- `ALARM_ROOTFS_KEYRING_URL`: Arch Linux ARM keyring package URL used to import missing pinned signing keys.
- `ALARM_ROOTFS_KEYSERVER`: optional fallback keyserver used to fetch missing pinned signing keys.
- `ALARM_ROOTFS_KEY_FETCH_TIMEOUT`: timeout for rootfs signing-key fetches.
- `ALARM_ROOTFS_SHA256`: pinned Arch Linux ARM rootfs hash, used instead of signature verification when set.
- `ALARM_MIRRORS`: space-separated Arch Linux ARM pacman mirror bases written into the image.
- `ALARM_MIRROR`: Arch Linux ARM pacman mirror base.
- `ROCKNIX_KERNEL_ALLOW_UNVERIFIED`: set to `1` only for local experiments that intentionally import an unverified ROCKNIX image.
