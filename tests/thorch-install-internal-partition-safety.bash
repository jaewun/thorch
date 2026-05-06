#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${root}/packages/thorch-installer/payload/usr/bin/thorch-install-internal"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

load_installer_functions() {
  source <(sed '/^require_root$/,$d' "${script}")
}

test_blank_rocknix_partlabel_detection() (
  load_installer_functions

  findmnt() {
    if [[ "$*" == "-n -o SOURCE /" ]]; then
      printf '/dev/mmcblk0p2\n'
      return 0
    fi
    return 1
  }

  blkid() {
    case "$*" in
      "-s LABEL -o value /dev/nvme0n1p11") printf 'THORCH_ROOT\n' ;;
      *) return 2 ;;
    esac
  }

  lsblk() {
    case "$*" in
      "-nrpo NAME,TYPE")
        printf '/dev/mmcblk0 disk\n/dev/mmcblk0p2 part\n/dev/nvme0n1 disk\n/dev/nvme0n1p10 part\n/dev/nvme0n1p11 part\n'
        ;;
      "-no PKNAME /dev/mmcblk0p2") printf 'mmcblk0\n' ;;
      "-no PKNAME /dev/nvme0n1p10"|"-no PKNAME /dev/nvme0n1p11") printf 'nvme0n1\n' ;;
      "-no FSTYPE /dev/nvme0n1p10") return 0 ;;
      "-no FSTYPE /dev/nvme0n1p11") printf 'ext4\n' ;;
      "-no PARTLABEL /dev/nvme0n1p10") printf 'ROCKNIX\n' ;;
      "-no PARTLABEL /dev/nvme0n1p11") printf 'STORAGE\n' ;;
      "-no NAME,LABEL,PARTLABEL /dev/nvme0n1p10") printf 'nvme0n1p10  ROCKNIX\n' ;;
      "-no NAME,LABEL,PARTLABEL /dev/nvme0n1p11") printf 'nvme0n1p11 THORCH_ROOT STORAGE\n' ;;
      *) return 1 ;;
    esac
  }

  find_thorch_internal_target
  [[ "${boot_device}" == "/dev/nvme0n1p10" ]] || fail "blank ROCKNIX boot was not selected"
  [[ "${root_device}" == "/dev/nvme0n1p11" ]] || fail "matching root was not selected"
)

test_partition_start_byte_conversion_for_adjacency() (
  load_installer_functions

  findmnt() {
    if [[ "$*" == "-n -o SOURCE /" ]]; then
      printf '/dev/mmcblk0p2\n'
      return 0
    fi
    return 1
  }

  readlink() {
    if [[ "$1" == "-f" ]]; then
      printf '%s\n' "$2"
      return 0
    fi
    command readlink "$@"
  }

  blockdev() {
    case "$*" in
      "--getsize64 /dev/nvme0n1p10"|"--getsize64 /dev/nvme0n1p12") printf '1048576\n' ;;
      *) return 1 ;;
    esac
  }

  blkid() {
    case "$*" in
      "-s LABEL -o value /dev/nvme0n1p10"|"-s LABEL -o value /dev/nvme0n1p12") printf 'ROCKNIX\n' ;;
      "-s LABEL -o value /dev/nvme0n1p11"|"-s LABEL -o value /dev/nvme0n1p13") printf 'THORCH_ROOT\n' ;;
      *) return 2 ;;
    esac
  }

  lsblk() {
    case "$*" in
      "-nrpo NAME,TYPE")
        printf '/dev/mmcblk0 disk\n/dev/mmcblk0p2 part\n/dev/nvme0n1 disk\n/dev/nvme0n1p10 part\n/dev/nvme0n1p11 part\n/dev/nvme0n1p12 part\n/dev/nvme0n1p13 part\n'
        ;;
      "-no PKNAME /dev/mmcblk0p2") printf 'mmcblk0\n' ;;
      "-no PKNAME /dev/nvme0n1p10"|"-no PKNAME /dev/nvme0n1p11"|"-no PKNAME /dev/nvme0n1p12"|"-no PKNAME /dev/nvme0n1p13") printf 'nvme0n1\n' ;;
      "-no FSTYPE /dev/nvme0n1p10"|"-no FSTYPE /dev/nvme0n1p12") printf 'vfat\n' ;;
      "-no FSTYPE /dev/nvme0n1p11"|"-no FSTYPE /dev/nvme0n1p13") printf 'ext4\n' ;;
      "-no PARTLABEL /dev/nvme0n1p10"|"-no PARTLABEL /dev/nvme0n1p12") printf 'ROCKNIX\n' ;;
      "-no PARTLABEL /dev/nvme0n1p11"|"-no PARTLABEL /dev/nvme0n1p13") printf 'STORAGE\n' ;;
      "-no NAME,LABEL,PARTLABEL "*) printf 'mock\n' ;;
      "-no START /dev/nvme0n1p10") printf '2048\n' ;;
      "-no START /dev/nvme0n1p11") printf '4096\n' ;;
      "-no START /dev/nvme0n1p12") printf '8192\n' ;;
      "-no START /dev/nvme0n1p13") printf '20000\n' ;;
      *) return 1 ;;
    esac
  }

  find_thorch_internal_target
  [[ "${boot_device}" == "/dev/nvme0n1p10" ]] || fail "adjacent boot was not selected"
  [[ "${root_device}" == "/dev/nvme0n1p11" ]] || fail "adjacent root was not selected"
)

