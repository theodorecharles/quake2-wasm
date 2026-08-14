/* Browser filesystem bootstrap for the native-source Quake II build. */

Module.preRun = Module.preRun || [];
Module.preRun.push(function quake2PrepareFilesystem() {
  const dependency = 'quake2-owner-data-and-persistence';
  const expected = new Map([
    ['pak0.pak', { size: 183997730 }],
    ['pak1.pak', { size: 12992754 }],
    ['pak2.pak', { size: 45055 }]
  ]);

  function status(message) {
    Module.setStatus?.(message);
    console.info(`[quake2-wasm] ${message}`);
  }

  async function validatePreparedEntries(dataSet) {
    const entries = Array.from(dataSet?.entries || []);
    const byKey = new Map(entries.map(entry => [String(entry.policy?.key || '').toLowerCase(), entry]));
    if (entries.length !== expected.size) throw new Error('Quake II owner-data set must contain exactly three PAKs.');

    for (const [key, rule] of expected) {
      const entry = byKey.get(key);
      if (!entry || !(entry.file instanceof Blob) || entry.file.size !== rule.size || entry.mountName !== key) {
        throw new Error(`Rejected prepared Quake II owner file: ${key}.`);
      }
      const header = new Uint8Array(await entry.file.slice(0, 4).arrayBuffer());
      if (header.length !== 4 || header[0] !== 0x50 || header[1] !== 0x41 ||
          header[2] !== 0x43 || header[3] !== 0x4b) {
        throw new Error(`${key} does not have a valid PACK header.`);
      }
    }
    return entries;
  }

  addRunDependency(dependency);
  (async function prepare() {
    if (!globalThis.WasmGameFramework) throw new Error('Shared wasm-game-framework package is unavailable.');
    const entries = await validatePreparedEntries(Module.quake2OwnerData);

    FS.mkdirTree('/data/baseq2');
    FS.mkdirTree('/persist');
    FS.mount(IDBFS, {}, '/persist');

    status('Restoring browser-local settings and saves…');
    await new Promise((resolve, reject) => FS.syncfs(true, error => error ? reject(error) : resolve()));

    status('Mounting registered Quake II data from this browser…');
    await WasmGameFramework.mountOwnerFiles(FS, entries, {
      root: '/data/baseq2',
      mode: 'memfs',
      chunkBytes: 16 * 1024 * 1024,
      onProgress(detail) {
        if (detail.phase !== 'mounting') return;
        const percent = detail.total ? Math.floor(detail.copied * 100 / detail.total) : 0;
        status(`Mounting registered Quake II data… ${percent}%`);
      }
    });
    FS.chmod('/data/baseq2', 0o555);
    FS.chmod('/data', 0o555);
    status('Starting Quake II…');
  })().catch(error => {
    console.error('[quake2-wasm] startup failed', error);
    Module.quake2AssetFailed = true;
    Module.onAssetError?.(error);
    try { abort(error); } catch (_) {}
  }).finally(() => removeRunDependency(dependency));
});

Module.postRun = Module.postRun || [];
Module.postRun.push(function quake2StartPersistenceFlush() {
  setInterval(() => {
    FS.syncfs(false, error => {
      if (error) console.error('[quake2-wasm] persistence sync failed', error);
    });
  }, 10000);
});
