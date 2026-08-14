#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="$repo_dir/build-web/release"
framework_dir="${WASM_FRAMEWORK_DIR:-$repo_dir/../wasm-game-framework}"

"$repo_dir/build-web.sh"

for required in index.html quake2.js quake2.wasm wasm-game-data.json \
  shared-shell/wolfwasm-shell.js shared-shell/wolfwasm-shell.css \
  shared-shell/wasm-game-framework.json; do
  [[ -f "$release_dir/$required" ]] || { echo "Missing Quake II web artifact: $required" >&2; exit 1; }
done

node --check "$release_dir/quake2.js"
node --check "$repo_dir/web/pre.js"
wasm-validate "$release_dir/quake2.wasm"
cmp "$framework_dir/dist/wolfwasm-shell.js" "$release_dir/shared-shell/wolfwasm-shell.js"
cmp "$framework_dir/dist/wolfwasm-shell.css" "$release_dir/shared-shell/wolfwasm-shell.css"

for marker in \
  'WolfWasmShell.configure' \
  'WolfWasmShell.createDataCache' \
  'WolfWasmShell.createOwnerDataSet' \
  'WolfWasmShell.createContainerDataClient' \
  "displayMode: 'dynamic'" \
  'shell.setEngineState' \
  'quake2OwnerData: preparedData' \
  'quake2ControlsValid' \
  'Q2Web_SetInputCaptured' \
  'Q2Web_EnsureMenu'; do
  grep -Fq "$marker" "$release_dir/index.html" || { echo "Missing shared Quake II marker: $marker" >&2; exit 1; }
done

for marker in \
  'WolfWasmShell.mountOwnerFiles' \
  "root: '/data/baseq2'" \
  "mode: 'memfs'"; do
  grep -Fq "$marker" "$repo_dir/web/pre.js" || { echo "Missing Quake II owner-data mount marker: $marker" >&2; exit 1; }
done

grep -Fq 'grab = grab && q2web_input_captured' "$repo_dir/src/client/vid/glimp_sdl2.c"
grep -Fq 'Q2Web_ConfigureControls' "$repo_dir/src/backends/web/main.c"
grep -Fq 'Q2Web_RuntimeState' "$repo_dir/src/backends/web/main.c"
grep -Fq 'Q2Web_AudioNonzeroCallbacks' "$repo_dir/src/client/sound/sdl.c"

if grep -R -E 'caches\.open|CacheStorage|__quake2_owner_data__' "$repo_dir/web" >/dev/null; then
  echo 'Legacy Quake II CacheStorage implementation is still present.' >&2
  exit 1
fi
if find "$release_dir" -type f \( -iname '*.pak' -o -iname '*.pk3' -o -iname '*.data' \) -print -quit | grep -q .; then
  echo 'Retail-like data was found in the Quake II web release.' >&2
  exit 1
fi
if grep -R -F '/local-data/' "$release_dir/index.html" >/dev/null; then
  echo 'Legacy direct owner-data serving is still present.' >&2
  exit 1
fi
if grep -R -F '/home/ted/' "$release_dir" "$repo_dir/web" "$repo_dir/build-web.sh" >/dev/null; then
  echo 'A workstation-specific path leaked into the Quake II browser build.' >&2
  exit 1
fi

git -C "$repo_dir" diff --check
echo 'Quake II web build passed framework, input, audio, and owner-data boundary checks.'