test_reuse_confirmation_precedes_deletion() {
  local log="${tmp}/reuse-mutating-commands.log"
  set +e
  (
    load_installer_functions

    findmnt() { return 1; }
    readlink() {
      if [[ "$1" == "-f" ]]; then
        printf '%s\n' "$2"
        return 0
      fi
      command readlink "$@"
    }
    blockdev() { printf '68719476736\n'; }
    lsblk() {
      case "$*" in
        "-no START "*) printf '67108864\n' ;;
        "-nrpo NAME,TYPE /dev/nvme0n1") printf '/dev/nvme0n1p1 part\n/dev/nvme0n1p2 part\n' ;;
        *) return 0 ;;
      esac
    }
    parted() {
      if [[ "$*" == "-m -s /dev/nvme0n1 unit B print" ]]; then
        printf 'BYT;\n/dev/nvme0n1:68719476736B:gpt:512:512:gpt:mock:;\n1:1048576B:34359738367B:34358689792B:ext4:userdata:;\n2:34359738368B:42949672959B:8589934592B:ext4:STORAGE:;\n'
        return 0
      fi
      case "$*" in
        *" rm "*|*" mkpart "*) printf '%s\n' "$*" >> "${log}" ;;
      esac
      return 0
    }

    printf 'NOPE\n' | create_target_by_reusing_resized_userdata /dev/nvme0n1
  ) >/dev/null 2>&1
  local rc=$?
  set -e
  [[ ${rc} -ne 0 ]] || fail "reuse path accepted a bad CREATE THORCH confirmation"
  [[ ! -s "${log}" ]] || fail "reuse path mutated partitions before confirmation: $(cat "${log}")"
}

test_shrink_confirmation_precedes_userdata_wipe() {
  local log="${tmp}/shrink-mutating-commands.log"
  set +e
  (
    load_installer_functions

    findmnt() { return 1; }
    readlink() {
      if [[ "$1" == "-f" ]]; then
        printf '%s\n' "$2"
        return 0
      fi
      command readlink "$@"
    }
    blockdev() { printf '68719476736\n'; }
    lsblk() { return 0; }
    parted() {
      if [[ "$*" == "-m -s /dev/nvme0n1 unit B print" ]]; then
        printf 'BYT;\n/dev/nvme0n1:68719476736B:gpt:512:512:gpt:mock:;\n1:1048576B:67645734912B:67644686336B:ext4:userdata:;\n'
        return 0
      fi
      case "$*" in
        *" rm "*|*" mkpart "*) printf '%s\n' "$*" >> "${log}" ;;
      esac
      return 0
    }
    dd() {
      printf 'dd %s\n' "$*" >> "${log}"
      return 0
    }

    printf 'SHRINK USERDATA\n8\nNOPE\n' | create_target_by_shrinking_userdata /dev/nvme0n1
  ) >/dev/null 2>&1
  local rc=$?
  set -e
  [[ ${rc} -ne 0 ]] || fail "shrink path accepted a bad CREATE THORCH confirmation"
  [[ ! -s "${log}" ]] || fail "shrink path mutated userdata before final confirmation: $(cat "${log}")"
}

test_blank_rocknix_partlabel_detection
test_partition_start_byte_conversion_for_adjacency
test_reuse_confirmation_precedes_deletion
test_shrink_confirmation_precedes_userdata_wipe

printf 'thorch internal installer partition safety tests passed\n'
