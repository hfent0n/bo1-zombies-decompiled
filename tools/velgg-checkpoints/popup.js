// vel.gg Checkpoints popup: lists the checkpoints per map, arms one to load on the next start of that map.
'use strict';
const MAP_NAMES = {
  zombie_pentagon: 'Five', zombie_theater: 'Kino der Toten', zombie_cod5_factory: 'Der Riese',
  zombie_cod5_prototype: 'Nacht der Untoten', zombie_cod5_asylum: 'Verrückt', zombie_cod5_sumpf: 'Shi No Numa',
  zombie_cosmodrome: 'Ascension', zombie_coast: 'Call of the Dead', zombie_temple: 'Shangri-La', zombie_moon: 'Moon',
};
const KIND = { auto: 'Latest', round: 'Round start', manual: 'Saved' };
const $ = id => document.getElementById(id);

const ago = t => {
  const s = Math.max(0, Math.round((Date.now() - t) / 1000));
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.round(s / 60)} min ago`;
  if (s < 86400) return `${Math.round(s / 3600)} h ago`;
  return new Date(t).toLocaleDateString();
};
const token = () => Array.from(crypto.getRandomValues(new Uint8Array(8)), b => (b % 36).toString(36)).join('');

async function velTab() {
  const tabs = await chrome.tabs.query({ url: 'https://vel.gg/*' });
  return tabs.find(t => t.active) ?? tabs[0] ?? null;
}

async function render() {
  const all = await chrome.storage.local.get(null);
  const settings = all.settings ?? {}, armed = all.armed ?? {};
  $('enabled').checked = settings.enabled !== false;
  $('renderer').value = settings.renderer === 'webgl2' ? 'webgl2' : 'auto';
  document.body.classList.toggle('disabled', settings.enabled === false);
  renderMods(settings);

  const tab = await velTab();
  let engineZone = null, log = [];
  if (tab) try {
    const status = await chrome.tabs.sendMessage(tab.id, { type: 'status' });
    engineZone = status?.engineZone ?? null;
    log = Array.isArray(status?.log) ? status.log : [];
    if (Array.isArray(status?.modStatus) && status.modStatus.length) $('mod-status').textContent = 'Mod status:\n' + status.modStatus.join('\n');
    for (const f of Array.isArray(status?.gameLogs) ? status.gameLogs : []) {
      if (f?.lines?.length) log.push('', `--- ${f.path} (game log, last mod lines) ---`, ...f.lines);
    }
  } catch { /* no content script yet */ }
  if (log.length) $('log-lines').textContent = log.join('\n');
  $('save-now').disabled = !engineZone;
  $('status').textContent = !tab ? 'Open vel.gg to play.' : engineZone
    ? `Playing ${MAP_NAMES[engineZone] ?? engineZone}. A checkpoint is kept every round.` : 'vel.gg is open; start a map.';

  const list = $('list');
  list.replaceChildren();
  const zones = Object.keys(all).filter(k => k.startsWith('cp:')).map(k => k.slice(3))
    .filter(z => all['cp:' + z]?.length || armed[z]);
  if (!zones.length) {
    list.append(Object.assign(document.createElement('p'), { className: 'empty', textContent: 'No checkpoints yet. Play a round on vel.gg.' }));
    return;
  }
  zones.sort((a, b) => (a === engineZone ? -1 : b === engineZone ? 1 : (MAP_NAMES[a] ?? a).localeCompare(MAP_NAMES[b] ?? b)));
  for (const zone of zones) {
    list.append(Object.assign(document.createElement('h2'), { textContent: MAP_NAMES[zone] ?? zone }));
    const a = armed[zone];
    if (a) list.append(card(zone, a.checkpoint, { armed: true, tab }));
    const items = [...(all['cp:' + zone] ?? [])].sort((x, y) => y.savedAt - x.savedAt);
    for (const cp of items) list.append(card(zone, cp, { tab }));
  }
}

function card(zone, cp, { armed = false, tab }) {
  const el = document.createElement('div');
  el.className = 'cp' + (armed ? ' armed' : '');
  const info = document.createElement('div');
  info.className = 'info';
  info.append(
    Object.assign(document.createElement('div'), { className: 'title', textContent: `Round ${cp.round}` + (armed ? ' · loads next start' : '') }),
    Object.assign(document.createElement('div'), { className: 'meta',
      textContent: `${KIND[cp.kind] ?? cp.kind} · ${cp.score.toLocaleString()} pts · ${ago(cp.savedAt)}` }));
  const actions = document.createElement('div');
  actions.className = 'actions';
  const button = (text, onClick, primary = false) => {
    const b = Object.assign(document.createElement('button'), { type: 'button', textContent: text });
    if (primary) b.className = 'primary';
    b.addEventListener('click', onClick);
    actions.append(b);
  };
  if (armed) {
    if (tab) button('Restart', () => chrome.tabs.reload(tab.id), true);
    button('Cancel', async () => {
      const { armed: all = {} } = await chrome.storage.local.get('armed');
      delete all[zone];
      await chrome.storage.local.set({ armed: all });
      render();
    });
  } else {
    button('Load', async () => {
      const { armed: all = {} } = await chrome.storage.local.get('armed');
      all[zone] = { token: token(), checkpoint: structuredClone(cp), armedAt: Date.now() };
      await chrome.storage.local.set({ armed: all });
      render();
    }, true);
    button('✕', async () => {
      const key = 'cp:' + zone;
      const { [key]: items = [] } = await chrome.storage.local.get(key);
      await chrome.storage.local.set({ [key]: items.filter(c => c.id !== cp.id) });
      render();
    });
    actions.lastChild.title = 'Delete';
  }
  el.append(info, actions);
  return el;
}

// the mod menu: settings.mods = { [id]: { on, [key]: value } }
async function setMod(id, patch) {
  const { settings = {} } = await chrome.storage.local.get('settings');
  const mods = { ...(settings.mods ?? {}) };
  mods[id] = { ...(mods[id] ?? {}), ...patch };
  await chrome.storage.local.set({ settings: { ...settings, mods } });
}
function renderMods(settings) {
  const box = $('mods');
  const focused = document.activeElement;
  if (box.contains(focused) && focused.type === 'number') return; // do not rebuild while a number is being typed
  box.replaceChildren();
  const saved = settings.mods ?? {};
  for (const mod of globalThis.VELGG_MODS) {
    const on = saved[mod.id]?.on ?? mod.on;
    const el = document.createElement('div');
    el.className = 'mod' + (on ? '' : ' off');
    const label = document.createElement('label');
    const check = Object.assign(document.createElement('input'), { type: 'checkbox', checked: on });
    check.addEventListener('change', () => setMod(mod.id, { on: check.checked }));
    const text = document.createElement('div');
    text.append(Object.assign(document.createElement('div'), { className: 'title', textContent: mod.name }),
      Object.assign(document.createElement('div'), { className: 'meta', textContent: mod.desc }));
    label.append(check, text);
    el.append(label);
    if (mod.settings.length) {
      const opts = document.createElement('div');
      opts.className = 'opts';
      for (const s of mod.settings) {
        const value = saved[mod.id]?.[s.key] ?? s.def;
        let input;
        if (s.type === 'choice') {
          input = document.createElement('select');
          for (const [v, label] of s.options) input.append(new Option(label, v, false, v === String(value)));
        } else input = s.type === 'bool'
          ? Object.assign(document.createElement('input'), { type: 'checkbox', checked: !!Number(value) })
          : Object.assign(document.createElement('input'), { type: 'number', min: s.min, max: s.max, step: 1, value });
        input.addEventListener('change', () => {
          if (s.type === 'choice') return setMod(mod.id, { [s.key]: input.value });
          if (s.type === 'bool') return setMod(mod.id, { [s.key]: input.checked ? 1 : 0 });
          const n = Math.max(s.min, Math.min(s.max, Math.round(Number(input.value))));
          input.value = Number.isFinite(n) ? n : s.def;
          setMod(mod.id, { [s.key]: Number(input.value) });
        });
        opts.append(Object.assign(document.createElement('span'), { textContent: s.label }), input);
      }
      el.append(opts);
    }
    box.append(el);
  }
}

// vel.gg picks the renderer once per page load, so a change reloads the vel.gg tab
$('renderer').addEventListener('change', async event => {
  const { settings = {} } = await chrome.storage.local.get('settings');
  await chrome.storage.local.set({ settings: { ...settings, renderer: event.target.value } });
  const tab = await velTab();
  if (tab) setTimeout(() => chrome.tabs.reload(tab.id), 300); // after content.js has applied it
});

$('enabled').addEventListener('change', async event => {
  const { settings = {} } = await chrome.storage.local.get('settings');
  await chrome.storage.local.set({ settings: { ...settings, enabled: event.target.checked } });
});
$('save-now').addEventListener('click', async () => {
  const tab = await velTab();
  if (tab) await chrome.tabs.sendMessage(tab.id, { type: 'save-now' }).catch(() => {});
  setTimeout(render, 1500);
});
$('copy-log').addEventListener('click', () => navigator.clipboard.writeText($('mod-status').textContent + '\n\n' + $('log-lines').textContent));
chrome.storage.onChanged.addListener(() => render());
render();
