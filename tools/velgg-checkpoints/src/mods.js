// The mod menu: every mod the extension can add, in fs_mods order (checkpoint last, so a loaded checkpoint's round
// wins over the others). Loaded by content.js (via the manifest) and popup.html. The files come from mod-files.js.
//   zones:    the maps it runs on (null: every map)
//   settings: popup inputs, each passed to the engine as +set <dvar> <value> (integers only)
//   fsGame:   a mod with its own mod.ff, which the engine loads only from the fs_game folder: the game starts with
//             +set fs_game <fsGame> +set kisak_modff <size>, and in co-op every player needs the same file
//   ff:       that mod.ff inside the extension (content.js fetches it and page.js writes it into OPFS)
//   extras:   its other files, written beside mod.ff in the fs_game folder (halo.iwd: the textures)
globalThis.VELGG_MODS = [
  {
    id: 'halo', name: 'Halo weapons', zones: null, on: false, fsGame: 'mods/halo', ff: 'mod/halo/mod.ff', extras: ['mod/halo/halo.iwd'],
    desc: '22 Halo-style guns with their own textures (your friend\'s mod.ff and halo.iwd) at buy spots around the spawn, using stock guns\' animations and sounds. In co-op every player needs this extension with the Halo mod on.',
    settings: [
      { key: 'start', dvar: 'halo_start_weapon', label: 'Starting gun', type: 'choice', def: 'magnum', options: [
        ['0', 'Retail pistol'], ['magnum', 'M6G Magnum'], ['assault_rifle', 'MA37 Assault Rifle'], ['dmr', 'M392 DMR'],
        ['shotgun', 'M45 Shotgun'], ['sniper_rifle', 'SRS99 Sniper Rifle'], ['plasma_pistol', 'Plasma Pistol'],
        ['needler', 'Needler'], ['plasma_rifle', 'Plasma Rifle'], ['plasma_repeater', 'Plasma Repeater'],
        ['spiker', 'Type-25 Spiker'], ['needle_rifle', 'Needle Rifle'] ] },
      { key: 'buys', dvar: 'halo_buys', label: 'Buy spots around the spawn', type: 'bool', def: 1 },
      { key: 'free', dvar: 'halo_buy_free', label: 'Free', type: 'bool', def: 0 },
      { key: 'box', dvar: 'halo_box', label: 'Also in the Mystery Box (experimental)', type: 'bool', def: 0 },
      // the friend's diagnostic: the four test models alone, so the 22 buy-spot models (300,000+ vertices) do not
      // overflow the engine's per-frame cache for animated models
      { key: 'test', dvar: 'halo_test_models', label: 'Test models only (turns buy spots off)', type: 'bool', def: 0,
        forces: { halo_buys: 0 } },
    ],
  },
  {
    id: 'sandbox', name: 'Sandbox', zones: ['zombie_pentagon'], on: false,
    desc: 'Five only. Power on, every door open, DEFCON 5, and pads in the spawn room that give every perk, power-up and weapon.',
    settings: [
      { key: 'points', dvar: 'sandbox_points', label: 'Starting points', min: 0, max: 9999999, def: 500000 },
      { key: 'round', dvar: 'sandbox_round', label: '"Set round" pad goes to', min: 1, max: 255, def: 20 },
    ],
  },
  {
    id: 'tweaks', name: 'Game tweaks', zones: null, on: false,
    desc: 'Start round, starting points, power and a third-person camera, on any map.',
    settings: [
      { key: 'round', dvar: 'tweaks_start_round', label: 'Start round', min: 1, max: 255, def: 1 },
      { key: 'points', dvar: 'tweaks_start_points', label: 'Starting points', min: 0, max: 9999999, def: 500 },
      { key: 'power', dvar: 'tweaks_power', label: 'Power on at start', type: 'bool', def: 0 },
      { key: 'third', dvar: 'tweaks_third_person', label: 'Third person camera', type: 'bool', def: 0 },
    ],
  },
  {
    id: 'checkpoint', name: 'Checkpoints', zones: null, on: true,
    desc: 'Keeps a checkpoint every round; F8 saves one now. Load them below.',
    settings: [],
  },
];

// settings.mods = { [id]: { on, [key]: value } } -> what page.js gets: the ticked mods with their dvars
globalThis.velggModConfig = function (settings = {}) {
  const saved = settings.mods ?? {};
  return globalThis.VELGG_MODS.filter(mod => saved[mod.id]?.on ?? mod.on).map(mod => {
    const config = configOf(mod, saved);
    // a ticked bool with "forces" overrides other settings' dvars (Halo's test models turn the buy spots off)
    for (const s of mod.settings) if (s.forces && config.dvars[s.dvar] === 1) Object.assign(config.dvars, s.forces);
    return config;
  });
};
function configOf(mod, saved) {
  return ({
    id: mod.id, zones: mod.zones, fsGame: mod.fsGame ?? null,
    dvars: Object.fromEntries(mod.settings.map(s => {
      if (s.type === 'choice') {
        const pick = String(saved[mod.id]?.[s.key] ?? s.def);
        return [s.dvar, s.options.some(([v]) => v === pick) ? pick : s.def];
      }
      const raw = Number(saved[mod.id]?.[s.key] ?? s.def);
      const value = s.type === 'bool' ? (raw ? 1 : 0) : Math.max(s.min, Math.min(s.max, Math.round(Number.isFinite(raw) ? raw : s.def)));
      return [s.dvar, value];
    })),
  });
}
