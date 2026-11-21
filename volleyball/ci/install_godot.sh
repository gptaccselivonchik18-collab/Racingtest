#!/usr/bin/env bash
set -euo pipefail
version=4.6.3
base="https://github.com/godotengine/godot-builds/releases/download/${version}-stable"
temp="$RUNNER_TEMP/volley-godot"
mkdir -p "$temp"
if [[ "$RUNNER_OS" == macOS ]]; then
  editor="Godot_v${version}-stable_macos.universal.zip"
  templates="$HOME/Library/Application Support/Godot/export_templates/${version}.stable"
else
  editor="Godot_v${version}-stable_linux.x86_64.zip"
  templates="$HOME/.local/share/godot/export_templates/${version}.stable"
fi
curl --fail -L --retry 4 "$base/$editor" -o "$temp/$editor"
curl --fail -L --retry 4 "$base/SHA512-SUMS.txt" -o "$temp/SHA512-SUMS.txt"
(cd "$temp"; grep " $editor$" SHA512-SUMS.txt | shasum -a 512 -c -)
unzip -q "$temp/$editor" -d "$temp/editor"
mkdir -p "$temp/bin"
if [[ "$RUNNER_OS" == macOS ]]; then
  chmod +x "$temp/editor/Godot.app/Contents/MacOS/Godot"
  ln -s "$temp/editor/Godot.app/Contents/MacOS/Godot" "$temp/bin/godot"
else
  chmod +x "$temp/editor/Godot_v${version}-stable_linux.x86_64"
  ln -s "$temp/editor/Godot_v${version}-stable_linux.x86_64" "$temp/bin/godot"
fi
echo "$temp/bin" >> "$GITHUB_PATH"
if [[ "${1:-}" != editor-only ]]; then
  archive="Godot_v${version}-stable_export_templates.tpz"
  curl --fail -L --retry 4 "$base/$archive" -o "$temp/$archive"
  (cd "$temp"; grep " $archive$" SHA512-SUMS.txt | shasum -a 512 -c -)
  mkdir -p "$templates"
  if [[ "$RUNNER_OS" == macOS ]]; then
    unzip -j -q "$temp/$archive" templates/ios.zip -d "$templates"
  else
    unzip -j -q "$temp/$archive" templates/android_debug.apk templates/android_release.apk -d "$templates"
  fi
fi
