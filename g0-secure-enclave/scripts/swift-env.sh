# Source from zsh scripts after assigning project_dir. All caches stay in the project.
mkdir -p "$project_dir/.build/module-cache" "$project_dir/.build/manifest-support"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/module-cache"
g0_swift_args=(--disable-sandbox --cache-path "$project_dir/.build/cache" --config-path "$project_dir/.build/config" --security-path "$project_dir/.build/security")

# Some CLT installations retain a Swift 5.10 private PackageDescription interface
# beside a Swift 6 library. Compile the current PUBLIC interface locally instead
# of changing anything in /Library/Developer or disabling security checks.
toolchain_dir="$(xcode-select -p)"
manifest_dir="$toolchain_dir/usr/lib/swift/pm/ManifestAPI"
arch_name="$(uname -m)"
public_interface="$manifest_dir/PackageDescription.swiftmodule/$arch_name-apple-macos.swiftinterface"
private_interface="$manifest_dir/PackageDescription.swiftmodule/$arch_name-apple-macos.private.swiftinterface"
if [[ -f "$public_interface" && -f "$private_interface" ]]; then
  public_version="$(sed -n '2p' "$public_interface")"
  private_version="$(sed -n '2p' "$private_interface")"
  if [[ "$public_version" != "$private_version" ]]; then
    local_module="$project_dir/.build/manifest-support/PackageDescription.swiftmodule"
    if [[ ! -f "$local_module" || "$public_interface" -nt "$local_module" ]]; then
      xcrun swiftc -frontend -compile-module-from-interface "$public_interface" \
        -o "$local_module" -module-name PackageDescription \
        -sdk "$(xcrun --show-sdk-path)" -module-cache-path "$project_dir/.build/module-cache" \
        -target "$arch_name-apple-macosx14.0"
    fi
    g0_swift_args+=(-Xmanifest -Xfrontend -Xmanifest "-swift-module-file=PackageDescription=$local_module")
  fi
fi
