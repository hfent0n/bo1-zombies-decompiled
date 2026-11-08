# Loading mods on vel.gg through a Chrome extension

What we found by reading vel.gg's page scripts (`https://vel.gg/bsz`, November 2026) and building
`tools/velgg-checkpoints`. The checkpoint mod has been confirmed working on the live site. Anything marked
*untested* has not been tried there.

## 1. What vel.gg is

- vel.gg runs a WebAssembly build of this engine family (`artifacts/KisakBlack-web.mjs` + `.wasm`), entirely in the
  browser. It is not cloud streaming.
- It uses the same mod system as this repo: `+set fs_mods "a b c"` stacks `mods/a`, `mods/b` and `mods/c` on the
  search path. Each mod registers through `maps/<name>/_hooks.gsc`, and `mods/_stack` supplies the shared hooks
  (`_zombiemode_ffotd::main_end`, ...).
- The engine is a newer fork of this repo's code, so some engine-side names differ. The web build uses `kisak_*` dvars
  (`kisak_zombies`, `kisak_mod_zones`, `kisak_modff`), where this repo uses `bo1_*`.
- Key page scripts:
  - `maps.js`: map list and storage paths.
  - `play.js`: landing, downloader and pack gate.
  - `engine.js`: the engine's start arguments.
  - `download-worker.js`: manifest and SHA-256 checks.
  - `pack-selection.js`: which mod files are downloaded.
  - `coop.js` and `coop-metadata.js`: co-op rooms.

## 2. Where the game files live

- Each map's pack is stored in the site's private browser storage (OPFS) under a folder of its own: Five is `pack`, every
  other map `pack-<slug>` (`kino`, `riese`, `nacht`, `verruckt`, `shinonuma`, `ascension`, `cotd`, `shangrila`,
  `moon`).
- The engine's game folder is `/opfs/<pack>/files`, passed as `+set fs_b`. The engine's home folder is `/opfs/user`
  (`fs_h`), or `/opfs/user/coop-host` and `/opfs/user/coop-join` in co-op.
- The engine's file system looks names up in lowercase (`opfs-icase.js`), so files must be **stored with lowercase
  names**.
- Every file in the download manifest is SHA-256-checked when it's downloaded. Files that are **not** in the manifest
  are never checked or deleted. The engine opens them like any other file, because its pack gate only waits on files
  the manifest lists.

## 3. The four hooks

All of them run from a content script with `"world": "MAIN"` at `document_start`, before vel.gg's own code.

| Hook | How | Why |
|---|---|---|
| **Download the stack** | Wrap `window.Worker`. For `engine-download-worker.js`, wrap `postMessage` and add our mod names to `data.mods` in `download`/`inspect` messages. | `selectPack` only keeps `mods/_stack` when some mod is wanted (`wanted.size && !cstest`). Our own files aren't in the manifest, so the names only serve to bring `_stack` down. |
| **Write the mod files** | `navigator.storage.getDirectory()` → `<pack>/files/mods/<name>/...` with `createWritable()`. Write into every map's pack, since the map is unknown at page load. | This puts loose GSC and `.cfg` files where the engine's `fs_mods` search path finds them. |
| **Change the start arguments** | `Object.defineProperty(Object.prototype, 'callMain', { set })`. Emscripten does `Module["callMain"] = callMain`, so the setter wraps it. Edit `args` before `+devmap`: append to `fs_mods` or add it, add `+set` dvars, add `+exec <file>.cfg`. | `engine.js` calls `module.callMain(args)`. The engine reads `+set`/`+exec` lines in order (64 lines at most, about 1 KB each). |
| **Read game state** | Grab `module.HEAPU8.buffer` (a 2 GiB `SharedArrayBuffer`) from the wrapped module. Scan it in a blob worker for marked script strings. | Game scripts can't write files in this build, so state leaves the engine as text kept in memory. |

Communication between the page world and the extension uses `window.postMessage`, with a tag on each message.

## 4. Passing data in and out

- **In (at start):** write a `.cfg` file into the mod folder (`set cp_0 "..."`, ...) and add `+exec name.cfg` to the
  start arguments. Scripts read the values with `GetDvar`. Keep values to `[A-Za-z0-9_|:@#=.-]`: never `+`, `;`, `"`,
  spaces or `//`.
