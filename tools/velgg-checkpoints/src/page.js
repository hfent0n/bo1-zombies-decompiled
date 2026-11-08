// vel.gg Checkpoints: the part that runs in the page's own JavaScript world (manifest "world": "MAIN"), at
// document_start, before any of vel.gg's scripts. It never runs engine code; it only:
//  1. asks vel.gg's pack downloader for the mod stack too (mods/_stack), by adding "checkpoint" to the mod list the
//     page posts to engine-download-worker.js (pack-selection.js selectPack keeps _stack when any mod is wanted);
//  2. adds "checkpoint" to fs_mods and "+exec checkpoint_load.cfg" to the engine's start arguments (engine.js calls
//     module.callMain(args); the Emscripten module sets Module["callMain"], which an Object.prototype setter catches);
//  3. writes the mod's script files and checkpoint_load.cfg into the map packs' OPFS folders (what the engine reads as
//     fs_b: /opfs/<pack>/files, names lowercase as opfs-icase.js stores them);
//  4. reads the checkpoint strings the mod keeps in script memory (mod/checkpoint/maps/checkpoint/_checkpoint.gsc) out
//     of the engine's heap, in a background worker when the heap is a SharedArrayBuffer.
// It talks to content.js (the extension's isolated world) with window.postMessage.
(() => {
  'use strict';
  const TAG = 'velgg-checkpoints';
  const MOD = 'checkpoint';
  const CFG = 'checkpoint_load.cfg';
  const CS_MOD = 'cstest'; // fs_game mod: the stack's files would shadow its own (vel.gg guns.js)

  // content.js's mod menu: the ticked mods in fs_mods order, each with the maps it runs on (null: every map) and the
  // dvars it is started with. Until content.js says otherwise: checkpoints only.
  let config = { enabled: true, mods: [{ id: MOD, zones: null, dvars: {} }] };
  let engine = null;  // { module, zone, startedAt, mods, checkpoint }
  const NAME = /^[a-z0-9_]{1,40}$/, VALUE = /^(-?\d{1,9}|[a-z0-9_]{1,40})$/; // a number, or a choice's id
  let installed = Promise.resolve();

  const send = msg => window.postMessage({ [TAG]: 'to-ext', ...msg }, location.origin);
  const log = (...args) => console.debug('[checkpoints]', ...args);

  //---------------------------------------------------------------------------------------------------------------
  // 1. the pack download: keep mods/_stack
  //---------------------------------------------------------------------------------------------------------------
  const OrigWorker = window.Worker;
  function patchDownload(data) {
    const ours = config.enabled ? config.mods.map(m => m.id) : [];
    if (!ours.length || !data || (data.type !== 'download' && data.type !== 'inspect') || !Array.isArray(data.mods)) return data;
    const mods = data.mods.map(String);
    if (mods.some(m => m.toLowerCase() === CS_MOD)) return data;
    return { ...data, mods: [...mods, ...ours.filter(id => !mods.includes(id))] };
  }
  window.Worker = new Proxy(OrigWorker, {
    construct(target, args) {
      const worker = Reflect.construct(target, args);
      if (/engine-download-worker\.js/.test(String(args[0]))) {
        const post = worker.postMessage;
        worker.postMessage = function (data, ...rest) { return post.call(this, patchDownload(data), ...rest); };
      }
      return worker;
    },
  });

  //---------------------------------------------------------------------------------------------------------------
  // 2. the engine's start arguments
  //---------------------------------------------------------------------------------------------------------------
  function setIndex(args, name) {
    for (let i = 1; i < args.length - 1; i++) if (args[i] === name && args[i - 1] === '+set') return i;
    return -1;
  }
  function patchArgs(module, args) {
    if (!config.enabled || !Array.isArray(args)) return;
    if (setIndex(args, 'fs_game') >= 0) { send({ type: 'engine', status: 'fs_game' }); return; }
    if (args.indexOf('+devmap') < 0) { send({ type: 'engine', status: 'nomap' }); return; }
    const zone = String(args[args.indexOf('+devmap') + 1] ?? '').toLowerCase();
    // co-op (engine.js: kisak_web_coop 1, the friend also kisak_join peer1): the game scripts run on the host's engine
    // only, so the host adds the mods and keeps the checkpoints; a friend's engine is a client and is left as the room
    // started it (the room's own mods, which vel.gg checks against the pack, stay the same on both sides).
    const role = setIndex(args, 'kisak_web_coop') < 0 ? 'solo' : setIndex(args, 'kisak_join') >= 0 ? 'join' : 'host';
    const before = (...items) => args.splice(args.indexOf('+devmap'), 0, ...items);
    let active = config.mods.filter(m => NAME.test(m.id) && (!m.zones || m.zones.includes(zone)));
    // a mod with its own mod.ff (Halo): the engine loads mod.ff only from the fs_game folder, and sizes its memory for
    // it before it reads any file (vel.gg guns.js: kisak_modff). One at a time, and only once its file is written.
    const withFf = active.filter(m => m.fsGame);
    // mod.ff and the mod's other files (Halo's halo.iwd, its textures, which the engine finds by scanning the fs_game
    // folder for *.iwd): every one written before the game starts
    const written = m => ffReady.get(m.fsGame + '/mod.ff') === m.ffStamp
      && (Array.isArray(m.extraFiles) ? m.extraFiles : []).every(e => ffReady.get(e?.path) === e?.stamp);
    const ffMod = withFf.find(m => written(m) && Number.isSafeInteger(m.ffSize) && /^mods\/[a-z0-9_]+$/.test(m.fsGame));
    for (const m of withFf) if (m !== ffMod) send({ type: 'engine', status: 'ff-skipped', id: m.id, pending: !written(m) });
    active = active.filter(m => !m.fsGame || m === ffMod);
    const ffArgs = ffMod ? ['+set', 'fs_game', ffMod.fsGame, '+set', 'kisak_modff', String(ffMod.ffSize)] : [];
    if (role === 'join') {
      // a friend's engine draws the mod.ff's models and needs its weapon definitions too, so it loads the same file;
      // the scripts (fs_mods) run on the host only
      if (ffMod) before(...ffArgs);
      send({ type: 'engine', status: 'started', zone, role, mods: ffMod ? [ffMod.id] : [], ffStamp: ffMod?.ffStamp });
      if (ffMod) log('engine start (co-op friend)', zone, args.join(' '));
      logBatch.push('[extension] start (co-op friend): ' + args.join(' '));
      return;
    }
    if (!active.length) { send({ type: 'engine', status: 'started', zone, role, mods: [] }); return; }
    const ids = active.map(m => m.id);
    if (ffMod) before(...ffArgs);
    const mods = setIndex(args, 'fs_mods');
    if (mods >= 0) {
      // ours after the page's own (horde, zinfo, ...): checkpoint last, so a loaded checkpoint's round wins
      const list = String(args[mods + 1]).split(/\s+/).filter(m => m && !ids.includes(m));
      args[mods + 1] = [...list, ...ids].join(' ');
    } else {
      before('+set', 'fs_mods', ids.join(' '));
    }
    for (const m of active) {
      for (const [name, value] of Object.entries(m.dvars ?? {})) {
        if (NAME.test(name) && VALUE.test(String(value))) before('+set', name, String(value));
      }
    }
    const checkpoint = ids.includes(MOD);
    if (checkpoint) before('+exec', CFG);
    engine = { module, zone, role, startedAt: Date.now(), mods: ids, checkpoint, status: !!ffMod };
    send({ type: 'engine', status: 'started', zone, role, mods: ids, ffStamp: ffMod?.ffStamp });
    log('engine start', zone, args.join(' '));
    logBatch.push(`[extension] start (${role}): ` + args.join(' '));
  }
  // the engine's console (engine.js: Module print/printErr -> console.log/console.error): from callMain on, keep the
  // lines about files, mods and scripts, for the popup's engine log (why a mod did or did not load)
  const LOG_MATCH = /mod\.ff|modff|iwd|search path|fs_game|fs_mods|halo|checkpoint|tweaks|sandbox|_stack|modstack|zone|fastfile|script|xmodel|weapon|precache|error|warning|couldn't|could not|can't|cannot|unknown|missing|not found|failed/i;
  // vel.gg's own once-a-second status lines (view/weaponstate, thread waits, load profiling): they matched "weapon"
  // and pushed every startup line out of the popup's log
  const LOG_SKIP = /^(KISAK_BROWSER view|KISAK_WAIT_CALLER|KISAK_FRAME_THREAD|KISAK_LOAD_PROXY|KISAK_LOAD_GL)\b|is missing TECHNIQUE_|couldn't find path to goal/;
  let logging = false, logBatch = [], logTimer = 0;
  for (const level of ['log', 'warn', 'error']) {
    const original = console[level];
    console[level] = function (...items) {
      if (logging) try {
        const line = items.map(String).join(' ');
        if (!line.startsWith('[checkpoints]') && LOG_MATCH.test(line) && !LOG_SKIP.test(line)) {
          logBatch.push(line.slice(0, 400));
          logTimer ||= setTimeout(() => { send({ type: 'engine-log', lines: logBatch }); logBatch = []; logTimer = 0; }, 1000);
        }
      } catch { /* never break the page's logging */ }
      return original.apply(this, items);
    };
  }

  Object.defineProperty(Object.prototype, 'callMain', {
    configurable: true,
    get() { return undefined; },
    set(fn) {
      const module = this;
      const value = typeof fn !== 'function' ? fn : function (args, ...rest) {
        logging = true;
        try { patchArgs(module, args); } catch (error) { console.warn('[checkpoints] could not add the mod', error); }
        return fn.call(this, args, ...rest);
      };
      Object.defineProperty(module, 'callMain', { value, writable: true, configurable: true, enumerable: true });
    },
  });

  //---------------------------------------------------------------------------------------------------------------
  // 3. files in OPFS
  //---------------------------------------------------------------------------------------------------------------
  async function writeText(root, path, text) {
    const parts = path.toLowerCase().split('/');
    let dir = root;
    for (const name of parts.slice(0, -1)) dir = await dir.getDirectoryHandle(name, { create: true });
    const handle = await dir.getFileHandle(parts.at(-1), { create: true });
    const writable = await handle.createWritable();
    await writable.write(text);
    await writable.close();
  }
  async function dirAt(path) {
    let dir = await navigator.storage.getDirectory();
    for (const name of path.toLowerCase().split('/').filter(Boolean)) dir = await dir.getDirectoryHandle(name, { create: true });
    return dir;
  }
  // the engine's home folders (fs_h): a mod under fs_game may be looked up there too (native: <fs_homepath>/<fs_game>)
  const HOMES = ['user', 'user/coop-host', 'user/coop-join'];
  async function install({ files, cfgs }) {
    for (const [pack, cfg] of Object.entries(cfgs)) {
      const base = await dirAt(pack + '/files');
      for (const [path, text] of Object.entries(files ?? {})) await writeText(base, path, text);
      await writeText(base, `mods/${MOD}/${CFG}`, cfg);
    }
    for (const home of files ? HOMES : []) {
      const base = await dirAt(home);
      for (const [path, text] of Object.entries(files)) await writeText(base, path, text);
    }
  }

  // the game's own log files under the engine's home folders (games_mp.log has the scripts' LogPrint lines: "halo: 22
  // of 22 weapons ...", "checkpoint: ..."; console_mp.log the console), found by walking OPFS user/ a few levels deep.
  // Only the tail of each, and only the lines about mods, files and errors.
  const GAME_LINE = /halo|iwd|search path|checkpoint|tweaks|sandbox|horde|zinfo|noperks|modstack|fs_mods|fs_game|mod\.ff|script|error|warning|couldn't|could not|unknown|not found|failed/i;
  async function readLogs() {
    const out = [];
    async function walk(dir, path, depth) {
      for await (const [name, handle] of dir.entries()) {
        if (handle.kind === 'directory' && depth < 4) await walk(handle, path + name + '/', depth + 1);
        else if (handle.kind === 'file' && /\.log$/i.test(name)) {
          try {
            const file = await handle.getFile();
            const text = await file.slice(Math.max(0, file.size - 256 * 1024)).text();
            const lines = text.split(/\r?\n/).filter(l => GAME_LINE.test(l) && !LOG_SKIP.test(l)).slice(-200);
            out.push({ path: path + name, size: file.size, modified: file.lastModified, lines });
          } catch (error) {
            // the engine may hold the file open (an OPFS sync access handle locks it) while the game runs
            out.push({ path: path + name, modified: 0, lines: [`(not readable while the game has it open: ${error?.name ?? error})`] });
          }
        }
      }
    }
    try { await walk(await navigator.storage.getDirectory().then(root => root.getDirectoryHandle('user')), 'user/', 0); }
    catch (error) { if (error?.name !== 'NotFoundError') throw error; }
    return out.sort((a, b) => b.modified - a.modified);
  }

  // binary mod files (mod.ff, .iwd): written once per version into every base, with a <path>.stamp beside each copy, so a
  // page load with the same file writes nothing. ffReady: path -> stamp, once every copy is in place.
  const ffReady = new Map();
  let binaryQueue = Promise.resolve();
  async function installBinary({ path, buffer, stamp, bases }) {
    const parts = path.toLowerCase().split('/'), name = parts.pop(), dirPath = parts.join('/');
    let wrote = 0;
    for (const base of bases) {
      const dir = await dirAt(base + '/' + dirPath);
      try {
        const [file, mark] = await Promise.all([(await dir.getFileHandle(name)).getFile(), (await dir.getFileHandle(name + '.stamp')).getFile()]);
        if (file.size === buffer.byteLength && (await mark.text()) === stamp) continue;
      } catch { /* not there yet */ }
      ffReady.delete(path);
      for (const [file, data] of [[name, buffer], [name + '.stamp', stamp]]) {
        const writable = await (await dir.getFileHandle(file, { create: true })).createWritable();
        await writable.write(data);
        await writable.close();
      }
      wrote++;
    }
    ffReady.set(path, stamp);
    return wrote;
  }

  //---------------------------------------------------------------------------------------------------------------
  // 4. reading the checkpoint strings
  //---------------------------------------------------------------------------------------------------------------
  // Runs in the scan worker (via toString) or, without a SharedArrayBuffer heap, on this thread. Script strings are
  // NUL-terminated; a match must be a whole string: ~cP9|gid|seq|i|n|fields|~cE or ~cP9L|token|~cE.
  function cpScan(u8, ranges) {
    const snaps = [], acks = [];
    let statuses; // ~cP9S|seq|text|~cE: a mod's status line (maps/halo/_halo_start.gsc)
    for (const [from, to] of ranges) {
      const start = Math.max(0, from), end = Math.min(u8.length, to);
      if (end <= start) continue;
      const view = u8.subarray(start, end);
      for (let p = view.indexOf(0x7e); p >= 0 && p < view.length; p = view.indexOf(0x7e, p + 1)) {
        if (view[p + 1] !== 0x63 || view[p + 2] !== 0x50 || view[p + 3] !== 0x39) continue; // "cP9"
        const at = start + p, limit = Math.min(u8.length, at + 1600);
        let q = at + 4;
        while (q < limit && u8[q] !== 0) q++;
        if (q >= limit) continue;
        let s = '';
        for (let k = at; k < q; k++) s += String.fromCharCode(u8[k]);
        let m = /^~cP9\|(\d{1,12})\|(\d{1,12})\|(\d{1,3})\|(\d{1,3})\|([\x21-\x7e]*)\|~cE$/.exec(s);
        if (m) snaps.push({ gid: m[1], seq: Number(m[2]), i: Number(m[3]), n: Number(m[4]), body: m[5], at });
        else if ((m = /^~cP9L\|([A-Za-z0-9]{1,40})\|~cE$/.exec(s))) acks.push({ token: m[1], at });
        else if ((m = /^~cP9S\|(\d{1,12})\|([\x20-\x7e]{1,600})\|~cE$/.exec(s))) (statuses ??= []).push({ seq: Number(m[1]), text: m[2], at });
      }
    }
    return { snaps, acks, statuses: statuses ?? [] };
  }
  const workerSource = `${cpScan.toString()}
onmessage = ({ data }) => {
  const t0 = performance.now();
  const result = cpScan(new Uint8Array(data.buffer), data.ranges);
  postMessage({ id: data.id, ...result, ms: performance.now() - t0 });
};`;
  let scanWorker = null, scanId = 0;
  function scanInWorker(buffer, ranges) {
    scanWorker ??= new OrigWorker(URL.createObjectURL(new Blob([workerSource], { type: 'text/javascript' })));
    const id = ++scanId;
    return new Promise((resolve, reject) => {
      const onMessage = ({ data }) => { if (data.id !== id) return; scanWorker.removeEventListener('message', onMessage); resolve(data); };
      scanWorker.addEventListener('message', onMessage);
      scanWorker.onerror = event => reject(new Error(event.message || 'scan worker failed'));
      scanWorker.postMessage({ id, buffer, ranges });
    });
  }

  const MB = 1 << 20;
  let hint = null;              // [from, to]: where the strings were found last time
  const gidSeq = new Map();     // game id -> highest seq seen so far
  let liveGid = null;
  let scanning = false;

  function heapOf(module) {
    const buffer = module.HEAPU8?.buffer ?? module.HEAPF32?.buffer;
    return buffer ? { buffer, length: buffer.byteLength, shared: typeof SharedArrayBuffer === 'function' && buffer instanceof SharedArrayBuffer } : null;
  }
  async function runScan(heap, ranges) {
    if (heap.shared) return scanInWorker(heap.buffer, ranges);
    const t0 = performance.now();
    return { ...cpScan(new Uint8Array(heap.buffer), ranges), ms: performance.now() - t0 };
  }

  // the newest complete set of chunks of the game that is running now
  function pick(snaps) {
    const sets = new Map();
    for (const s of snaps) {
      const key = s.gid + '|' + s.seq;
      let set = sets.get(key);
      if (!set) sets.set(key, set = { gid: s.gid, seq: s.seq, n: s.n, chunks: [] });
      if (s.n === set.n && s.i < s.n) set.chunks[s.i] = s.body;
    }
    const complete = [...sets.values()].filter(set => set.n > 0 && set.chunks.length === set.n && set.chunks.every(c => typeof c === 'string'));
    const best = new Map();
    for (const set of complete) if (!best.has(set.gid) || best.get(set.gid).seq < set.seq) best.set(set.gid, set);
    // live: a game whose newest seq moved since the last scan; first scan: the newest overall
    let grown = [...best.values()].filter(set => set.seq > (gidSeq.get(set.gid) ?? -1));
    if (gidSeq.size && grown.length) liveGid = grown.sort((a, b) => b.seq - a.seq)[0].gid;
    else if (!gidSeq.size && best.size) liveGid = [...best.values()].sort((a, b) => b.seq - a.seq)[0].gid;
    for (const set of best.values()) gidSeq.set(set.gid, Math.max(set.seq, gidSeq.get(set.gid) ?? -1));
    return liveGid && best.get(liveGid) || null;
  }

  async function scan(reason) {
    if (!engine) { send({ type: 'scan-result', reason, error: 'No game is running on this page yet.' }); return; }
    // status-only games (Halo without checkpoints) are scanned for the mods' status line alone
    if (!engine.checkpoint && !engine.status) { send({ type: 'scan-result', reason, error: 'Checkpoints were off when this game started.' }); return; }
    if (scanning) { send({ type: 'scan-result', reason, error: 'Still reading the last checkpoint.' }); return; }
    const heap = heapOf(engine.module);
    if (!heap) { send({ type: 'scan-result', reason, error: 'The game is still starting.' }); return; }
    if (reason === 'auto' && !heap.shared) return; // a whole-heap scan on the page's thread would stall the game
    scanning = true;
    try {
      let ranges = hint ? [hint] : [[0, heap.length]];
      let result = await runScan(heap, ranges);
      if (hint && !result.snaps.length && !result.statuses.length) result = await runScan(heap, ranges = [[0, heap.length]]);
      const found = [...result.snaps, ...result.acks, ...result.statuses].map(x => x.at);
      if (result.statuses.length) send({ type: 'mod-status', lines: [...new Set(result.statuses.sort((a, b) => b.seq - a.seq).map(x => x.text))].slice(0, 5) });
      if (!engine.checkpoint) return;
      if (found.length) hint = [Math.min(...found) - 64 * MB, Math.max(...found) + 64 * MB];
      if (result.acks.length) send({ type: 'acks', zone: engine.zone, tokens: [...new Set(result.acks.map(a => a.token))] });
      const set = pick(result.snaps);
      log(`scan (${reason}): ${result.snaps.length} chunks, ${result.acks.length} acks, ${Math.round(result.ms)} ms`);
      if (!set) { send({ type: 'scan-result', reason, error: 'No checkpoint yet: it is taken every 2 s while every player is up.' }); return; }
      send({ type: 'snapshot', reason, zone: engine.zone, gid: set.gid, seq: set.seq, chunks: set.chunks });
    } catch (error) {
      send({ type: 'scan-result', reason, error: String(error?.message ?? error) });
    } finally { scanning = false; }
  }
  setInterval(() => { if ((engine?.checkpoint || engine?.status) && !document.hidden) scan('auto'); }, 15000);

  //---------------------------------------------------------------------------------------------------------------
  // messages from content.js
  //---------------------------------------------------------------------------------------------------------------
  window.addEventListener('message', event => {
    const data = event.data;
    if (event.source !== window || !data || data[TAG] !== 'to-main') return;
    if (data.type === 'ping') send({ type: 'hello' });
    else if (data.type === 'config') {
      config = { enabled: data.enabled !== false, mods: Array.isArray(data.mods) ? data.mods.filter(m => m && NAME.test(m.id)) : config.mods };
    }
    else if (data.type === 'install') {
      installed = installed.then(() => install(data)).then(
        () => send({ type: 'installed', packs: Object.keys(data.cfgs) }),
        error => send({ type: 'install-error', message: String(error?.message ?? error) }));
    } else if (data.type === 'read-logs') {
      readLogs().then(files => send({ type: 'game-logs', id: data.id, files }),
        error => send({ type: 'game-logs', id: data.id, files: [{ path: '(error)', lines: [String(error?.message ?? error)] }] }));
    } else if (data.type === 'install-binary') {
      if (typeof data.path !== 'string' || !/^mods\/[a-z0-9_]+\/(mod\.ff|[a-z0-9_]+\.iwd)$/.test(data.path) || !(data.buffer instanceof ArrayBuffer)
        || !/^[a-f0-9]{12}$/.test(data.stamp) || !Array.isArray(data.bases)) return;
      const t0 = performance.now();
      binaryQueue = binaryQueue.then(() => installBinary(data)).then(
        wrote => { send({ type: 'binary-ready', path: data.path, stamp: data.stamp, wrote }); log(`${data.path} ${data.stamp}: ${wrote} copies written in ${Math.round(performance.now() - t0)} ms`); },
        error => send({ type: 'install-error', message: `${data.path}: ${String(error?.message ?? error)}` }));
    } else if (data.type === 'scan') scan(data.reason === 'manual' ? 'manual' : 'auto');
  });
  send({ type: 'hello' });
})();
