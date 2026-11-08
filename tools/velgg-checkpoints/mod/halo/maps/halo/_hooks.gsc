// HALO MOD - not part of the original game. Halo Reach weapons (mods/halo/README.md). The weapons themselves are in
// mods/halo/mod.ff (tools\halo\build_ff.ps1); load with +set fs_game mods/halo (the engine reads mod.ff from the
// fs_game folder only) and +set fs_mods "... halo" (this hook).

register()
{
	maps\_modstack::add( "_zombiemode_ffotd::main_end", maps\halo\_halo::main_end );
	// vel.gg extension addition: halo_start_weapon (after _halo::main_end, which fills level.halo_weapons)
	maps\_modstack::add( "_zombiemode_ffotd::main_end", maps\halo\_halo_start::main_end );
}
