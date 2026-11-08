// CHECKPOINT MOD - not part of the original game. Written into the vel.gg pack by the vel.gg Checkpoints browser
// extension (tools/velgg-checkpoints) and started with +set fs_mods "... checkpoint". mods/_stack/maps/_modstack.gsc.
// Last in fs_mods: its main_end then runs after the other mods' (horde's horde_start_round included), so a loaded
// checkpoint's round wins.

register()
{
	maps\_modstack::add( "_zombiemode_ffotd::main_end", maps\checkpoint\_checkpoint::main_end );
}
