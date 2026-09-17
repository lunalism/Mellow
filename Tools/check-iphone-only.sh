#!/bin/zsh
# check-iphone-only.sh — iPhone-only distribution guard (ROADMAP §3.15 Release Gate).
#
# Read-only. Asks Xcode for the EFFECTIVE build settings of the shipping Mellow app target (never
# parses project.pbxproj) and fails unless TARGETED_DEVICE_FAMILY is exactly "1" (iPhone family) in
# BOTH Debug and Release. Optionally validates one already-built product's Info.plist so that a
# release candidate can be checked without rebuilding here.
#
#   Tools/check-iphone-only.sh                       # settings audit (Debug + Release)
#   Tools/check-iphone-only.sh --app /path/Mellow.app  # + require UIDeviceFamily == [1] in that build
#   Tools/check-iphone-only.sh --self-test           # exercises the pass / fail predicates offline
#
# Exit status: 0 = iPhone-only confirmed, 1 = violation, 2 = usage / tooling error.
set -u
set -o pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
project="$repo_root/Mellow.xcodeproj"
target="Mellow"
app_path=""
self_test=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) [[ $# -ge 2 ]] || { echo "error: --app needs a path" >&2; exit 2; }; app_path="$2"; shift 2 ;;
    --self-test) self_test=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

failures=0
pass() { print -- "PASS  $1"; }
fail() { print -- "FAIL  $1" >&2; failures=$((failures + 1)); }

# Predicate 1: an effective TARGETED_DEVICE_FAMILY value is iPhone-only iff it is exactly "1".
check_device_family() {  # $1 = configuration label, $2 = raw value
  if [[ "$2" == "1" ]]; then
    pass "$1: TARGETED_DEVICE_FAMILY = 1 (iPhone only)"
  else
    fail "$1: TARGETED_DEVICE_FAMILY = '${2:-<unset>}' — must be exactly 1 (iPhone only); 2 = iPad, 1,2 = universal"
  fi
}

# Predicate 2: a built product's UIDeviceFamily must be exactly [1].
check_ui_device_family() {  # $1 = label, $2 = plist-extracted family list (one entry per line)
  local families="${2//$'\n'/,}"
  if [[ "$families" == "1" ]]; then
    pass "$1: UIDeviceFamily = [1] (iPhone only)"
  else
    fail "$1: UIDeviceFamily = [${families:-<missing>}] — must be exactly [1]"
  fi
}

if (( self_test )); then
  # Offline exercise of both predicates: the accepted value passes, every other shape fails.
  check_device_family "self-test accepted" "1"
  before=$failures
  check_device_family "self-test iPad" "2" 2>/dev/null
  check_device_family "self-test universal" "1,2" 2>/dev/null
  check_device_family "self-test unset" "" 2>/dev/null
  check_ui_device_family "self-test accepted" "1"
  check_ui_device_family "self-test universal" $'1\n2' 2>/dev/null
  check_ui_device_family "self-test missing" "" 2>/dev/null
  rejected=$((failures - before))
  if (( rejected == 5 )); then
    print -- "PASS  self-test: 5/5 non-iPhone-only shapes rejected"; exit 0
  else
    print -- "FAIL  self-test: expected 5 rejections, got $rejected" >&2; exit 1
  fi
fi

[[ -d "$project" ]] || { echo "error: $project not found" >&2; exit 2; }
command -v xcodebuild >/dev/null || { echo "error: xcodebuild not available" >&2; exit 2; }

for configuration in Debug Release; do
  value="$(xcodebuild -project "$project" -target "$target" -configuration "$configuration" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '$1 ~ /^[[:space:]]*TARGETED_DEVICE_FAMILY$/ { print $2; exit }')"
  if [[ -z "$value" ]]; then
    echo "error: could not read TARGETED_DEVICE_FAMILY for $target ($configuration)" >&2; exit 2
  fi
  check_device_family "$configuration" "$value"
done

if [[ -n "$app_path" ]]; then
  plist="$app_path/Info.plist"
  [[ -f "$plist" ]] || { echo "error: $plist not found" >&2; exit 2; }
  families="$(plutil -extract UIDeviceFamily json -o - "$plist" 2>/dev/null | tr -d '[] \n' | tr ',' '\n')"
  check_ui_device_family "$app_path:t" "$families"
fi

if (( failures )); then
  print -- "iPhone-only guard: $failures violation(s) — Mellow V1 must stay iPhone-only (ROADMAP §3.15)." >&2
  exit 1
fi
print -- "iPhone-only guard: OK"
