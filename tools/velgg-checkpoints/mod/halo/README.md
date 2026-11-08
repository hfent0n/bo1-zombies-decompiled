# halo - Halo Reach weapons in Black Ops 1 Zombies (NOT part of the original game)

Halo Reach's UNSC and Covenant weapons as zombie weapons: at buy spots, optionally in the Mystery Box and on wall
buys, with Pack-a-Punch versions.
For your own play only. The models and textures are Bungie's (ripped and rigged by a fan porter, see their
`credits.txt`), so `mods/halo/mod.ff` and anything built from them stay out of the repository and are not shared
(`.gitignore` excludes them).

The mod is this folder and nothing else: its scripts, `mods/halo/mod.ff` (the models, materials, weapons and a list
of them) and `mods/halo/halo.iwd` (the textures). It uses retail script functions only, so it needs no engine change
and can be side-loaded. Both files are built from the assets `tools/halo` exports, either with OpenAssetTools, a
community fastfile builder, reading the installed game's `common_zombie.ff` (section 2a, no mod tools needed), or with
the official **Call of Duty: Black Ops Mod Tools** (section 2). Without `mod.ff` the mod does not load: the log names
the missing `maps/halo/_halo_list`.

## What is done, and what is left

| Step | State |
| --- | --- |
| Models: the 22 weapons and 7 projectiles to CoD `xmodel_export`, scaled to inches, bones renamed for the donor animations, `tag_flash` / `tag_brass` added | Done by `tools\halo\export.ps1` (checked: `tools\halo\check_xmodel.py`) |
| Textures: diffuse and normal maps to TGA; glow-only materials as one-colour textures | Done by the export |
| Asset sheet (every xmodel, material and weapon file to create), `mod.csv`, `halo.str` (wall-buy texts) | Done by the export |
| Scripts: buy spots around the spawn, optional box and wall registration, `halo_give` / `halo_show` test commands | Done (`maps/halo/_halo.gsc`), retail script functions only |
| `mod.ff` + `halo.iwd` with OpenAssetTools (`tools\halo\build_ff.ps1`): 29 models, 45 Halo materials, 67 textures, 22 weapons and their Pack-a-Punch versions, the list | Built (4.8 MB + 18.4 MB) and read back with OAT's Unlinker; not yet tried in the game |
| Weapons: each its donor's weapon file (animations, sounds, effects, hands) with the Halo model and stats | Built; the sword, hammer and grenades are held like the M1911 for now |
| Create the xmodels, materials and weapon files in the mod tools, build `mod.ff` | **You**, with the mod tools (below) |
| First-person animations | Borrowed from a stock donor weapon per gun (`tools\halo\weapons.json`); Halo's own were not in the export |
| Sounds, muzzle flashes, projectile effects | The donor's until replaced |
| Halo-only behaviour (Needler homing, overcharge, Spartan Laser charge, sword lunge, sticky plasma grenade) | Not yet: marked `special` in `weapons.json` |

## 1. Export the assets

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\halo\export.ps1
```

Reads `..\UNSC Weapons\UNSC Weapons.blend` and `..\Covenant Weapons\Covenant Weapons.blend` (the folder above the
repo; `-Source` for another) with Blender in the background, scripts in the scenes off, and writes `build\halo\`:

- `model_export\halo\*.xmodel_export` - one per weapon (`halo_<weapon>_view`) and projectile
- `texture_assets\halo\*.tga`
- `asset_sheet.md` - per weapon: the xmodels, the materials with their textures, the weapon file to make and what to change
- `mod.csv`, `raw\english\localizedstrings\halo.str`
- `report_*.json` - bones, bounds, tag positions, warnings

Check the models (Blender's bundled Python has numpy):

```powershell
& "C:\Program Files\Blender Foundation\Blender 3.2\3.2\python\bin\python.exe" tools\halo\check_xmodel.py build\halo\model_export\halo build\halo\check_sheet.png
```

It validates every file and draws side and top views: muzzle (`tag_flash`) red, grip (`j_gun`) green, magazine
(`tag_clip`) blue. Every weapon points +X. The Spartan Laser's "behind the grip" warning is expected (shoulder-fired).

## 2a. Build mod.ff with OpenAssetTools (no mod tools)

[OpenAssetTools](https://github.com/Laupetin/OpenAssetTools) (OAT) builds Black Ops fastfiles: its Linker writes the
`IWffu100` version 473 header this engine loads (src/database/db_file_load.cpp). For Black Ops it builds xmodels
from glTF, materials from JSON, weapons from weapon files, `.str` strings, scripts, and image headers whose pixels
the game loads from `images/<name>.iwi` in an `.iwd`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\halo\build_ff.ps1 [-Game <Black Ops folder>] [-Only magnum]
```

