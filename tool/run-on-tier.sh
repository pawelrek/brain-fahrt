#!/usr/bin/env bash
# Launch the Flutter app on a tiered Android emulator.
#
#   ./tool/run-on-tier.sh low        # boot the budget-tier AVD, then `flutter run`
#   ./tool/run-on-tier.sh mid        # boot the mainstream-tier AVD, then `flutter run`
#   ./tool/run-on-tier.sh flagship   # boot the top-tier AVD, then `flutter run`
#   ./tool/run-on-tier.sh all        # boot all three AVDs (then run on each)
#
# Emulators identify by AVD NAME, not port, so this coexists with any other
# emulator you already have running (e.g. pixel_m1) and never targets the wrong one.
#
# Note: emulators emulate screen/density/RAM/CPU + a stock Android image — NOT a
# vendor skin (One UI, HyperOS, etc.). For real OEM behaviour use a real device
# or a device cloud (Samsung Remote Test Lab, Firebase Test Lab, BrowserStack...).
set -euo pipefail

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
EMULATOR="$SDK/emulator/emulator"
ADB="$SDK/platform-tools/adb"

avd_for() {
  case "$1" in
    low)      echo "slop_low" ;;
    mid)      echo "slop_mid" ;;
    flagship) echo "slop_flagship" ;;
    *)        echo "" ;;
  esac
}

# Print the adb serial of a running AVD (matched by name); empty if not running.
serial_of() {
  local want="$1" s n
  for s in $("$ADB" devices | awk '/^emulator-/{print $1}'); do
    n=$("$ADB" -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')
    [ "$n" = "$want" ] && { echo "$s"; return; }
  done
}

# Boot an AVD by name (auto-assigned port); print its serial on stdout when ready.
boot() {
  local avd="$1" s
  s="$(serial_of "$avd")"
  if [ -z "$s" ]; then
    echo "▶ Booting $avd ..." >&2
    "$EMULATOR" "@$avd" -no-snapshot-save -gpu auto >/dev/null 2>&1 &
    for _ in $(seq 1 90); do s="$(serial_of "$avd")"; [ -n "$s" ] && break; sleep 2; done
    [ -z "$s" ] && { echo "ERROR: $avd did not register with adb" >&2; exit 1; }
  else
    echo "▶ $avd already running ($s)" >&2
  fi
  "$ADB" -s "$s" wait-for-device
  until [ "$("$ADB" -s "$s" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 2; done
  echo "  ✓ $avd ready ($s)" >&2
  echo "$s"
}

run_tier() {
  local avd serial
  avd="$(avd_for "$1")"; [ -z "$avd" ] && { echo "Unknown tier: $1"; exit 1; }
  serial="$(boot "$avd")"
  echo "▶ flutter run on '$1' tier ($avd / $serial)"
  flutter run -d "$serial"
}

case "${1:-}" in
  low|mid|flagship) run_tier "$1" ;;
  all)
    for t in low mid flagship; do boot "$(avd_for "$t")" >/dev/null; done
    echo; echo "All tiers booted:"
    for t in low mid flagship; do a="$(avd_for "$t")"; echo "  $t -> $a ($(serial_of "$a"))"; done
    echo "Run the app on one with:  flutter run -d <serial>"
    ;;
  *) echo "Usage: $0 {low|mid|flagship|all}"; exit 1 ;;
esac
