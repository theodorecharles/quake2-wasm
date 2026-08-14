# quake2-wasm

Quake II running locally in a browser from the native Yamagi Quake II source,
compiled to WebAssembly with Emscripten. The project supplies a responsive web
launcher, browser-private game-data caching, WebGL 2 rendering, SDL audio,
modern controls, graphics profiles, and the original in-game UI.

The retail game files are not included. On first launch, select the `baseq2`
folder from a legally owned Quake II installation. The launcher verifies the
three supported PAKs locally and caches them in this browser; it does not upload
them. Hard refreshes and later sessions reuse that private cache.

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
python3 -m http.server 8082 --directory build-web/release
```

Open `http://127.0.0.1:8082/`, choose the owner `baseq2` folder, and click
**Play Quake II**. The Steam installation normally stores it under
`steamapps/common/Quake 2/baseq2`.

The current WebAssembly build supports the original single-player game through
an in-process server and loopback transport. Remote multiplayer still requires
a browser WebSocket transport and compatible dedicated-server proxy.

## Data and privacy

Only exact known `pak0.pak`, `pak1.pak`, and `pak2.pak` files are accepted. The
launcher checks filename, size, `PACK` header, and SHA-256 before Play is
enabled. Validated files live in browser-private IndexedDB and are mounted
read-only for the engine. No anonymous upload route or public retail-data route
exists.

## Project layout

- `web/`: launcher and owner-data bootstrap
- `src/backends/web/`: browser platform boundary
- `scripts/test-web.sh`: reproducible build and static checks
- `RUNBOOK.md`: architecture, exact test evidence, and remaining work
- `build-web/release/`: generated browser bundle (ignored)

This downstream browser work is based on Yamagi Quake II and id Software's GPL
Quake II source. See `LICENSE` and the existing source headers for licensing and
attribution. Do not submit the browser-port patches upstream.