`-Game` defaults to `build\Release` (setup.ps1's copy of the game). The build reads its `zone\Common\common_zombie.ff`,
which every zombie map loads, with OAT's Unlinker into `build\halo\retail\` (local, never committed): the donor
weapons' files and AI accuracy graphs, the M1911's material and the zone's asset list. `-NoGame` builds without the
game files: plain M1911 material, weapons with no animations, sounds or effects, no textures.

1. **Models:** `tools\halo\xmodel_to_gltf.py` turns each `.xmodel_export` into a `.glb` plus OAT's
   `xmodel/<name>.json`, in inches with OAT's axes (glTF Y up), bones and weights kept, faces the way the normals
   point, each surface on its own material `mc/mtl_halo_*`. Checked by importing the `.glb` into Blender: bones,
   bounds and every face's direction match the export. The root bone is `j_gun`, as on every stock view model (the
   bone the stock animations move and the hands' `tag_weapon` holds); the Halo slide is `j_bolt`, the magazine
   `tag_clip` (weapons.json "rootBone" / "boneMap").
2. **Materials and textures:** `tools\halo\make_materials.py` copies the M1911's material (`mc/mtl_t5_weapon_m1911_mp`:
   technique set `mc_l_sm_r0c0n0s0_wpn_clrdtl_hero` and its render-state tables) once per Halo material and swaps in
   the Halo colour map, the Halo normal map (or the stock flat one) and a shared dull specular map. It writes the
   textures as `.iwi` (format 13, as the retail ones in `main\iw_*.iwd`): colour DXT1, normals DXT5 with X in alpha and
   Y in red, green and blue (the retail layout), mip-mapped. `tools\halo\pack_iwd.py` zips them into `halo.iwd`.
   Checked by decoding the Magnum's back: about 2 of 255 off on average, nothing flipped.
