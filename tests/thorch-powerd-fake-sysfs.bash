#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source="${root}/packages/thorch-bsp/powerd/thorch-powerd.rs"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

if ! command -v rustc >/dev/null 2>&1; then
  printf 'SKIP: rustc not available\n'
  exit 0
fi

script="${tmp}/thorch-powerd"
rustc "${source}" --edition=2021 -C opt-level=0 -o "${script}"

mkdir -p \
  "${tmp}/sys/class/backlight/panel0" \
  "${tmp}/sys/devices/system/cpu/cpufreq/policy0" \
  "${tmp}/sys/devices/system/cpu/cpu1" \
  "${tmp}/sys/class/devfreq/gpu0" \
  "${tmp}/sys/class/power_supply/battery" \
  "${tmp}/bin"

printf '80\n' > "${tmp}/sys/class/backlight/panel0/brightness"
printf '0\n' > "${tmp}/sys/class/backlight/panel0/bl_power"
printf 'schedutil\n' > "${tmp}/sys/devices/system/cpu/cpufreq/policy0/scaling_governor"
printf 'performance schedutil powersave\n' > "${tmp}/sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors"
printf 'performance\n' > "${tmp}/sys/class/devfreq/gpu0/governor"
printf 'performance powersave\n' > "${tmp}/sys/class/devfreq/gpu0/available_governors"
printf '1\n' > "${tmp}/sys/devices/system/cpu/cpu1/online"
printf 'Discharging\n' > "${tmp}/sys/class/power_supply/battery/status"

cat > "${tmp}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'systemctl %s\n' "$*" >> "${THORCH_FAKE_SYSTEMCTL_LOG:?}"
if [[ "${1:-}" == "is-active" ]]; then
  exit 0
fi
EOF
chmod 755 "${tmp}/bin/systemctl"

cat > "${tmp}/bin/thorch-rgb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'thorch-rgb %s\n' "$*" >> "${THORCH_FAKE_RGB_LOG:?}"
EOF
chmod 755 "${tmp}/bin/thorch-rgb"

run_powerd() {
  PATH="${tmp}/bin:${PATH}" \
  THORCH_POWERD_STATE_DIR="${tmp}/state" \
  THORCH_POWERD_SYSFS_ROOT="${tmp}/sys" \
  THORCH_POWERD_SHUTDOWN_DELAY=0 \
  THORCH_POWERD_PARK_CORES=1 \
  THORCH_FAKE_SYSTEMCTL_LOG="${tmp}/systemctl.log" \
  THORCH_FAKE_RGB_LOG="${tmp}/rgb.log" \
    "${script}" "$@"
}

run_powerd suspend

[[ -e "${tmp}/state/active" ]] || fail "fake suspend did not create active flag"
[[ "$(cat "${tmp}/sys/class/backlight/panel0/bl_power")" == "4" ]] || fail "backlight was not blanked"
[[ "$(cat "${tmp}/sys/devices/system/cpu/cpufreq/policy0/scaling_governor")" == "powersave" ]] || fail "cpu governor was not set to powersave"
[[ "$(cat "${tmp}/sys/class/devfreq/gpu0/governor")" == "powersave" ]] || fail "devfreq governor was not set to powersave"
[[ "$(cat "${tmp}/sys/devices/system/cpu/cpu1/online")" == "0" ]] || fail "cpu1 was not parked"

run_powerd resume

[[ ! -e "${tmp}/state/active" ]] || fail "fake suspend active flag survived resume"
[[ "$(cat "${tmp}/sys/class/backlight/panel0/brightness")" == "80" ]] || fail "backlight brightness was not restored"
[[ "$(cat "${tmp}/sys/class/backlight/panel0/bl_power")" == "0" ]] || fail "backlight power was not restored"
[[ "$(cat "${tmp}/sys/devices/system/cpu/cpufreq/policy0/scaling_governor")" == "schedutil" ]] || fail "cpu governor was not restored"
[[ "$(cat "${tmp}/sys/class/devfreq/gpu0/governor")" == "performance" ]] || fail "devfreq governor was not restored"
[[ "$(cat "${tmp}/sys/devices/system/cpu/cpu1/online")" == "1" ]] || fail "cpu1 was not restored"

actual="$(cat "${tmp}/rgb.log" 2>/dev/null || true)"
expected=$'thorch-rgb poweroff\nthorch-rgb apply-config'
[[ "${actual}" == "${expected}" ]] || fail "unexpected rgb calls: ${actual}"

printf 'ok\n'
