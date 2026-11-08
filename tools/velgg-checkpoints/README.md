# vel.gg Checkpoints (browser extension)

Round checkpoints and a mod menu for the browser build of BO1 zombies on [vel.gg](https://vel.gg/bsz). It is a
Chrome/Edge Manifest V3 extension. Checkpoints have been confirmed working on the live site. The mod menu's Sandbox
and Game tweaks mods have not been tried there yet.

## Mod menu (popup)

Each mod is a checkbox, and some have settings. A change applies the next time a map starts. The ticked mods go into
`fs_mods` after the page's own mods (horde, zinfo, ...), in this order: sandbox, tweaks, checkpoint. Their settings
are passed as `+set` dvars.

| Mod | Maps | Settings (dvars) | Source |
|---|---|---|---|
| Sandbox | Five only | starting points (`sandbox_points`), "set round" pad target (`sandbox_round`) | the repo's `mods/sandbox/maps/sandbox/` |
| Game tweaks | all | start round (`tweaks_start_round`), starting points (`tweaks_start_points`), power on (`tweaks_power`) | `mod/tweaks/` |
| Checkpoints | all | none | `mod/checkpoint/` |

Game tweaks does nothing when a checkpoint is loading, so the checkpoint's own state wins.

### Halo weapons (a mod with its own `mod.ff`) - *untested on vel.gg*

`mod/halo/` holds your friend's Halo mod: `maps/halo/*.gsc` and `mod.ff`, 4.8 MB of models and weapons. See
`mod/halo/README.md`. `mod.ff` is in `.gitignore`, so copy it in after a fresh clone.

- **Loading:** content.js fetches `mod.ff` from the extension (falling back to `src/background.js` if the page's
  COEP blocks that fetch) and fingerprints it. Its version code is the first 12 hex digits of its SHA-256. page.js
  writes it into every map pack and into `user`, `user/coop-host` and `user/coop-join`, with a `.stamp` beside each
  copy so later page loads write nothing. The first copy-in takes a moment; if a map starts before it finishes,
  Halo is left out and a toast says to restart.
- **Engine start:** `+set fs_game mods/halo +set kisak_modff <size>`, with `halo` first in `fs_mods`, so the stack
  and the other mods keep working. The Halo settings are passed as `halo_buys`, `halo_buy_free` and `halo_box`.
- **Co-op:** every player needs the extension with Halo on. A friend's engine gets `fs_game` and `kisak_modff` too,
  because it draws the models and needs the weapon definitions, but not the scripts. Compare the version code in
  each player's toast.
- **Unknowns on vel.gg:** whether its engine looks for `mod.ff` in the pack or the home folder (we write both), and
  whether it accepts a `mod.ff` it didn't ship.

Not offered, because vel.gg's engine or packs lack what they need:
- **mapkit** calls `bo1_mapkit_*` engine builtins.
- **nightmare** needs other maps' zones loaded (`bo1_mod_zones`), and vel.gg's packs don't ship them.
- **zinfo** relies on the `bo1_mod_tabinfo` engine dvar. vel.gg ships its own zinfo in horde mode.

To add a mod, put it in `src/mods.js` and `build-mod.mjs`'s `SOURCES`. It has to be pure game script that registers
through `maps/<name>/_hooks.gsc`.

## Checkpoints

- **Automatic checkpoints:** the latest state, plus the start of each of the last 15 rounds, for every map.
- **F8 in game:** saves a named checkpoint now (up to 20 per map).
- **Popup → Load:** arms a checkpoint for that map. **Restart** reloads the vel.gg tab. Start the same map again
  and the game begins at the start of the saved round, with the saved state.

Saved: round, power, opened doors and debris, points, perks, and weapons with ammo and offhand items (the same set
as `mods/savequit`). Not saved: zombies, power-ups, the box location, map quests and timers.

## Co-op

The game scripts run only on the host's engine, so only the host's extension does anything:
- **Host:** adds the ticked mods and their settings, keeps the checkpoints (every player is saved, with p0 = the
  host) and loads them. On load, the script waits up to 30 s for the saved players to connect, then restores them
  all at once, matched by join order.
- **Friend:** the engine starts exactly as the room set it up, so friends don't need the extension. The room's own
  mod list is left alone, because vel.gg checks it against what each pack ships.

Game tweaks' starting points also reach friends who connect during the first minute.

The extension turns itself off for the Counter-Strike guns mode (an `fs_game` mod).

Untested in a real co-op game. The engine doesn't compare `fs_mods` between host and client (`sv_pure` is off), and
the added mods are server-side game script only. If a friend can't join a modded host, that's where to look.

## Install

1. Open `chrome://extensions` and turn on **Developer mode**.
2. Click **Load unpacked** and pick this folder (`tools/velgg-checkpoints`).
3. Open vel.gg and start a map. A toast says `Checkpoints on: F8 saves` once the engine starts with the mod.

After editing anything in `mod/` or `mods/sandbox`, run `node build-mod.mjs` (it regenerates `src/mod-files.js`), then reload the
extension.

## How it works

vel.gg runs the engine as WebAssembly, with the same `mods/_stack` + `fs_mods` mod system as this repo. The browser
engine has no file builtins, so the save path of `mods/savequit` cannot work there. Instead:

| Piece | What it does |
|---|---|
| `mod/checkpoint/maps/checkpoint/_checkpoint.gsc` | Every 2 s while every player is up, keeps the state in a few script strings: `~cP9\|<game id>\|<seq>\|<chunk>\|<chunks>\|<fields>\|~cE`. On load, reads `cp_*` dvars and restores the state, as Save & Quit does. |
| `src/page.js` (page world) | Adds `checkpoint` to the mod list the page posts to `engine-download-worker.js`, so `mods/_stack` is downloaded. Adds `checkpoint` to `fs_mods` and `+exec checkpoint_load.cfg` to the engine's `callMain` arguments. Writes the mod files and the cfg into each map pack's OPFS folder (`/opfs/<pack>/files`). Every 15 s, a worker scans the engine heap (a SharedArrayBuffer) for those strings. |
| `src/content.js` (extension world) | Stores checkpoints in `chrome.storage.local`, writes the armed checkpoint into that map's `checkpoint_load.cfg`, handles F8 and shows toasts. When the game reports `~cP9L\|<token>\|~cE` (the checkpoint was read), it disarms the checkpoint. |
| `popup.*` | Lists, loads and deletes checkpoints, and turns the extension on or off. |

## Testing it, and what might break

There is no web build in this repo, so the first real test is on vel.gg itself. Keep DevTools open (filter the
console on `[checkpoints]`):

1. **Engine start:** the console shows `engine start zombie_… … +set fs_mods … checkpoint … +exec checkpoint_load.cfg`.
   If it doesn't, vel.gg changed how it starts the engine (`engine.js`, `module.callMain`).
2. **Mod loads:** play past round 1. A `Round 2 checkpoint` toast should appear within about 15 s, and the console
   shows `scan (auto): N chunks`. If there are 0 chunks, the script did not run. Check that `mods/_stack` and
   `mods/checkpoint` exist under DevTools → Application → Storage → OPFS → `pack…/files/mods`.
3. **Load:** popup → Load → Restart, start the same map, and wait for `Checkpoint loaded: round N` in game.

Known risks:

- **Site updates** that change the downloader messages, the `callMain` call or the OPFS layout will break the hooks.
- **Heap scan cost:** the first scan reads the whole 2 GiB heap, which takes about 2 s on a background thread. Later
  scans read only the area where the strings were found last time.
- **Freshness:** a checkpoint is at most 2 s old (the script refresh). Auto checkpoints are at most about 17 s old.
  A state where a player is down is never saved.
- **Points mid-round:** a checkpoint taken mid-round restores those points at the start of that round. This matches
  Save & Quit.
