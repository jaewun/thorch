# Internal Install Notes

Thorch treats SD as staging and recovery media. The intended performance path is
internal UFS storage.

The safest in-image installer flow uses explicit target partitions:

```bash
sudo thorch-install-internal --boot-device /dev/<boot-partition> --root-device /dev/<root-partition>
```

The default target mountpoint is `/mnt/thorch-internal`. A custom `--target` is
accepted only under `/mnt/thorch-internal` or `/run/thorch-installer`.

With no device arguments, the installer may auto-detect exactly one existing
internal ROCKNIX/Thorch Linux target and ask for confirmation before formatting
that target. It will not create new partitions or shrink Android userdata in the
default flow.

Creating a target by shrinking Android `userdata` is an explicit advanced flow:

```bash
sudo thorch-install-internal --create-from-userdata
```

That mode wipes Android userdata, recreates it smaller, creates a 2 GiB
ROCKNIX-compatible boot partition, creates a Thorch root partition in the
remaining space, and requires typed confirmations before repartitioning. The
flow first asks for `SHRINK USERDATA`, then asks how much space Android userdata
should keep, then requires `CREATE THORCH` before changing the partition table.

Safety behavior:

- Refuses to run unless the current root filesystem appears to be on removable
  media or matches the expected Thorch SD layout. Thor can report the SD slot as
  non-removable, so the fallback checks for root on `mmcblk*`, root label
  `THORCH_ROOT`, and `/boot` label `ROCKNIX` on the same card.
- Requires explicit boot/root block devices, one auto-detected existing
  ROCKNIX/Thorch target, or the explicit `--create-from-userdata` mode.
- Refuses common Android partition labels such as `abl`, `boot_a`, `boot_b`,
  `vendor`, `system`, `super`, `metadata`, `userdata`, `dtbo`, `vbmeta`,
  `persist`, `modem`, `bluetooth`, `dsp`, `xbl`, `tz`, `hyp`, `keymaster`, and
  `recovery`.
- Requires the typed confirmation `INSTALL THORCH`.
- Backs up readable existing boot files under `/var/lib/thorch-installer`.
- Formats the selected boot partition as FAT32 label `ROCKNIX`.
- Formats the selected root partition as ext4 label `THORCH_ROOT`.
- Copies the running SD system, writes `fstab`, regenerates initramfs, rebuilds
  `/boot/KERNEL`, and validates the boot directory.

The installer never flashes ABL. The device must already have a Linux-capable ABL
path.

## SD Recovery After Internal Install

The internal Linux boot filesystem is formatted with the ROCKNIX-compatible
label `ROCKNIX` so the layout stays close to the imported ROCKNIX boot image
conventions. Current evidence does not prove that Thor ABL selects Linux media
by that filesystem label; the practical boot contract is a FAT/ESP-style
partition with a top-level `/KERNEL` Android boot image.

On some devices ABL may still load the internal `/KERNEL` before the SD card's
`/KERNEL`. Thorch handles that in the initramfs: when `thorch-sd-prefer` finds
the expected two-partition Thorch SD layout, it switches the root filesystem to
the SD card before fsck and mount. The layout check requires a `ROCKNIX` FAT
boot partition and a `THORCH_ROOT` ext4 root partition on the same `mmcblk`
card. Pass `thorch.sdprefer=0` on the kernel command line to disable the
preference, or `thorch.sdwait=<seconds>` to change the short detection wait.

If the screen says `no match found for DTB!`, the SD or internal FAT partition
has been selected but its top-level `/KERNEL` is wrong for this Thor boot path.
Validate the card or image with:

```bash
make check IMAGE=/dev/sdX
```

The check must pass the Android boot image, root UUID, framebuffer rotation, and
embedded Thor DTB test for `/KERNEL`.
