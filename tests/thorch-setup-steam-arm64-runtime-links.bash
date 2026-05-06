#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${root}/packages/thorch-gaming-installers/payload/usr/bin/thorch-setup-steam-arm64"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

steam_root="${tmp}/.local/share/Steam"
runtime_lib_dir="${steam_root}/steam-runtime-steamrt-arm64/fake/files/lib/aarch64-linux-gnu"
mkdir -p "${runtime_lib_dir}"
touch \
  "${runtime_lib_dir}/libibus-1.0.so.5.0.5200" \
  "${runtime_lib_dir}/libgtk-x11-2.0.so.0.2400.33" \
  "${runtime_lib_dir}/libgdk-x11-2.0.so.0.2400.33"

STEAM_STORAGE_ROOT="${tmp}" "${script}" --repair-proton-beta-runtime-links

link_dir="${steam_root}/lib/aarch64-linux-gnu"
for soname in libibus-1.0.so.5 libgtk-x11-2.0.so.0 libgdk-x11-2.0.so.0; do
  [[ -L "${link_dir}/${soname}" ]] || fail "missing ${soname} link"
  target="$(readlink "${link_dir}/${soname}")"
  [[ "${target}" == "${runtime_lib_dir}/${soname}."* ]] ||
    fail "${soname} link points at unexpected target: ${target}"
done

printf 'thorch Steam ARM64 runtime link tests passed\n'
