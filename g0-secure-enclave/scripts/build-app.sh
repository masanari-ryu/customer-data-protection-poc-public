#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build
source "$project_dir/scripts/swift-env.sh"
swift build "${g0_swift_args[@]}" -c release --product ProtectionG0
bin_dir="$(swift build "${g0_swift_args[@]}" -c release --show-bin-path)"
app_dir="$project_dir/build/ProtectionG0.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$bin_dir/ProtectionG0" "$app_dir/Contents/MacOS/ProtectionG0"
build_id="$(shasum -a 256 "$bin_dir/ProtectionG0" | cut -c 1-12)"
cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>jp.customer-protection.poc.g0</string>
<key>CFBundleName</key><string>ProtectionG0</string>
<key>CFBundleDisplayName</key><string>顧客情報保護 G0</string>
<key>CFBundleExecutable</key><string>ProtectionG0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>$build_id</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Ad-hoc signing permits local launch; it is NOT a Developer ID distribution.
# Supply an existing identity only after confirming its entitlement/provisioning needs.
signing_identity="${G0_SIGNING_IDENTITY:--}"
if [[ -n "${G0_PROVISIONING_PROFILE:-}" ]]; then
  cp "$G0_PROVISIONING_PROFILE" "$app_dir/Contents/embedded.provisionprofile"
elif [[ -f "$app_dir/Contents/embedded.provisionprofile" ]]; then
  rm "$app_dir/Contents/embedded.provisionprofile"
fi
if [[ -n "${G0_ENTITLEMENTS_FILE:-}" ]]; then
  codesign --force --sign "$signing_identity" --entitlements "$G0_ENTITLEMENTS_FILE" "$app_dir"
else
  codesign --force --sign "$signing_identity" "$app_dir"
fi
codesign --verify --strict "$app_dir"
echo "G0アプリ: $app_dir"
echo "ビルド: $build_id"
echo '実機鍵・本人確認・ロック・再起動の試験は未実施です。'