3. **Weapons:** `tools\halo\make_weapons.py --donors` starts each weapon as its weapons.json "donor"'s file (its
   animations, sounds, effects, hands and, for launchers, the Halo projectile model) and sets the Halo model, name
   and weapons.json's clip, ammo, damage and fire time; `_upgraded_zm` doubles the damage. A weapon file needs every
   one of its 748 keys (OAT leaves a missing one a null pointer the engine reads), listed in
   `tools\halo\weapon_fields_t5.json` (from OAT's own field table).
4. **References:** everything taken from the game (the technique set, the stock images, the donors' animations,
   effects, hands and HUD icons) is listed under `ignore,halo_retail`, every asset of `common_zombie.ff`, so `mod.ff`
   refers to the game's copies by name (`,name` entries the engine links to the loaded assets) instead of carrying
   them. Not `$default` as a material: that is the 2D default (the engine swaps it for `$default3d` on models,
   xanim/xmodel_load_obj.cpp); the first test build used it, and its models drew nothing in the world and shards in
   first person.
5. **Diagnostics:** `tools\halo\make_test_models.py` adds `halo_test_cube` (one bone), `halo_test_cube2` (two bones)
   and `halo_magnum_1bone` (the Magnum on its root bone only), on the M1911's material; `/set halo_show test` lines
   them up with the Magnum, each taking a different path through the renderer.
6. **The list:** `maps/halo/_halo_list.gsc`, written into `mod.ff` as a script, names the weapons and models it holds;
   `_halo.gsc` precaches exactly those. The engine reads a script it cannot find on disk from the fastfiles
   (clientscript/cscr_parser.cpp), so this file must not exist in `mods/halo/maps/halo/`.
7. The Linker writes `build\halo\oat\zone_out\mod\mod.ff`; the script copies it and `halo.iwd` to `mods\halo\` (and
   `build\Release\mods\halo\` when that exists). Side-loading means both files and the scripts.

In game: buy spots appear around your spawn, each with its weapon's model spinning over it (`halo_buy_free 1` makes
them free). `/set halo_show magnum` spins a model in front of you (`all`, `test`, `clear`). Held, a gun moves with its
donor's animations; where it sits in the hand depends on where the Halo rig's root is, so some may need an offset.

## 2. Build mod.ff with the Black Ops mod tools

The mod tools (Steam, "Call of Duty: Black Ops - Mod Tools") install into the game folder: they need the PC game
installed. With them installed, ask Claude to check the assumptions marked below against the tools' raw scripts and
asset formats; nothing here has been through the tools yet.

1. Copy `build\halo\model_export\halo` into the game's `model_export\`, `texture_assets\halo` into `texture_assets\`,
   and `raw\english\localizedstrings\halo.str` into `raw\english\localizedstrings\`.
2. In the Asset Manager, per `asset_sheet.md`:
   - materials (`mtl_halo_*`): a model material with the colour map, plus the normal map where listed;
   - xmodels: `halo_<weapon>_view` from its `.xmodel_export` (type animated), and `halo_<weapon>_world` from the
     same file; projectiles as rigid xmodels;
   - weapons: duplicate the donor weapon (`weapons.json` "donor"), rename it `halo_<weapon>_zm`, set the view and
     world models (and the projectile model), then the clip / ammo / damage / fire time the sheet lists. The same
     for `halo_<weapon>_upgraded_zm` from the donor's upgraded weapon (Pack-a-Punch).
3. Copy `build\halo\mod.csv` to the mod tools' `mods\halo\` and build the mod (Launcher, Mod Builder, "halo").
4. Copy the built `mod.ff` (and any `.iwd`) into this repo's `mods\halo\`; the build copies `mods\` next to the exe.

Things to check in the tools on the first weapon (the Magnum is a good first one):

- The donor's animations move `tag_clip` / `j_bolt`: if the magazine or slide stays still, rename the bone in
  `weapons.json` "boneMap" to the donor's (the Asset Viewer lists an xanim's bones) and export again.
- Inside-out faces: set `"flipWinding": false` in `weapons.json` and export again.
- Bumps lit from the wrong side: set `"normalFlipGreen": true`.
- Sights: the Halo gun sits where the donor's did, so aiming down sights needs the view-model offsets adjusted per weapon.

## 3. Play

```powershell
.\BO1Zombies.exe ... +set fs_game mods/halo +set fs_mods "halo" +devmap zombie_theater
```

- `fs_game mods/halo`: the engine reads `mod.ff` only from the `fs_game` folder, so this cannot be combined with
  another mod that sets its own `fs_game` (horde, mapkit, nightmare) until the engine reads every stacked mod's `mod.ff`.
- `fs_mods "halo"` (or `"zinfo halo resume"`): runs `maps/halo/_hooks.gsc`.
- The log (`games_mp.log`) says `halo: 22 of 22 weapons and 29 models in mod.ff` and where the buy spots went.
- Buy spots: `halo_buys 0` turns them off, `halo_buy_free 1` makes them free.
- `/set halo_give magnum` (or any weapon's full name) gives player 1 that weapon.
- `halo_box 1` also puts the weapons in the Mystery Box and the retail wall-buy tables. It is off by default because
  it assumes the retail signatures `include_zombie_weapon( weapon_name, in_box )` and
  `add_zombie_weapon( weapon_name, upgrade_name, hint, cost )` of `maps\_zombiemode_weapons`; check them against the
  mod tools' `raw\maps\_zombiemode_weapons.gsc` first.

## Files

- `maps/halo/_hooks.gsc` - registers `main_end` with mods/_stack's `_zombiemode_ffotd` hook.
- `maps/halo/_halo.gsc` - the weapon list, the buy spots, the optional registration, `halo_give` and `halo_show`.
- `mod.ff`, `halo.iwd` (built, not in the repository) - the models, materials, weapons and
  `maps/halo/_halo_list.gsc`; the textures.
- `tools/halo/weapons.json` - every weapon: source rig, donor, stats, status and notes; the bone renames.
- `tools/halo/export_halo.py`, `tools/halo/export.ps1` - the Blender export.
- `tools/halo/check_xmodel.py` - the checker and contact sheet.
- `tools/halo/build_ff.ps1` with `xmodel_to_gltf.py`, `make_materials.py`, `make_weapons.py`,
  `weapon_fields_t5.json`, `make_test_models.py`, `pack_iwd.py` - `mod.ff` and `halo.iwd` with OpenAssetTools
  (section 2a).
