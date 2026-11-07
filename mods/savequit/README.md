# savequit - Save & Quit (NOT part of the original game)

Lets you save a zombies game, quit, and continue it later from the **start of the round you saved in**.

## Use it

- In `tools\mod-launcher.hta`, keep **Save & Quit with F5** ticked (it is on by default) and play.
- In game, press **F5**. The game shows "Press F5 again to Save & Quit". Press it again within 4 seconds: the game
  saves and goes back to the main menu.
- To continue, pick the same map (and the same options) in the launcher, tick **Continue saved game** and press Play.
  The launcher only enables that box when the map has a save.

You can't save while a player is down or after game over. A save can only be loaded once: loading it renames the
file to `<map>.loaded`, so it won't show up as a save again.

Command line, without the launcher: `+set fs_mods "... savequit" +set bo1_mod_savequit 1` to enable it, plus
`+set savequit_load 1` to continue. Put `savequit` last in `fs_mods` so the round it restores overrides
`horde_start_round`.

## What is saved

| saved | not saved |
| --- | --- |
| round number (with the speed and spawn delay that round has, as `horde_start_round` does) | zombies alive, the round's progress |
| points of every player | power-ups on the ground, double points / insta-kill timers |
| primary weapons with clip and stock ammo, Pack-a-Punched included | Bowie knife / sickle (melee weapons) |
| grenades, claymores, monkey bombs and other offhand items | Mystery Box location, fire sale |
| perks (bought again from their machines, for free) | map quests and easter eggs, Five's DEFCON, Kino's teleporter |
| doors, airlocks and debris opened | |
| power on | |

While a game loads, zombie spawning is paused and the players can't be hurt. Each perk is bought from its own
machine, so the drinking animation plays once per perk; spawning starts again when that's done.

## Settings

- `bo1_mod_savequit 0/1` - engine: turns the key and the `bo1_savequit` command on (the launcher sets it).
- `bo1_mod_savequit_key F5` - the save key (any key name `bind` accepts).
- `bo1_savequit` - console command, the same as pressing the key.
- `savequit_desktop 1` - quit to the desktop instead of the main menu.
- `savequit_load 1` - load this map's save at the start.

## Where the save file lives

`build\Release\savequit\<map>.txt` (`<fs_homepath>\savequit`), with `_<layout>` added for mapkit maps. It sits
outside the `fs_game` / `fs_mods` folders, so the launcher finds it whatever mods were loaded. It's a plain
`key=value` text file. The file also records the mod list it was saved with. If you load it with different mods,
it still loads and writes a warning to the log.

## How it works

- `maps/savequit/_hooks.gsc` registers `main_end` on the shared `_zombiemode_ffotd::main_end` hook
  (`mods/_stack/maps/_modstack.gsc`).
- `maps/savequit/_savequit.gsc` does the work:
  - At level start it lists every door and debris trigger.
  - When you save, it writes out the state.
  - When you load, it sets the round number in `main_end`, before `round_start()`, the way `horde_start_round`
    does. After `begin_spawning` it restores the power, doors (with their own triggers, free under
    `zombie_unlock_all`), perks (from their machines), weapons, and points last.
- Engine half: `src/game_sp/g_sp_savequit.cpp`. It handles the key (hooked in `CL_KeyEvent` next to
  `bo1_mod_quickrestart`) and the `bo1_savequit` command, and adds the script builtins `bo1_savequit_write`,
  `bo1_savequit_read`, `bo1_savequit_retire` and `bo1_savequit_exit`.
- It doesn't use the engine's own SP savegame (`g_sp_savegame.cpp`). That one only saves to memory, and its
  load path isn't fully ported yet.

Log lines (`games_mp.log`): `savequit: save ...`, `savequit: load ...`, `savequit: restore ...`.
