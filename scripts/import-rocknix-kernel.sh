#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${script_dir}/lib/common.sh"
load_thorch_config

usage() {
  cat >&2 <<'EOF'
usage: scripts/import-rocknix-kernel.sh --from-dir <dir> [--boot-dir <dir>] [--root-dir <dir>] [--dest <dir>] [--ref <label>]

Imports prebuilt ROCKNIX kernel artifacts for Thorch. The input may be a mounted
ROCKNIX boot/root filesystem, an extracted ROCKNIX image tree, or separate boot
and root directories.

Required artifacts:
  Image
  dtb/qcom/qcs8550-ayn-thor.dtb
  usr/lib/modules/<kernel-release>/
  usr/lib/libvulkan_freedreno.so
  usr/lib/libdisplay-info.so.0.2.0
  usr/share/fex-emu/libvulkan_freedreno.so
  usr/share/vulkan/icd.d/freedreno_icd*.json

Thorch uses these kernel artifacts unchanged, but generates its own Arch
initramfs and rebuilds /boot/KERNEL during image creation.
EOF
}

require_value() {
  local opt="$1" value="${2:-}"
  [[ -n "${value}" ]] || {
    usage
    die "${opt} requires a value"
  }
}

from_dir=""
boot_dir=""
root_dir=""
dest="${THORCH_ROCKNIX_KERNEL_DIR}"
ref_label="${ROCKNIX_REF}"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --from-dir)
      require_value "$1" "${2:-}"
      from_dir="$2"
      shift 2
      ;;
    --boot-dir)
      require_value "$1" "${2:-}"
      boot_dir="$2"
      shift 2
      ;;
    --root-dir)
      require_value "$1" "${2:-}"
      root_dir="$2"
      shift 2
      ;;
    --dest)
      require_value "$1" "${2:-}"
      dest="$2"
      shift 2
      ;;
    --ref)
      require_value "$1" "${2:-}"
      ref_label="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

if [[ -n "${from_dir}" ]]; then
  boot_dir="${boot_dir:-${from_dir}}"
  root_dir="${root_dir:-${from_dir}}"
fi
[[ -n "${boot_dir}" && -n "${root_dir}" ]] || {
  usage
  die "provide --from-dir or both --boot-dir and --root-dir"
}

require_cmd find install rsync

