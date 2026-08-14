# Reproducible browser and dedicated-server builds

The default browser bundle contains engine code and open configuration only. It
never contains Quake II retail PAKs. Emscripten 6.0.6 is pinned in
`scripts/emscripten-version.txt`.

```sh
scripts/build-web.sh
scripts/build-server.sh
```

The web build produces GLES3 and software renderer side modules plus
`release/bundle-manifest.json`. GL1 remains available when a PIC-enabled GL4ES
checkout is supplied explicitly:

```sh
WITH_GL1=yes GL4ES_PATH=/absolute/path/to/gl4es_pic scripts/build-web.sh
```

The native build produces `release/q2ded`, `release/baseq2/game.so`, and
`release/server-manifest.json`. Both manifests record stable artifact ordering,
sizes, and SHA-256 values. `SOURCE_DATE_EPOCH` defaults to the current commit
timestamp and may be supplied explicitly.

## Owner-provided retail data

`scripts/setup-data.sh` discovers Steam app 2320 or accepts `QUAKE2_PATH`. It
validates `baseq2/pak0.pak`, links available PAKs into ignored `data/baseq2`, and
writes an ignored checksummed asset manifest. It never downloads or modifies
retail data.

For a local title/menu test only, retail data can be preloaded into the ignored
bundle:

```sh
scripts/setup-data.sh
WITH_LOCAL_RETAIL_DATA=1 scripts/build-web.sh
scripts/serve-local.py --port 8082
```

That mode marks `containsRetailData` in the bundle manifest and prints a warning.
Never publish, commit, release, or copy its `release/index.data` into a Docker
layer. The normal build instead reaches a diagnostic console and identifies the
missing `/baseq2/pak0.pak` path clearly.

## First WebSocket boundary

The WASM POSIX datagram backend now points to same-origin `/ws` with Emscripten's
`binary` subprotocol. `scripts/serve-local.py` provides the matching loopback
test boundary: one fixed UDP socket per WebSocket session to `q2ded`, a 1400-byte
packet cap, 64 KiB input/output caps, an idle timeout, strict origin and
subprotocol checks, and connection-summary logging without per-packet spam.

This is a development bridge, not the operational wake/sleep supervisor. A
production deployment must route `/ws` through its TLS reverse proxy, restrict
the configured UDP target, and add the portfolio lifecycle controls before the
multiplayer milestone can pass.