- **Out (while running):** the script keeps strings like `~cP9|<game id>|<seq>|<i>|<n>|<fields>|~cE` alive in a
  `level` variable. The scanner matches whole NUL-terminated strings and keeps the highest `seq` of the live game.
  Build the marker by concatenation (`"~c" + "P9|"`), so the script's own source text never matches.
- **Scan cost:** about 1 s per GiB in a worker. After the first hit, rescan only around where the strings were found.

## 5. Limits found

- **Script-only.** Loose `.gsc`, `.csc` and `.cfg` files work. Anything needing engine builtins that this repo adds
  (`bo1_savequit_*`, `bo1_mapkit_*`), or engine dvars the web build may have renamed (`bo1_mod_tabinfo`), does not.
- **Zones.** Mods that load other maps' zones (nightmare: `bo1_mod_zones`) need data that vel.gg's packs don't ship.
- **Counter-Strike guns** runs as `fs_game mods/cstest` with no `fs_mods`, so the stack and our mods are off in that
  mode.
- **Memory** is a fixed 2 GiB heap. That's why vel.gg caps horde at 300 zombies.
- **Fragility:** every hook depends on vel.gg's current page code, which can change without notice.

## 6. Co-op

- Host and friend both start through `callMain` with `+devmap`. The engine adds `kisak_web_coop 1`, and the friend
  also gets `kisak_join peer1` (it runs as a client).
- Game scripts run **on the host only**. A script-only mod therefore needs the extension on the host's machine alone.
  Friends start unchanged. *Untested:* the engine doesn't compare `fs_mods` between host and client (`sv_pure` is off).
- **Don't touch the room metadata.** `roomSelection` rejects any mod a map's pack doesn't ship ("The room uses
  unavailable mods").
- The checkpoint script saves every player (`p0` = the host). On load, it waits up to 30 s for `kisak_coop_players`
  players, then restores them in join order.

## 7. Custom models (`mod.ff`): wired in for the Halo mod, untested on vel.gg

The extension now does what this section describes, for `mod/halo` (README → "Halo weapons"). Two facts update the
plan below:
- The friend's `mod.ff` was built with **OpenAssetTools**, not the Mod Tools. The models and weapons are
  placeholders, with no animations, sounds or materials.
- The mod uses **`fs_game mods/halo` plus `fs_mods "halo ..."`**, so `mods/_stack` and our other mods still load
  alongside it.

- **Building:** new models, textures, sounds and weapon definitions have to be compiled into `mod.ff` with the
  official BO1 Mod Tools, which are Windows-only. OpenAssetTools can't build BO1 models yet.
- **Loading:** the engine loads `mod.ff` only with `fs_game` set (`src/database/db_registry.cpp:4503`). The web
  engine also needs the size up front: `+set kisak_modff <bytes>` (see vel.gg's `guns.js` `csArguments`).
- **Extension changes needed:**
  1. Write `mods/<name>/mod.ff` (binary) into storage.
  2. Start with `+set fs_game mods/<name> +set kisak_modff <size>`, without `fs_mods`.
  3. Ship the mod's own `maps/_zombiemode_ffotd.gsc` that calls the checkpoint and tweaks scripts, because the stack
     doesn't run under `fs_game`.
- **Co-op:** every player renders the models and needs the same weapon definitions, so **every player needs the
  extension** with the same `mod.ff`. Show a version code to compare. A friend can't get it through vel.gg's
  downloader, which only serves files vel.gg hosts. The alternatives are vel.gg hosting the mod, or the host sending
  it over the game connection (hard).
- **Licensing:** use openly licensed or original models (for example CC0 packs), not ripped Halo or Counter-Strike
  assets.

## 8. Related forks (MisaDev4/bo1-zombies-decompiled)

- **Kurtjwest:** a native macOS, Linux and Windows x64 port. It could let these mods be built and tested on a Mac,
  given the game files.
- **Thaolia:** a Switch port, dedicated servers, and `ffconv` (a 32-bit → 64-bit fastfile converter). `ffconv` is
  not an authoring tool.
- **spacemandev-git:** an earlier browser build of the engine, which would mean a web engine we control.
- No fork adds custom weapons or models.
