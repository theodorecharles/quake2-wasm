# quake2-wasm browser-port runbook

## Scope and downstream policy

This repository is a downstream browser port based directly on native Yamagi
Quake II commit `69599f5a7b3c`. The browser integration in this tree was written
against that native source; no retired or third-party Quake II WebAssembly port
was inspected, copied, or used.

Do not submit this work upstream, open upstream issues about it, or push to the
upstream repository. Development belongs on downstream branches in this fork.
The `upstream` remote is fetch-only and its push URL is intentionally
`DISABLED`.

Retail Quake II data is not source code and must never be committed. The build
and asset output directories are ignored by Git.

## Current status — 2026-08-14

The native client, base game module, in-process server, SDL2 input/audio path,
and OpenGL ES 3 renderer compile and link into a reproducible WebAssembly
bundle. The downstream-generated artifacts are:

- `build-web/release/quake2.js`
- `build-web/release/quake2.wasm`
- `build-web/release/wasm-game.json`
- `build-web/release/game-adapter.js`

The canonical document, launcher, loading surface, and runtime canvas are owned
by wasm-game-framework 0.5.3 and served as `/` by its container server.

The shared framework's Docker server validates the persistent `/data` volume
against `wasm-game-data.json`. If data is missing, only the one-time setup UI
is shown; after successful provisioning it is hidden. Each browser downloads
those exact server-held PAKs once and restores them from private IndexedDB on
later visits. Raw `/data`, `/local-data`, arbitrary names, and uploads after a
complete setup are unavailable.
Chrome then started the native engine, loaded `base2` through the in-process
server, and rendered live single-player combat with the authentic HUD. Native
telemetry reported the complete WASD/aspect contract (`255/255`) after startup config,
and SDL audio produced nonzero samples after the browser gesture. The first load
spends several seconds on the attract/demo transition and map data; the
temporary black canvas during that interval is expected. Physical pointer lock,
saves, and remote multiplayer still need their dedicated checks.

### Milestone ledger

| Milestone | State | Evidence |
| --- | --- | --- |
| Substantial native source compiles | Passed | 137 C compilation/link steps complete under Emscripten |
| `.wasm` and launcher produced | Passed | `quake2.js` and validated `quake2.wasm` in `build-web/release` |
| Launcher initializes in Chrome | Passed | real Chrome saw ready container data, restored all three PAKs from IndexedDB, hid setup, and enabled Play |
| Engine initializes in Chrome | Passed | browser log reached `==== Quake II Initialized ====` |
| Retail resources load in engine | Passed | runtime loaded `base2` models, images, clients, and sky from owner PAKs |
| Authentic title/menu appears | Partial | attract sequence advances correctly; menu navigation not checked in this basic pass |
| Single-player level renders | Passed | Chromium captured live `base2` combat with HUD and enemies |
| Keyboard/mouse work | Passed with gesture caveat | telemetry is `255/255`: WASD, Space, E, mouse fire/look, sensitivity 4, A/Z legacy pitch removed, Hor+ widescreen enabled; physical pointer lock still needs a user click |
| Sound works | Passed | SDL callback telemetry produced nonzero samples after canvas interaction |
| Remote multiplayer works | Not implemented | needs a WebSocket-to-UDP transport/proxy |

## Architecture

```text
framework launcher: name + graphics choices + one-time container setup
        |
        | server /data -> exact allowlist -> browser IndexedDB (once)
        | Play (engine JS is deliberately loaded only here)
        v
Emscripten preRun
  |- restore exactly allowlisted pak0/pak1/pak2 from private IndexedDB
  |- stream them into read-only /data/baseq2 without an HTTP request
  `- mount /persist as browser-local IDBFS
        |
        v
single WASM program
  |- native Yamagi client
  |- statically linked baseq2 game API
  |- in-process server + loopback transport (single player)
  |- SDL2 keyboard, mouse and audio
  `- native Yamagi GLES3 renderer -> WebGL 2
```

Yamagi normally loads the game and renderer from dynamic libraries. Browsers do
not provide that native `dlopen` model, so CMake builds the game and GLES3
renderer as separate object modules and links them into the one WASM program.
A small browser system backend resolves their original APIs statically. Private
symbols that only collide after removing the shared-library boundaries are
namespaced at compile time.

