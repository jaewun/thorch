#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${root}/packages/thorch-gaming-installers/payload/usr/bin/thorch-install-fex"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

cat > "${tmp}/FEX" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${*}" == "/bin/uname -m" ]]; then
  printf 'x86_64\n'
  exit 0
fi
printf 'unexpected FEX invocation: %s\n' "$*" >&2
exit 2
EOF
chmod 755 "${tmp}/FEX"

cat > "${tmp}/FEXRootFSFetcher" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'FEXRootFSFetcher %s\n' "$*" >> "${FAKE_COMMAND_LOG:?}"
mkdir -p "${FEX_ROOTFS_DIR:?}"
printf 'valid squashfs\n' > "${FEX_ROOTFS_DIR}/ArchLinux.sqsh"
EOF
chmod 755 "${tmp}/FEXRootFSFetcher"

cat > "${tmp}/unsquashfs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-s" ]]; then
  grep -q 'valid squashfs' "${2:?}"
  exit $?
fi

dest=""
source=""
while [[ "$#" -gt 0 ]]; do
  case "${1}" in
    -d)
      dest="${2:?}"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      source="${1}"
      shift
      ;;
  esac
done

[[ -n "${dest}" && -n "${source}" ]] || exit 2
grep -q 'valid squashfs' "${source}" || exit 1
mkdir -p "${dest}/usr/lib" "${dest}/bin"
printf '#!/bin/sh\n' > "${dest}/bin/sh"
printf 'x86 guest lib\n' > "${dest}/usr/lib/libvulkan_freedreno.so"
EOF
chmod 755 "${tmp}/unsquashfs"

cat > "${tmp}/file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s: ELF 64-bit LSB shared object, x86-64\n' "${1:-file}"
EOF
chmod 755 "${tmp}/file"

home="${tmp}/home"
rootfs_dir="${home}/.fex-emu/RootFS"
mkdir -p "${rootfs_dir}"
printf 'truncated download\n' > "${rootfs_dir}/ArchLinux.sqsh"

FAKE_COMMAND_LOG="${tmp}/commands.log" \
  HOME="${home}" \
  FEX_ROOTFS_DIR="${rootfs_dir}" \
  PATH="${tmp}:${PATH}" \
  "${script}" >/dev/null

grep -qx 'FEXRootFSFetcher -y -x --distro-name arch --distro-version rolling' "${tmp}/commands.log" ||
  fail "FEXRootFSFetcher was not invoked after corrupt rootfs was found"

compgen -G "${rootfs_dir}/ArchLinux.sqsh.invalid.*" >/dev/null ||
  fail "corrupt rootfs was not moved aside"

grep -q 'valid squashfs' "${rootfs_dir}/ArchLinux.sqsh" ||
  fail "replacement rootfs was not installed"

[[ -d "${rootfs_dir}/ArchLinux/usr/lib" ]] ||
  fail "replacement rootfs was not unpacked"

grep -q '"RootFS": "ArchLinux"' "${home}/.config/fex-emu/Config.json" ||
  fail "FEX config was not pointed at unpacked rootfs"

printf 'thorch install FEX corrupt rootfs test passed\n'
