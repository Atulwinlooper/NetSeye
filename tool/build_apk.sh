#!/bin/zsh
# Build release APKs for the family.
#   ./tool/build_apk.sh        -> NetSeye.apk     (phones: arm64, smaller)
#   ./tool/build_apk.sh tv     -> NetSeye-TV.apk  (32-bit TVs & older devices, e.g. OnePlus Y)
#   (64-bit TVs can install NetSeye.apk; it appears in the TV launcher too.)
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f secrets.json ]] || { echo "Missing secrets.json (copy secrets.example.json)"; exit 1; }
common=(--release --dart-define-from-file=secrets.json --obfuscate --split-debug-info=build/symbols)
if [[ "${1:-}" == "tv" ]]; then
  # 32-bit only: most TVs are armeabi-v7a and have little free storage.
  # Skia instead of Impeller: TV GPUs like the Mali-470 only do OpenGL ES 2.0,
  # where Impeller's fallback renders the UI at ~7 fps.
  flutter build apk "${common[@]}" --split-per-abi --target-platform android-arm \
    --android-project-arg=impeller=false
  cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk NetSeye-TV.apk
  echo "Built $(pwd)/NetSeye-TV.apk"
else
  flutter build apk "${common[@]}" --split-per-abi --target-platform android-arm64
  cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk NetSeye.apk
  echo "Built $(pwd)/NetSeye.apk"
fi
