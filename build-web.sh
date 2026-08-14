#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v emcc >/dev/null 2>&1; then
  emsdk_dir="${EMSDK_DIR:-${EMSDK:-}}"
  if [[ -z "$emsdk_dir" || ! -f "$emsdk_dir/emsdk_env.sh" ]]; then
    echo "Activate Emscripten first, or set EMSDK_DIR to an emsdk checkout." >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  source "$emsdk_dir/emsdk_env.sh" >/dev/null
fi

# Older checkpoints placed owner PAK symlinks under the HTTP document root.
# Remove only those known generated paths so a rebuild can never serve them.
for retail_name in pak0.pak pak1.pak pak2.pak; do
  rm -f "$repo_dir/build-web/release/assets/baseq2/$retail_name"
done
rm -f "$repo_dir/build-web/release/assets/manifest.json"
rmdir "$repo_dir/build-web/release/assets/baseq2" "$repo_dir/build-web/release/assets" 2>/dev/null || true
rm -f "$repo_dir/build-web/release/index.html"

emcmake cmake -S "$repo_dir" -B "$repo_dir/build-web" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$repo_dir/build-web" --target quake2

framework_dir="${WASM_FRAMEWORK_DIR:-$repo_dir/../wasm-game-framework}"
if [[ ! -x "$framework_dir/scripts/install-browser-package.sh" ]]; then
  echo "WASM framework browser package not found at $framework_dir" >&2
  exit 1
fi
"$framework_dir/scripts/install-browser-package.sh" "$repo_dir/build-web/release/shared-shell" copy
if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick is required to build authentic Quake II PWA icons." >&2
  exit 1
fi
magick "$repo_dir/stuff/icon/Quake2.png" -resize 192x192 "$repo_dir/build-web/release/quake2-192.png"
cp "$repo_dir/stuff/icon/Quake2.png" "$repo_dir/build-web/release/quake2-512.png"

echo "Web bundle: $repo_dir/build-web/release"
