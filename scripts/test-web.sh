#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="$repo_dir/build-web/release"
framework_dir="${WASM_FRAMEWORK_DIR:-$repo_dir/../wasm-game-framework}"

"$repo_dir/build-web.sh"

for required in quake2.js quake2.wasm quake2.ico game-adapter.js wasm-game.json wasm-game-data.json \
  shared-shell/wolfwasm-shell.js shared-shell/wolfwasm-shell.css \
  shared-shell/wolfwasm-bootstrap.js shared-shell/wasm-game-framework.json; do
  [[ -f "$release_dir/$required" ]] || { echo "Missing Quake II web artifact: $required" >&2; exit 1; }
done

if [[ -e "$release_dir/index.html" ]]; then
  echo 'Quake II downstream still owns obsolete index.html.' >&2
  exit 1
fi

node --check "$release_dir/quake2.js"
node --check "$release_dir/game-adapter.js"
node --check "$repo_dir/web/pre.js"
node --check "$release_dir/shared-shell/wolfwasm-bootstrap.js"
wasm-validate "$release_dir/quake2.wasm"
cmp "$repo_dir/web/game-adapter.js" "$release_dir/game-adapter.js"
cmp "$repo_dir/web/wasm-game.json" "$release_dir/wasm-game.json"
cmp "$framework_dir/dist/wolfwasm-shell.js" "$release_dir/shared-shell/wolfwasm-shell.js"
cmp "$framework_dir/dist/wolfwasm-shell.css" "$release_dir/shared-shell/wolfwasm-shell.css"
cmp "$framework_dir/dist/wolfwasm-bootstrap.js" "$release_dir/shared-shell/wolfwasm-bootstrap.js"

for marker in \
  'globalThis.WasmGameAdapter' \
  'ctx.framework.createOwnerDataSet' \
  'ctx.dataClient.load' \
  'globalThis.createQuake2Module' \
  'quake2OwnerData: preparedData' \
  'quake2ControlsValid' \
  '_Q2Web_SetInputCaptured' \
  '_Q2Web_EnsureMenu' \
  '_Q2Web_ResizeViewport'; do
  grep -Fq "$marker" "$release_dir/game-adapter.js" || { echo "Missing shared Quake II adapter marker: $marker" >&2; exit 1; }
done

for marker in \
  'WolfWasmShell.mountOwnerFiles' \
  "root: '/data/baseq2'" \
  "mode: 'memfs'"; do
  grep -Fq "$marker" "$repo_dir/web/pre.js" || { echo "Missing Quake II owner-data mount marker: $marker" >&2; exit 1; }
done

node -e '
const fs=require("fs");
const c=JSON.parse(fs.readFileSync(process.argv[1]));
const m=JSON.parse(fs.readFileSync(process.argv[2]));
const p=JSON.parse(fs.readFileSync(process.argv[3]));
if(c.id!=="quake2"||c.displayMode!=="dynamic"||c.nativeManaged!==true||c.syncBackbuffer!==false)process.exit(1);
if(m.namespace!=="quake2-registered"||m.files.length!==3||m.files.some(f=>!f.sha256||f.magic!=="PACK"))process.exit(1);
if(p.package!=="@wasm-game-framework/browser"||p.version!=="0.5.3"||!p.bootstrapSha256)process.exit(1);
' "$release_dir/wasm-game.json" "$release_dir/wasm-game-data.json" "$release_dir/shared-shell/wasm-game-framework.json"

grep -Fq 'grab = grab && q2web_input_captured' "$repo_dir/src/client/vid/glimp_sdl2.c"
grep -Fq 'Q2Web_ConfigureControls' "$repo_dir/src/backends/web/main.c"
grep -Fq 'Q2Web_RuntimeState' "$repo_dir/src/backends/web/main.c"
grep -Fq 'Q2Web_AudioNonzeroCallbacks' "$repo_dir/src/client/sound/sdl.c"

if strings "$release_dir/quake2.wasm" | grep -F 'Yamagi Quake II' >/dev/null; then
  echo 'Quake II browser binary retains source-port title branding.' >&2
  exit 1
fi
for marker in 'Quake II WebAssembly' 'Quake II OpenGL ES3 Renderer' 'Quake II Initialized'; do
  strings "$release_dir/quake2.wasm" | grep -F "$marker" >/dev/null || { echo "Missing browser-native Quake II title: $marker" >&2; exit 1; }
done

if grep -R -E 'caches\.open|CacheStorage|__quake2_owner_data__' "$repo_dir/web" >/dev/null; then
  echo 'Legacy Quake II CacheStorage implementation is still present.' >&2
  exit 1
fi
if find "$release_dir" -type f \( -iname '*.pak' -o -iname '*.pk3' -o -iname '*.data' \) -print -quit | grep -q .; then
  echo 'Retail-like data was found in the Quake II web release.' >&2
  exit 1
fi
if grep -R -F '/local-data/' "$release_dir/game-adapter.js" >/dev/null; then
  echo 'Legacy direct owner-data serving is still present.' >&2
  exit 1
fi
if grep -R -F '/home/ted/' "$release_dir" "$repo_dir/web" "$repo_dir/build-web.sh" >/dev/null; then
  echo 'A workstation-specific path leaked into the Quake II browser build.' >&2
  exit 1
fi

git -C "$repo_dir" diff --check
echo 'Quake II web build passed framework 0.5.3, input, aspect, branding, audio, and owner-data boundary checks.'
