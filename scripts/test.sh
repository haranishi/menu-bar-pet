#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
"$project_root/scripts/build-core.sh" --test
swift run -c release --disable-sandbox MenuBarPetTests
swift run -c release --disable-sandbox MenuBarPet --self-test
swift run -c release --disable-sandbox MenuBarPet --render-self-test
