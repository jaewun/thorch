#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${root}/packages/thorch-bsp/payload/usr/bin/thorch-backlight"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

make_backlight() {
  local name="$1" brightness="$2" max="$3" dir

  dir="${tmp}/sys/class/backlight/${name}"
  mkdir -p "${dir}"
  printf '%s\n' "${brightness}" > "${dir}/brightness"
  printf '%s\n' "${max}" > "${dir}/max_brightness"
}

brightness() {
  local name="$1"

  cat "${tmp}/sys/class/backlight/${name}/brightness"
}

run_backlight() {
  THORCH_BACKLIGHT_SYSFS_ROOT="${tmp}/sys" "$script" "$@"
}

assert_brightness() {
  local name="$1" expected="$2" actual

  actual="$(brightness "${name}")"
  [[ "${actual}" == "${expected}" ]] || fail "${name} expected ${expected}, got ${actual}"
}

make_backlight ae94000.dsi.0 100 200
make_backlight ae96000.dsi.0 10 100

run_backlight up all 10
assert_brightness ae94000.dsi.0 120
assert_brightness ae96000.dsi.0 20

run_backlight down all 50
assert_brightness ae94000.dsi.0 20
assert_brightness ae96000.dsi.0 1

run_backlight set all 999
assert_brightness ae94000.dsi.0 200
assert_brightness ae96000.dsi.0 100

status="$(run_backlight status)"
[[ "${status}" == $'bottom 200 200\ntop 100 100' ]] || fail "unexpected status: ${status}"

printf 'ok\n'
