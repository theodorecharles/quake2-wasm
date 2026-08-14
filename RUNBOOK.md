# quake2-wasm implementation runbook

Read `/home/ted/Development/WASM_PORTS_RUNBOOK.md` first. It defines shared shell, lifecycle, caching, input, graphics, Docker, testing, and coordination behavior. This file is the Quake II-specific implementation contract.

## Objective

Ship the real Quake II single-player campaign and native Quake II multiplayer in a browser. Preserve Yamagi/Qwasm2 engine behavior, authentic menus/HUD/console, the base game module, saves, monsters, cinematics, renderer, audio, deathmatch, cooperative play, and supported mods. HTML remains a thin launcher.

## Current checkpoint

- Downstream repository: `theodorecharles/quake2-wasm`.
- Implementation base: Qwasm2, derived from Yamagi Quake II.
- Work branch: `devel`.
- Qwasm2 already builds a main WASM engine plus side modules for the base game and GLES3/GL1/software renderers.
- Existing output contract: `index.html`, `index.js`, `index.data`, `index.wasm`, `game_baseq2.wasm`, `ref_soft.wasm`, `ref_gl1.wasm`, and `ref_gles3.wasm`.
- Existing browser persistence covers saves/configs; multiplayer WebSockets are explicitly not implemented yet.
- Steam app 2320 was re-checked on 2026-08-13 and is fully installed. The local owner-provided `baseq2/pak0.pak`, `pak1.pak`, and `pak2.pak` paths are present; they remain ignored and outside public bundles. Browser asset mounting and playability still require runtime evidence before those milestones can be claimed.
- Original id source belongs in ignored `references/quake2-source/` and is reference-only.

## Downstream-only rule

Do not submit anything upstream. Do not open or comment on Qwasm2, Yamagi, or id Software pull requests, issues, discussions, or releases. Do not message maintainers. Never push to `upstream`. All generated work stays in `theodorecharles/quake2-wasm`.

## Source authority

Use this order:

1. legal Steam Quake II in actual play after its download completes;
2. `references/quake2-source/` for original behavior;
3. Qwasm2/Yamagi code for maintained implementation and existing WASM behavior;
4. `wolfet-wasm` for browser-platform mechanics only.

Do not discard Qwasm2's working web port to start again from desktop source.

## First compile loop

The upstream reproduction command is:

```bash
cd /home/ted/Development/quake2-wasm
source /home/ted/emsdk/emsdk_env.sh
emmake make GL4ES_PATH=/absolute/path/to/gl4es_pic
```

The historical build expects a PIC-enabled Emscripten GL4ES library for its GL1 side module. The shortest first milestone may build GLES3 and software renderers while temporarily disabling GL1, provided the native build remains intact and the limitation is recorded. WebGL 2/GLES3 is the primary renderer.

Create reproducible scripts instead of relying on an undocumented local GL4ES checkout:

```text
scripts/build-web.sh
scripts/build-server.sh
scripts/setup-data.sh
```

Pin Emscripten, build the native `q2ded` server separately, and emit a machine-readable bundle manifest.

## Game data

After Steam finishes, discover the install through `QUAKE2_PATH` or the Steam library. Normalize data into an ignored `/data/baseq2` runtime directory. Expected retail files normally include `pak0.pak`, with patch files `pak1.pak` and `pak2.pak` when present; validate the actual Steam layout before hardcoding it.

Never download retail PAKs from unofficial sources, commit them, upload them to releases, or bake them into public Docker layers. The public runtime requires an owner-mounted `/data/baseq2` or a browser-local directory picker.

Keep immutable PAK delivery separate from writable `/qwasm2` save/config storage. Do not IDBFS-sync PAK bytes on every save. Hard refresh must reuse checksummed PAK data from IndexedDB/OPFS.

## Menu and game modes

The authentic engine UI must visibly expose:

- Single Player
  - New Game/difficulty
  - Load Game
  - Save Game
- Multiplayer
  - Join Game
  - Deathmatch
  - Cooperative
  - Host/Local Match where useful
- Options
- Credits

Do not build replacement menus in HTML. Patch the Q2 menu code so Single Player and Multiplayer are reliable browser actions. A browser-inappropriate Quit action can return to the launcher or be hidden.

Single Player loads `game_baseq2.wasm` without waking a dedicated server. Multiplayer intent wakes native `q2ded` before connection begins. The landing-page name must become the safe `name` cvar and save/profile identifier.

## Single-player acceptance

- Start a new campaign at each difficulty.
- Render intro/cinematics or document the temporary fallback.
- Complete at least one map transition.
- Verify monsters, items, doors, trains, triggers, particles, dynamic lights, underwater rendering, death/reload, and intermission.
- Save, reload the page, restore from persistent storage, and load the save.
- Keep base-game side-module ABI deterministic across engine rebuilds.

