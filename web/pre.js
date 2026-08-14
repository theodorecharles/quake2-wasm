/* Browser filesystem bootstrap for the native-source Yamagi build. */

Module.preRun = Module.preRun || [];
Module.preRun.push(function quake2PrepareFilesystem() {
  const dependency = "quake2-assets-and-persistence";
  const ownerCacheName = Module.quake2OwnerCacheName || "quake2-owner-data-v1";
  const allowedPaks = new Map([
    ["baseq2/pak0.pak", { size: 183997730, sha256: "1ce99eb11e7e251ccdf690858effba79836dbe5e32a4083ad00a13ecda491679" }],
    ["baseq2/pak1.pak", { size: 12992754, sha256: "678210ecd1b27dde1c645660333a1a7b139d849425793859657f804d379b62ad" }],
    ["baseq2/pak2.pak", { size: 45055, sha256: "cb88d584ef939d08e24433a6cf86274737303fac2bbd94415927a75e6b269dd8" }]
  ]);

  function status(message) {
    if (Module.setStatus) Module.setStatus(message);
    console.info(`[quake2-wasm] ${message}`);
  }

  function ownerCacheKey(entry) {
    return new URL(`/__quake2_owner_data__/${entry.path}?sha256=${entry.sha256}`, location.origin).href;
  }

  async function streamIntoMemfs(entry) {
    const expected = allowedPaks.get(entry.path);
    if (!expected || entry.size !== expected.size || entry.sha256 !== expected.sha256) {
      throw new Error(`Rejected asset manifest entry: ${JSON.stringify(entry)}`);
    }

    status(`Preparing ${entry.path} (${Math.ceil(entry.size / 1048576)} MiB)…`);
    if (!("caches" in globalThis)) {
      throw new Error("This browser does not provide private CacheStorage");
    }
    const cache = await caches.open(ownerCacheName);
    const response = await cache.match(ownerCacheKey(entry));
    if (!response || !response.ok || !response.body) {
      throw new Error(`${entry.path} is not available in browser-private storage; select the game folder again`);
    }

    const contentLengthHeader = response.headers.get("content-length");
    const contentLength = Number(contentLengthHeader);
    if (contentLengthHeader !== null && Number.isFinite(contentLength) && contentLength !== entry.size) {
      throw new Error(`${entry.path}: expected ${entry.size} bytes, server sent ${contentLength}`);
    }

    const destination = `/data/${entry.path}`;
    const stream = FS.open(destination, "w");
    const reader = response.body.getReader();
    let offset = 0;
    const header = new Uint8Array(4);
    let headerBytes = 0;

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (headerBytes < 4) {
          const count = Math.min(4 - headerBytes, value.byteLength);
          header.set(value.subarray(0, count), headerBytes);
          headerBytes += count;
        }
        FS.write(stream, value, 0, value.byteLength, offset);
        offset += value.byteLength;
        status(`Preparing ${entry.path}: ${Math.floor((offset / entry.size) * 100)}%`);
      }
    } finally {
      FS.close(stream);
    }

    if (offset !== entry.size || headerBytes !== 4 ||
        header[0] !== 0x50 || header[1] !== 0x41 ||
        header[2] !== 0x43 || header[3] !== 0x4b) {
      FS.unlink(destination);
      throw new Error(`${entry.path}: invalid PAK header or length (${offset}/${entry.size})`);
    }

    FS.chmod(destination, 0o444);
  }

  addRunDependency(dependency);
  (async function prepare() {
    FS.mkdirTree("/data/baseq2");
    FS.mkdirTree("/persist");
    FS.mount(IDBFS, {}, "/persist");

    status("Restoring browser-local settings and saves…");
    await new Promise((resolve, reject) => FS.syncfs(true, error => error ? reject(error) : resolve()));

    status("Restoring owner-provided Quake II data from browser-private storage…");
    for (const [path, metadata] of allowedPaks) {
      await streamIntoMemfs({ path, ...metadata });
    }
    FS.chmod("/data/baseq2", 0o555);
    FS.chmod("/data", 0o555);
    status("Starting Yamagi Quake II…");
  })().catch(error => {
    console.error("[quake2-wasm] startup failed", error);
    Module.quake2AssetFailed = true;
    if (Module.onAssetError) Module.onAssetError(error);
    try {
      abort(error);
    } catch (_) {
      // abort() marks the runtime failed; consume its sentinel exception so
      // this detached preparation chain cannot create an unhandled rejection.
    }
  }).finally(() => removeRunDependency(dependency));
});

Module.postRun = Module.postRun || [];
Module.postRun.push(function quake2StartPersistenceFlush() {
  setInterval(() => {
    FS.syncfs(false, error => {
      if (error) console.error("[quake2-wasm] persistence sync failed", error);
    });
  }, 10000);
});
