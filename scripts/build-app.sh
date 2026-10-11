#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_dir="$project_root/dist/MenuBarPet.app"

cd "$project_root"
"$project_root/scripts/build-core.sh"
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)
mkdir -p "$app_dir/Contents/MacOS"
cp "$bin_dir/MenuBarPet" "$app_dir/Contents/MacOS/MenuBarPet"
cp "$project_root/Packaging/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"

print "Created: $app_dir"
