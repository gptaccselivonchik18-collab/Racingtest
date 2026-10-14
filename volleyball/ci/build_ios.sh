#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/ios build/logs
xcodebuild -version | tee build/logs/xcode-version.log
# Some Godot versions validate the Team field even for export_project_only.
# This is a project placeholder, never a certificate or fabricated signature.
python3 - <<'PY'
from pathlib import Path
p = Path('export_presets.cfg')
p.write_text(p.read_text().replace('application/app_store_team_id=""', 'application/app_store_team_id="0000000000"'))
PY
godot --headless --path . --export-release iOS build/ios/VolleyballSimulator.xcodeproj 2>&1 | tee build/logs/ios-export.log
xcodebuild -project build/ios/VolleyballSimulator.xcodeproj \
  -scheme VolleyballSimulator -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath build/ios/DerivedData \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' build 2>&1 | tee build/logs/xcode-build.log
app=build/ios/DerivedData/Build/Products/Release-iphoneos/VolleyballSimulator.app
test -d "$app"
executable=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Info.plist")
test -x "$app/$executable"
lipo "$app/$executable" -verify_arch arm64
# Remove any toolchain-added ad-hoc signatures, including embedded frameworks.
while IFS= read -r -d '' binary; do
  if file "$binary" | grep -q 'Mach-O'; then
    if codesign -d "$binary" >/dev/null 2>&1; then
      codesign --remove-signature "$binary"
    fi
  fi
done < <(find "$app" -type f -print0)
find "$app" -type d -name _CodeSignature -prune -exec rm -rf {} +
if codesign --verify "$app" >/dev/null 2>&1; then
  echo 'Unexpected signature on unsigned build' >&2
  exit 1
fi
mkdir -p build/ios/package/Payload
ditto "$app" build/ios/package/Payload/VolleyballSimulator.app
(cd build/ios/package && zip -qry ../../../VolleyballSimulator-iOS-Unsigned.ipa Payload)
mv VolleyballSimulator-iOS-Unsigned.ipa build/
python3 ci/verify_ipa.py build/VolleyballSimulator-iOS-Unsigned.ipa | tee build/logs/ipa-verification.log
