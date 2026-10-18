#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
source "$project_dir/scripts/swift-env.sh"
swift run "${g0_swift_args[@]}" g0-self-test