root="$(repo_root)"
if [[ "${dest}" == /* ]]; then
  dest_abs="$(abspath "${dest}")"
else
  dest_abs="$(abspath "${root}/${dest}")"
fi
boot_dir_abs="$(abspath "${boot_dir}")"
root_dir_abs="$(abspath "${root_dir}")"

case "${boot_dir_abs}:${root_dir_abs}" in
  *"${root}/packages/"*"/pkg"*|*"${root}/packages/"*"/src"*)
    die "refusing to import kernel artifacts from local makepkg pkg/src outputs; use a mounted or extracted ROCKNIX image"
    ;;
esac

find_first() {
  local base="$1"
  shift
  find "${base}" "$@" 2>/dev/null | sort | head -n1
}

image="$(find_first "${boot_dir}" -type f -name Image)"
dtb="$(find_first "${boot_dir}" -type f \( -path '*/dtb/qcom/qcs8550-ayn-thor.dtb' -o -path '*/qcom/qcs8550-ayn-thor.dtb' \))"
kernel_boot="$(find_first "${boot_dir}" -maxdepth 3 -type f -name KERNEL)"
modules_root="$(find_first "${root_dir}" -type d -path '*/usr/lib/modules')"
if [[ -z "${modules_root}" ]]; then
  modules_root="$(find_first "${root_dir}" -type d -path '*/lib/modules')"
fi
firmware_root="$(find_first "${root_dir}" -type d -path '*/usr/lib/firmware')"
if [[ -z "${firmware_root}" ]]; then
  firmware_root="$(find_first "${root_dir}" -type d -path '*/lib/firmware')"
fi

find_runtime_path() {
  local rel="$1" candidate
  for candidate in "${root_dir_abs}" "${root_dir_abs}/system"; do
    if [[ -e "${candidate}/${rel}" || -L "${candidate}/${rel}" ]]; then
      printf '%s\n' "${candidate}/${rel}"
      return 0
    fi
  done
  return 1
}

find_runtime_icd() {
  local candidate found
  for candidate in "${root_dir_abs}" "${root_dir_abs}/system"; do
    [[ -d "${candidate}/usr/share/vulkan/icd.d" ]] || continue
    found="$(find "${candidate}/usr/share/vulkan/icd.d" -maxdepth 1 \( -type f -o -type l \) -name 'freedreno_icd*.json' | sort | head -n1)"
    if [[ -n "${found}" ]]; then
      printf '%s\n' "${found}"
      return 0
    fi
  done
  return 1
}

freedreno_lib="$(find_runtime_path usr/lib/libvulkan_freedreno.so || true)"
display_info_lib="$(find_runtime_path usr/lib/libdisplay-info.so.0.2.0 || true)"
fex_freedreno_lib="$(find_runtime_path usr/share/fex-emu/libvulkan_freedreno.so || true)"
freedreno_icd="$(find_runtime_icd || true)"

[[ -n "${image}" && -f "${image}" ]] || die "could not find ROCKNIX Image under ${boot_dir}"
[[ -n "${dtb}" && -f "${dtb}" ]] || die "could not find qcs8550-ayn-thor.dtb under ${boot_dir}"
[[ -n "${modules_root}" && -d "${modules_root}" ]] || die "could not find ROCKNIX modules under ${root_dir}"
[[ -n "${freedreno_lib}" && -f "${freedreno_lib}" ]] || die "could not find ROCKNIX libvulkan_freedreno.so under ${root_dir}"
[[ -n "${display_info_lib}" && -f "${display_info_lib}" ]] || die "could not find ROCKNIX libdisplay-info.so.0.2.0 under ${root_dir}"
[[ -n "${fex_freedreno_lib}" && -f "${fex_freedreno_lib}" ]] || die "could not find ROCKNIX FEX libvulkan_freedreno.so under ${root_dir}"
[[ -n "${freedreno_icd}" && -f "${freedreno_icd}" ]] || die "could not find ROCKNIX Freedreno Vulkan ICD under ${root_dir}"

rm -rf "${dest_abs}"
install -d "${dest_abs}/boot/dtb/qcom" "${dest_abs}/usr/lib/modules"
install -Dm644 "${image}" "${dest_abs}/boot/Image"
install -Dm644 "${dtb}" "${dest_abs}/boot/dtb/qcom/qcs8550-ayn-thor.dtb"
rsync -a "${modules_root}/" "${dest_abs}/usr/lib/modules/"
if [[ -n "${firmware_root}" && -d "${firmware_root}" ]]; then
  install -d "${dest_abs}/usr/lib/firmware"
  rsync -a "${firmware_root}/" "${dest_abs}/usr/lib/firmware/"
fi
if [[ -n "${kernel_boot}" && -f "${kernel_boot}" ]]; then
  install -Dm644 "${kernel_boot}" "${dest_abs}/boot/KERNEL"
fi
install -Dm755 "${freedreno_lib}" "${dest_abs}/usr/lib/libvulkan_freedreno.so"
install -Dm755 "${display_info_lib}" "${dest_abs}/usr/lib/libdisplay-info.so.0.2.0"
ln -sfn libdisplay-info.so.0.2.0 "${dest_abs}/usr/lib/libdisplay-info.so.2"
install -Dm755 "${fex_freedreno_lib}" "${dest_abs}/usr/share/fex-emu/libvulkan_freedreno.so"
install -Dm644 "${freedreno_icd}" "${dest_abs}/usr/share/vulkan/icd.d/freedreno_icd.json"

{
  printf 'ROCKNIX_REPO=%s\n' "${ROCKNIX_REPO}"
  printf 'ROCKNIX_REF=%s\n' "${ref_label}"
  printf 'SOURCE_BOOT_DIR=%s\n' "${boot_dir_abs}"
  printf 'SOURCE_ROOT_DIR=%s\n' "${root_dir_abs}"
  printf 'SOURCE_IMAGE=%s\n' "${image}"
  printf 'SOURCE_DTB=%s\n' "${dtb}"
  printf 'SOURCE_MODULES=%s\n' "${modules_root}"
  [[ -n "${firmware_root}" ]] && printf 'SOURCE_FIRMWARE_ROOT=%s\n' "${firmware_root}"
  printf 'SOURCE_VULKAN_FREEDRENO=%s\n' "${freedreno_lib}"
  printf 'SOURCE_DISPLAY_INFO=%s\n' "${display_info_lib}"
  printf 'SOURCE_FEX_VULKAN_FREEDRENO=%s\n' "${fex_freedreno_lib}"
  printf 'SOURCE_FREEDRENO_ICD=%s\n' "${freedreno_icd}"
  date -u '+IMPORTED_AT=%Y-%m-%dT%H:%M:%SZ'
} > "${dest_abs}/PROVENANCE"
chmod 0644 "${dest_abs}/PROVENANCE"

log "ROCKNIX kernel artifacts imported to ${dest_abs}"
