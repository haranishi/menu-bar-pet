#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_dir="$project_root/dist/MenuBarPet.app"

cd "$project_root"
swift build -c release
mkdir -p "$app_dir/Contents/MacOS"
cp "$project_root/.build/release/MenuBarPet" "$app_dir/Contents/MacOS/MenuBarPet"
cp "$project_root/Packaging/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"

print "Created: $app_dir"