Mission packs are separate future side modules; do not claim support because native DLLs happen to be present.

## Multiplayer implementation

Qwasm2's README states WebSocket multiplayer is absent. This is the largest functional gap.

Preserve Quake II protocol semantics behind:

```text
WASM client -> same-origin /ws -> bounded bridge -> native q2ded UDP
```

First inspect Emscripten's supported WebSocket/socket proxy path and Qwasm2's Unix networking backend. Isolate web networking under `__EMSCRIPTEN__`; do not alter native UDP behavior. The bridge must validate client/session ownership, cap queued packets, time out dead peers, surface disconnect reasons, and avoid per-packet console spam.

Network acceptance requires two browser clients through an HTTPS-capable same-origin proxy: join, chat, move, fire, damage, death, respawn, scoreboard, disconnect/reconnect, map transition, and cooperative entity state.

## Bots

Quake II campaign monsters are not deathmatch bots. The base game has no acceptable bot-fill behavior merely because AI source exists. A worker may evaluate a compatible, legally redistributable Quake II bot game module, but must verify protocol, side-module, dedicated-server, and licensing compatibility first.

If a bot module is selected, compile it as a named server/game module and maintain eight total participants with one transient connection slot. Otherwise ship correct human multiplayer and document bot fill as pending.

## Renderer and dynamic graphics

Start with `ref_gles3.wasm`; keep `ref_soft.wasm` as a diagnostic/fallback. Do not switch WebGL context versions after startup. Select renderer before context creation and treat changes requiring restart as next-launch settings.

Profiles should map to verified Quake II/Yamagi controls for render resolution, texture filtering/anisotropy, dynamic lights, particles, shadows, decals, water effects, model interpolation, post effects, and view distance. Dynamic 30/60/120 FPS follows the portfolio controller.

Visual acceptance includes:

- palette/gamma and lightmaps;
- sky and far plane;
- alpha-tested/translucent surfaces;
- particles, muzzle flashes, explosions, smoke, and water;
- entity and viewmodel interpolation;
- cinematics;
- console/menu/HUD/crosshair alignment at multiple aspect ratios and DPI values.

## Input and UI

Audit `src/backends/wasm/capmouse.c`, `wasm/shell.html`, SDL input, and absolute engine cursor mapping as one system. Avoid duplicate mouse deltas.

Test WASD/arrows, mouse buttons/wheel, Escape menus, console toggle, `/`, Backspace, Enter, Up/Down history, Tab scoreboard, chat, menu text entry, death/respawn, cinematics, and renderer restart/fallback. Browser shortcuts work when not captured.

## Lifecycle and Docker

The public image includes the web bundle, native `q2ded`, same-origin bridge, and no retail assets. Defaults:

```text
HTTP_PORT=8088
GAME_SLOTS=8
KEEP_ALIVE=false
IDLE_TIMEOUT=15m
GAME_MODE=vanilla
```

Use `/data/baseq2` plus writable `/data/custom_maps`. Wake only on Multiplayer intent, randomize the first valid map, and count fully connected humans for idle shutdown. Single-player sessions do not keep `q2ded` alive.

## First worker assignment

1. Re-check whether Steam has completed Quake II.
2. Reproduce the existing GLES3/software WASM build with the installed Emscripten SDK.
3. Add deterministic scripts and record whether GL4ES is still required.
4. Prove the browser artifact loads without retail data and emits a clear missing-data diagnostic.
5. Return an exact title/menu runtime test handoff to Luna; do not use Chrome.
6. Inspect the first networking code boundary and propose the smallest real `/ws` connection slice.
7. Commit and push the `devel` checkpoint.

## Status handoff

Record current milestone, exact passing command, artifacts, Steam asset state, browser test request, networking blocker, and `Upstream contacted: no`.

## Wave 1 implementation evidence

- Native `q2ded` reproduced before scaffold changes with `make -j4 SOURCE_DATE_EPOCH=1726334889 server`.
- Emscripten 6.0.6 reproduced `ref_soft.wasm`, `ref_gles3.wasm`, and `game_baseq2.wasm`; the historical main-module link then failed only because `ref_gl1.wasm` was hardcoded without a local PIC GL4ES archive.
- `scripts/build-web.sh` now makes GLES3/software the deterministic default while preserving opt-in GL1, and emits a machine-readable bundle manifest.
- `scripts/build-server.sh` builds native `q2ded` and `baseq2/game.so` separately and emits a server manifest.
- `scripts/setup-data.sh` validates and links owner-provided local PAK paths into ignored storage, with a local checksum manifest and an actionable missing-data failure.
- The first multiplayer boundary routes the existing Emscripten datagram emulation to same-origin `/ws`; `scripts/serve-local.py` supplies a bounded loopback WebSocket-to-fixed-UDP test bridge. Browser and real `q2ded` multiplayer acceptance remain pending Luna's serial runtime test.
