# quake2-wasm

Quake II running locally in a browser from the native Yamagi Quake II source,
compiled to WebAssembly with Emscripten. The project supplies a responsive web
launcher, browser-private game-data caching, WebGL 2 rendering, SDL audio,
modern controls, graphics profiles, and the original in-game UI.

The retail game files are not included. A deployment stores the three supported
PAKs in its persistent `/data` volume. If they are absent, the first-run screen
lets the administrator install a legally owned `baseq2` folder into that
container. Server validation happens before the files persist; each browser
then downloads and privately caches them once for fast later loads.

## Controls

- W/A/S/D: move
- Mouse: look
- Left mouse: fire
- Right mouse or Space: jump
- E: use
- Shift: run
- Escape: menu / release input

Click the game once to enable browser audio and capture the pointer. Quake II's
legacy A/Z pitch bindings are deliberately cleared.

## Build

Install CMake, Ninja, Node.js, and the Emscripten SDK, then run:

```bash
EMSDK_DIR=/path/to/emsdk ./scripts/test-web.sh
```

This builds and validates `build-web/release`. It never packages retail data.

## Run locally

```bash
WASM_GAME_SITE_ROOT="$PWD/build-web/release" \
WASM_GAME_SHELL_ROOT="$PWD/../wasm-game-framework/dist" \
WASM_GAME_DATA_ROOT="$PWD/runtime" \
WASM_GAME_HTTP_PORT=8082 \
node ../wasm-game-framework/server/static-server.js
```

Open `http://127.0.0.1:8082/`. With an empty `runtime`, install the owner
`baseq2` folder once, then click **Play Quake II**. The Steam installation
normally stores it under `steamapps/common/Quake 2/baseq2`. Later visitors do
not see setup controls.

The current WebAssembly build supports the original single-player game through
an in-process server and loopback transport. Remote multiplayer still requires
a browser WebSocket transport and compatible dedicated-server proxy.

## Data and privacy

Only exact known `pak0.pak`, `pak1.pak`, and `pak2.pak` files are accepted. The
framework server and launcher check filename, size, `PACK` header, and SHA-256
before Play is enabled. Validated files live in the persistent container volume
and browser-private IndexedDB, then mount read-only inside the engine. Raw
`/data` is never served; only exact allowlisted keys are downloadable. Set
`WASM_SETUP_TOKEN` to protect first-run provisioning on a public deployment.

## Project layout

- `web/`: launcher and owner-data bootstrap
- `src/backends/web/`: browser platform boundary
- `scripts/test-web.sh`: reproducible build and static checks
- `RUNBOOK.md`: architecture, exact test evidence, and remaining work
- `build-web/release/`: generated browser bundle (ignored)

This downstream browser work is based on Yamagi Quake II and id Software's GPL
Quake II source. See `LICENSE` and the existing source headers for licensing and
attribution. Do not submit the browser-port patches upstream.