The traditional blocking main loop is replaced only for Emscripten with
`emscripten_set_main_loop()`. Large timing jumps from backgrounded tabs are
clamped before they reach physics. Native targets retain their original loop.

Remote networking is intentionally not faked. The web backend implements only
Quake II's normal in-process loopback packet queues, which are required by
single player. Multiplayer UI may be visible in the authentic game menu, but a
remote connection cannot work until a WebSocket bridge is implemented.

## Owner data and browser persistence

The owner data found on this workstation is:

```text
/home/ted/.steam/debian-installation/steamapps/common/Quake 2/baseq2
```

The container requires registered retail `pak0.pak` and the supported 3.20
patch `pak1.pak`/`pak2.pak`. It validates exact names, sizes, `PACK` headers,
and SHA-256 values. An administrator may place them in the persistent `/data`
volume or use the launcher's first-run upload. That upload is same-origin to
the administrator's own container and is atomically accepted only after
server-side validation. It is not a central upload or redistribution service.

Once the volume is ready, the setup controls disappear. The framework then
checks browser-private IndexedDB first and requests `/game-data/files/<key>`
only for a true cache miss. Hard refreshes therefore do not transfer the PAKs
again. PAKs are never placed under the HTTP document root, copied into the
image/build, or tracked by Git.

The engine bootstrap accepts exactly those three cache keys and pinned
size/SHA metadata. It checks cached length and the `PACK` header before making
the files read-only in `/data`. The shared framework cache avoids another folder selection
after a hard refresh. It does not eliminate the current first-milestone
MEMFS copy: roughly 197 MiB of PAK data is materialized again in WASM memory on
each engine launch.

`scripts/prepare-web-assets.sh` is an optional command-line validator for
development. It receives an explicit owner directory and writes only an ignored
manifest under `runtime/`; it never creates web-root symlinks or copies PAKs.

Yamagi's home directory is `/persist`, mounted with IDBFS. Configuration and
saves are restored before engine initialization and flushed every ten seconds.
Retail PAKs and user-writable state never share a mount.

The standalone `baseq2/video/*.cin` cinematics and soundtrack files are not in
the current manifest. They are optional for the first title/menu/level smoke
milestone and must remain separately supplied if added later.

## Build

Prerequisites are CMake 3.31+, Ninja, Bash, Node.js for syntax checks, and an
active Emscripten SDK. If `emcc` is not already on `PATH`, set `EMSDK_DIR` (or
`EMSDK`) to the SDK checkout.

```bash
cd /home/ted/Development/wasm/quake2-wasm
./build-web.sh
```

The script configures an Emscripten Release build with Ninja and builds the
`quake2` browser target. It does not package retail data.

## Validate owner assets from the command line (optional)

For the Steam installation detected on this workstation:

```bash
./scripts/prepare-web-assets.sh "/home/ted/.steam/debian-installation/steamapps/common/Quake 2/baseq2"
```

To explicitly select a different owner-controlled `baseq2` directory:

```bash
./scripts/prepare-web-assets.sh "/absolute/path/to/Quake 2/baseq2"
```

The source must contain the supported `pak0.pak`, `pak1.pak`, and `pak2.pak`.
The generated private manifest lands in `runtime/manifest.json` and remains
ignored. The normal browser flow does not require this helper.

## Run

```bash
EMSDK_DIR=/home/ted/emsdk ./scripts/build-image.sh quake2-wasm:dev
docker run --rm -p 127.0.0.1:8082:8088 -v quake2-data:/data quake2-wasm:dev
```

Open this exact local URL in Chrome:

```text
http://127.0.0.1:8082/
```

The downstream intentionally has no `index.html`; the framework server owns
the document. Do not use a plain static or `file:` URL because provisioning,
IndexedDB, the WASM MIME type, and WebGL require the framework HTTP origin.

## Serialized Chrome smoke procedure

Only one portfolio game should own Chrome at a time.

1. Start the server and open `http://127.0.0.1:8082/` in a fresh tab.
2. With an empty `/data` volume, select the owner-installed `baseq2` directory
   once. Confirm the container validates all three PAKs and the setup controls
   disappear. If `/data` is already provisioned, confirm no setup controls are
   rendered.
