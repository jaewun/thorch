#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${root}/packages/thorch-bsp/payload/usr/bin/thorch-rgb"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_rgb() {
  THORCH_RGB_CONFIG="${tmp}/rgb.conf" \
  THORCH_RGB_SYSFS_ROOT="${tmp}/sys" \
  THORCH_RGB_SKIP_SYSTEMD=1 \
    "${script}" "$@"
}

make_leds() {
  local side color zone dir

  for side in l r; do
    for color in r g b; do
      for zone in 1 2 3 4; do
        dir="${tmp}/sys/class/leds/${side}:${color}${zone}"
        mkdir -p "${dir}"
        printf '0\n' > "${dir}/brightness"
        printf '255\n' > "${dir}/max_brightness"
      done
    done
  done
}

make_battery() {
  local capacity="$1" status="$2" dir

  dir="${tmp}/sys/class/power_supply/battery"
  mkdir -p "${dir}"
  printf '%s\n' "${capacity}" > "${dir}/capacity"
  printf '%s\n' "${status}" > "${dir}/status"
}

assert_file_value() {
  local path="$1" expected="$2" actual

  actual="$(< "${path}")"
  [[ "${actual}" == "${expected}" ]] || fail "${path} expected ${expected}, got ${actual}"
}

assert_channel() {
  local color="$1" expected="$2" path

  shopt -s nullglob
  for path in "${tmp}/sys/class/leds"/[lr]:"${color}"[0-9]*/brightness; do
    assert_file_value "${path}" "${expected}"
  done
  shopt -u nullglob
}

assert_config_mode() {
  local expected="$1"

  grep -qx "THORCH_RGB_MODE=${expected}" "${tmp}/rgb.conf" || fail "config mode is not ${expected}"
}

make_leds
make_battery 60 Discharging

status_output="$(run_rgb status)"
grep -q '^backend: raw-htr3212$' <<< "${status_output}" || fail "status did not detect raw HTR3212 LEDs"

run_rgb set 255 64 0
assert_config_mode static
assert_channel r 255
assert_channel g 64
assert_channel b 0

run_rgb off
assert_config_mode off
assert_channel r 0
assert_channel g 0
assert_channel b 0

run_rgb battery
assert_config_mode battery
assert_channel r 0
assert_channel g 153
assert_channel b 0

printf '8\n' > "${tmp}/sys/class/power_supply/battery/capacity"
printf 'Discharging\n' > "${tmp}/sys/class/power_supply/battery/status"
run_rgb apply-config
assert_channel r 255
assert_channel g 0
assert_channel b 0

if run_rgb set 300 0 0 >/dev/null 2>&1; then
  fail "invalid RGB value unexpectedly succeeded"
fi

rm -rf "${tmp}/sys/class/leds"
if run_rgb set 1 2 3 >/dev/null 2>&1; then
  fail "missing LED sysfs unexpectedly succeeded"
fi

printf 'thorch-rgb fake sysfs tests passed\n'
