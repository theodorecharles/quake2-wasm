(() => {
  'use strict';

  let engine = null;
  let ownerData = null;
  let resizeTimer = 0;
  let nextNativeResize = 0;
  let reportedState = 'menu';
  let qualityController = null;
  let telemetryTimer = 0;

  function nativeState() {
    if (!engine || typeof engine._Q2Web_RuntimeState !== 'function') return 'menu';
    return ['menu', 'gameplay', 'paused'][engine._Q2Web_RuntimeState()] || 'menu';
  }

  function safeName(value) {
    return String(value || '').replace(/[^A-Za-z0-9 _-]/g, '').trim().slice(0, 32) || 'Ranger';
  }

  function browserViewport() {
    const viewport = window.visualViewport;
    return {
      width: Math.max(640, Math.min(8192, Math.round(viewport ? viewport.width : window.innerWidth))),
      height: Math.max(360, Math.min(8192, Math.round(viewport ? viewport.height : window.innerHeight)))
    };
  }

  function graphicsArguments(profile, fps, viewport) {
    const profiles = {
      medium: ['+set', 'r_msaa_samples', '0', '+set', 'r_anisotropic', '2', '+set', 'r_shadows', '0', '+set', 'cl_particles', '0', '+set', 'cl_lights', '0'],
      high: ['+set', 'r_msaa_samples', '2', '+set', 'r_anisotropic', '8', '+set', 'r_shadows', '0', '+set', 'cl_particles', '1', '+set', 'cl_lights', '1'],
      ultra: ['+set', 'r_msaa_samples', '4', '+set', 'r_anisotropic', '16', '+set', 'r_shadows', '1', '+set', 'cl_particles', '1', '+set', 'cl_lights', '1']
    };
    return [
      '+set', 'vid_renderer', 'gles3',
      '+set', 'vid_fullscreen', '0',
      '+set', 'r_mode', '-1',
      '+set', 'r_customwidth', String(viewport.width),
      '+set', 'r_customheight', String(viewport.height),
      '+set', 'vid_maxfps', String(fps),
      '+set', 'horplus', '1',
      '+set', 'in_grab', '2',
      ...(profiles[profile] || profiles.high)
    ];
  }

  async function sha256Hex(file) {
    if (!globalThis.crypto?.subtle) throw new Error('SHA-256 verification requires HTTPS or localhost.');
    const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer());
    return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
  }

  async function loadEngineScript() {
    if (globalThis.createQuake2Module) return;
    await new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = '/quake2.js';
      script.onload = resolve;
      script.onerror = () => reject(new Error('Could not load quake2.js.'));
      document.head.appendChild(script);
    });
  }

  function startDynamicQuality(ctx, ceilingName, targetFps, enabled) {
    const levels = { medium: 0, high: 1, ultra: 2 };
    const profiles = ceilingName === 'ultra' ? ['ultra', 'high', 'medium'] :
      ceilingName === 'high' ? ['high', 'medium'] : ['medium'];
    qualityController?.stop();
    qualityController = ctx.framework.createQualityController({
      profiles,
      targetFps,
      enabled,
      apply(name, detail) {
        engine?._Q2Web_ApplyQuality(levels[name]);
        globalThis.__quake2Quality = { level: levels[name], name, targetFps, reason: detail.reason };
      },
      onSample(detail) {
        document.documentElement.dataset.quake2MeasuredFps = detail.fps.toFixed(1);
      }
    });
    qualityController.start();
  }

  function startTelemetry(ctx) {
    window.clearInterval(telemetryTimer);
    telemetryTimer = window.setInterval(() => {
      if (!engine) return;
      if (typeof engine._Q2Web_AudioCallbacks === 'function') {
        document.documentElement.dataset.quake2Audio = [
          engine._Q2Web_AudioCallbacks(),
          engine._Q2Web_AudioNonzeroCallbacks()
        ].join(',');
      }
      if (typeof engine._Q2Web_ControlsMask === 'function') {
        const mask = engine._Q2Web_ControlsMask();
        document.documentElement.dataset.quake2ControlsMask = String(mask);
        document.documentElement.dataset.quake2ControlsValid = String(mask === 255);
      }
      if (typeof engine._Q2Web_RenderWidth === 'function') {
        const renderWidth = engine._Q2Web_RenderWidth();
        const renderHeight = engine._Q2Web_RenderHeight();
        document.documentElement.dataset.quake2RenderSize = `${renderWidth}x${renderHeight}`;
        const viewport = browserViewport();
        if (typeof engine._Q2Web_ResizeViewport === 'function' &&
            (renderWidth !== viewport.width || renderHeight !== viewport.height) &&
            performance.now() >= nextNativeResize) {
          nextNativeResize = performance.now() + 750;
          engine._Q2Web_ResizeViewport(viewport.width, viewport.height);
        }
      }
      if (typeof engine._Q2Web_ViewWidth === 'function') {
        document.documentElement.dataset.quake2View = [
          engine._Q2Web_ViewWidth(),
          engine._Q2Web_ViewHeight(),
          engine._Q2Web_FovX100() / 100,
          engine._Q2Web_FovY100() / 100
        ].join(',');
      }
      const state = nativeState();
      if (state !== reportedState) {
        reportedState = state;
        ctx.setEngineState(state);
        engine._Q2Web_SetInputCaptured(ctx.shell.inputCaptured() ? 1 : 0);
      }
    }, 250);
  }

  globalThis.WasmGameAdapter = Object.freeze({
    async init(ctx) {
      const manifest = await fetch('/wasm-game-data.json', { cache: 'no-store' }).then(response => {
        if (!response.ok) throw new Error(`Quake II data policy failed with HTTP ${response.status}.`);
        return response.json();
      });
      ownerData = ctx.framework.createOwnerDataSet({
        namespace: manifest.namespace,
        version: manifest.version,
        files: manifest.files.map(spec => ({
          ...spec,
          mountName: spec.name,
          validateCached: false,
          validate: async file => {
            ctx.setLoading(`Verifying ${spec.name}…`);
            if (await sha256Hex(file) !== spec.sha256) throw new Error(`${spec.name} failed SHA-256 verification.`);
          }
        }))
      });
      ctx.elements.canvas.addEventListener('contextmenu', event => event.preventDefault());
    },

    async start(ctx) {
      if (engine) return;
      void ctx.shell.resumeAudio();
      const preferences = ctx.preferences.values();
      const name = safeName(preferences.playerName);
      const profile = preferences.qualityProfile;
      const fps = Number(preferences.targetFps) || 60;
      const viewport = browserViewport();
      ctx.setLoading('Restoring Quake II data…', '', 5);
      const preparedData = await ctx.dataClient.load(ownerData, {
        onProgress(detail) {
          if (detail.phase === 'checking-cache') ctx.setLoading(`Checking ${detail.key}…`);
          if (detail.phase === 'downloading') {
            const percent = detail.total ? Math.floor(detail.received * 100 / detail.total) : 0;
            ctx.setLoading(`Caching ${detail.key} from this container…`, `${percent}%`, Math.min(55, 5 + percent / 2));
          }
          if (detail.phase === 'restored') ctx.setLoading(`Restored ${detail.key} from this browser…`);
        }
      });
      document.documentElement.dataset.wasmDataSource = preparedData.entries.every(entry => entry.cached) ? 'cache' : 'container';
      ctx.setLoading('Loading Quake II engine…', '', 60);
      await loadEngineScript();
      engine = await globalThis.createQuake2Module({
        canvas: ctx.elements.canvas,
        quake2OwnerData: preparedData,
        arguments: ['-datadir', '/data', '+set', 'name', name, ...graphicsArguments(profile, fps, viewport)],
        print: value => { console.log('[Quake II WASM]', value); ctx.log(value); },
        printErr: value => { console.error('[Quake II WASM]', value); ctx.log(`ERROR: ${value}`); },
        setStatus: value => { if (value) ctx.setLoading(value); },
        onAbort(reason) {
          ctx.log(`Quake II stopped: ${reason}`);
          ctx.showRuntime('crashed');
        },
        onAssetError: error => ctx.log(error?.stack || error)
      });
      ctx.showRuntime();
      ctx.shell.resize();
      reportedState = nativeState();
      ctx.setEngineState(reportedState);
      startDynamicQuality(ctx, profile, fps, Boolean(preferences.dynamicQuality));
      startTelemetry(ctx);
    },

    readEngineState() { return nativeState(); },
    resize(detail) {
      if (!engine || typeof engine._Q2Web_ResizeViewport !== 'function') return;
      window.clearTimeout(resizeTimer);
      resizeTimer = window.setTimeout(() => engine?._Q2Web_ResizeViewport(detail.requestedWidth, detail.requestedHeight), 250);
    },
    captureLost() {
      if (!engine) return;
      engine._Q2Web_SetInputCaptured(0);
      engine._Q2Web_EnsureMenu();
    },
    inputCaptureChanged(captured) {
      if (engine) engine._Q2Web_SetInputCaptured(captured ? 1 : 0);
    }
  });
})();
