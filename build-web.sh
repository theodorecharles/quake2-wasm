#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
emsdk_dir="${EMSDK:-/home/ted/emsdk}"

if [[ ! -f "$emsdk_dir/emsdk_env.sh" ]]; then
  echo "Emscripten SDK not found at $emsdk_dir" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$emsdk_dir/emsdk_env.sh" >/dev/null

emcmake cmake -S "$repo_dir" -B "$repo_dir/build-web" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$repo_dir/build-web" --target quake2

echo "Web bundle: $repo_dir/build-web/release"
