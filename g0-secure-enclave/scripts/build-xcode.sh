#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${G0_DEVELOPMENT_TEAM:-}" ]]; then
  echo 'G0_DEVELOPMENT_TEAMに、Xcodeで確認した開発用Team IDを指定してください。'
  echo '画面で設定する場合は xcode/ProtectionG0.xcodeproj を開き、Signing & CapabilitiesでPersonal Teamを選んで実行できます。'
  exit 2
fi
xcodebuild -project "$project_dir/xcode/ProtectionG0.xcodeproj" \
  -scheme ProtectionG0 -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$project_dir/build/xcode-derived" \
  -allowProvisioningUpdates "DEVELOPMENT_TEAM=$G0_DEVELOPMENT_TEAM" ONLY_ACTIVE_ARCH=YES build
app_dir="$project_dir/build/xcode-derived/Build/Products/Debug/ProtectionG0.app"
codesign --verify --deep --strict "$app_dir"
echo "開発用署名済みアプリ: $app_dir"
echo 'Personal Teamのプロファイルには有効期限があります。ビルド成功とG0の実機試験合格は別に記録してください。'