3. On the first visit confirm only the three exact `/game-data/files/*`
   requests appear. Hard refresh, confirm no PAK request appears because the
   browser cache is used, then enter a player name,
   choose Medium/High/Ultra, choose 30/60/120 FPS, and
   decide whether Dynamic quality is enabled.
4. Click **Play**. Expect private-cache-to-MEMFS progress for three owner PAKs
   totaling about 197 MiB.
5. In the on-page console, confirm these stages appear without a fatal error:

   ```text
   [quake2-wasm] Restoring browser-local settings and saves…
   [quake2-wasm] Preparing Quake II…
   [quake2-wasm] Starting Quake II…
   [quake2-wasm] browser filesystem ready; starting Quake II
   ==== Quake II Initialized ====
   ```

6. Confirm the authentic Quake II attract/title/menu renders. Press Escape if
   an attract demo starts, then choose **Game -> New Game -> Easy** and verify a
   level renders.
7. Click the canvas, verify pointer lock and mouse look, then test WASD, mouse
   buttons, Escape, and the console. The defaults are W/A/S/D movement, Space
   jump, E use, mouse fire/look, sensitivity 4, and no A/Z pitch bindings. A
   click may also be required to resume the browser audio context after the
   long first asset load.
8. Change one setting or create a save, reload, click Play again, and verify the
   setting/save persists from IDBFS.
9. With Dynamic quality enabled, inspect `window.__quake2Quality` after at least
   two three-second sampling windows. The controller can reduce particles,
   dynamic lights, shadows, and anisotropic filtering without restarting the
   renderer, but never raises quality above the selected ceiling.
10. Record the final visible state, console errors, and a screenshot; stop this
    server before moving Chrome to another portfolio game.

## Verified tests

The following passed on 2026-08-14:

```bash
./scripts/test-web.sh
./scripts/prepare-web-assets.sh "/home/ted/.steam/debian-installation/steamapps/common/Quake 2/baseq2"
bash -n build-web.sh scripts/prepare-web-assets.sh
node --check web/pre.js
wasm-validate build-web/release/quake2.wasm
git diff --check
```

While the local server was running, HTTP checks passed for the launcher and
`application/wasm` bundle. The document root contains no PAK, and the optional
validator rejects an empty owner-data directory.

## Browser-facing behavior

- Player identity is collected and saved before any engine code is loaded.
- The web shell disappears after Play; the native Quake II attract/menu UI is the
  game interface rather than a web reimplementation.
- The graphics ceiling is applied through real engine cvars. Optional adaptive
  quality samples browser frame cadence in three-second windows and only changes
  live-safe effects; MSAA remains the launch-time ceiling.
- SDL owns keyboard/mouse events once the canvas is active. Pointer lock is
  requested by the native SDL backend, and Escape releases it through normal
  browser/engine behavior.
- PAKs persist in the container volume and browser-private cache. Only exact
  allowlisted keys are downloadable; first-run uploads close after setup, and
  a deployment may require `WASM_SETUP_TOKEN`.
- `dynamic` display mode synchronizes CSS canvas, native render buffer, view
  rectangle, and Hor+ FOV. While native `vid_restart` catches up, the framework
  temporarily contains the last valid aspect rather than stretching it.
- Native state polling reports menu/gameplay/paused to the framework. Capture
  is allowed only in gameplay and leaving capture opens the native menu.

## Residual blockers and next work

1. Finish the physical pointer-lock and save-persistence portions of the
   serialized Chrome smoke; browser automation cannot grant pointer lock.
2. Implement an explicit WebSocket client transport and server-side UDP proxy
   before claiming remote multiplayer. Server wake/keep-alive, human counts,
   an eight-player default, and bot-yield policy belong with that server work,
   not in the current single-player loopback shim.
3. Confirm the physical SDL pointer-lock transition after the first long asset
   load; automated Chrome already confirmed nonzero SDL audio output.
4. Replace the full MEMFS PAK materialization with a seekable, range-backed or
   chunked read-only filesystem before production scale; preserve exact
   allowlisting and browser-local cache semantics.
5. Add standalone cinematics and OGG soundtrack through a second
   exact manifest only after the core level smoke passes.
6. Add expansion game modules/data as separate manifests if
   The Reckoning or Ground Zero enters scope.

No Docker image, public deployment, remote multiplayer server, bots, aimbot, or
retail-data redistribution is claimed by this milestone.
