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
and Yamagi GLES3 renderer compile and link into a reproducible WebAssembly
bundle. The generated artifacts are:

- `build-web/release/index.html`
- `build-web/release/quake2.js`
- `build-web/release/quake2.wasm`

The static launcher, private owner-data path, HTTP code delivery, JavaScript,
and WebAssembly structure have been verified. Chrome loaded the rebuilt
launcher and showed the expected local-folder gate without a browser error.
The automation extension was not permitted to attach local files, so the
owner-data launch remains a short manual smoke rather than a playability claim.
Engine initialization, the title/menu, an actual level, input, and audio are
**built but not yet browser-verified**.

### Milestone ledger

| Milestone | State | Evidence |
| --- | --- | --- |
| Substantial native source compiles | Passed | 137 C compilation/link steps complete under Emscripten |
| `.wasm` and launcher produced | Passed | `quake2.js` and validated `quake2.wasm` in `build-web/release` |
| Launcher initializes in Chrome | Passed | real Chrome showed the folder-selection gate and disabled Play state |
| Engine initializes in Chrome | Pending | automated local-file selection was denied; manual owner-data smoke required |
| Retail resources load in engine | Pending | local header/size/hash validation passed; runtime load not observed |
| Authentic title/menu appears | Pending | renderer and data are linked/prepared but not visually observed |
| Single-player level renders | Pending | in-process loopback implementation is present but not exercised in Chrome |
| Keyboard/mouse work | Pending | native SDL2 backend is linked but not manually exercised |
| Sound works | Pending | SDL2 audio is linked but browser audio unlock is not manually exercised |
| Remote multiplayer works | Not implemented | needs a WebSocket-to-UDP transport/proxy |

## Architecture

```text
launcher: name + graphics choices
        |
        | Play (engine JS is deliberately loaded only here)
        v
Emscripten preRun
  |- restore exactly allowlisted pak0/pak1/pak2 from private CacheStorage
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

The launcher asks the owner to select this folder on first use. It requires the
registered retail `pak0.pak` and
the supported 3.20 patch `pak1.pak`/`pak2.pak`. It validates their exact names,
sizes, `PACK` headers, and pinned SHA-256 values, then stores the validated
`File` bodies in browser-private CacheStorage. The files are never uploaded,
placed under the HTTP document root, copied into the build, or tracked by Git.

The engine bootstrap accepts exactly those three cache keys and pinned
size/SHA metadata. It checks cached length and the `PACK` header before making
the files read-only in `/data`. CacheStorage avoids another folder selection
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
milestone and must remain owner-supplied if added later.

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
python3 -m http.server 8082 --directory build-web/release
```

Open this exact local URL in Chrome:

```text
http://127.0.0.1:8082/
```

Do not open `index.html` directly with a `file:` URL. Fetch, CacheStorage,
IndexedDB, the WASM MIME type, and WebGL require an HTTP origin.

## Serialized Chrome smoke procedure

Only one portfolio game should own Chrome at a time.

1. Start the server and open `http://127.0.0.1:8082/` in a fresh tab.
2. On first use, select the owner-installed `baseq2` directory. Confirm the
   launcher validates all three PAKs and says they are ready in private browser
   storage. On later hard refreshes, confirm the ready state is restored without
   selecting the folder again.
3. Confirm no PAK appears in the Network panel, then enter a player name,
   choose Medium/High/Ultra, choose 30/60/120 FPS, and
   decide whether Dynamic quality is enabled.
4. Click **Play**. Expect private-cache-to-MEMFS progress for three owner PAKs
   totaling about 197 MiB.
5. In the on-page console, confirm these stages appear without a fatal error:

   ```text
   [quake2-wasm] Restoring browser-local settings and saves…
   [quake2-wasm] Restoring owner-provided Quake II data from browser-private storage…
   [quake2-wasm] Starting Yamagi Quake II…
   [quake2-wasm] browser filesystem ready; starting Yamagi Quake II
   ==== Yamagi Quake II Initialized ====
   ```

6. Confirm the authentic Quake II attract/title/menu renders. Press Escape if
   an attract demo starts, then choose **Game -> New Game -> Easy** and verify a
   level renders.
7. Click the canvas, verify pointer lock and mouse look, then test WASD, mouse
   buttons, Escape, and the console. A click may also be required to resume the
   browser audio context after the long first asset load.
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
./build-web.sh
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
- The web shell disappears after Play; the native Yamagi attract/menu UI is the
  game interface rather than a web reimplementation.
- The graphics ceiling is applied through real engine cvars. Optional adaptive
  quality samples browser frame cadence in three-second windows and only changes
  live-safe effects; MSAA remains the launch-time ceiling.
- SDL owns keyboard/mouse events once the canvas is active. Pointer lock is
  requested by the native SDL backend, and Escape releases it through normal
  browser/engine behavior.
- PAKs are selected locally and remain in private browser storage. There is no
  PAK HTTP route, anonymous upload/PUT endpoint, or public retail-data service.

## Residual blockers and next work

1. Run the serialized Chrome smoke above and fix only initialization blockers;
   do not start a renderer-polish loop in this milestone.
2. Implement an explicit WebSocket client transport and server-side UDP proxy
   before claiming remote multiplayer. Server wake/keep-alive, human counts,
   an eight-player default, and bot-yield policy belong with that server work,
   not in the current single-player loopback shim.
3. Confirm SDL pointer-lock transitions and audio resume after the first long
   asset load.
4. Replace the full MEMFS PAK materialization with a seekable, range-backed or
   chunked read-only filesystem before production scale; preserve exact
   allowlisting and browser-local cache semantics.
5. Add owner-supplied standalone cinematics and OGG soundtrack through a second
   exact manifest only after the core level smoke passes.
6. Add expansion game modules/data as separately owner-provided manifests if
   The Reckoning or Ground Zero enters scope.

No Docker image, public deployment, remote multiplayer server, bots, aimbot, or
retail-data redistribution is claimed by this milestone.
