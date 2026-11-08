// TWEAKS MOD - not part of the original game. Written into the vel.gg pack by the vel.gg Checkpoints browser
// extension's mod menu and started with +set fs_mods "... tweaks checkpoint". mods/_stack/maps/_modstack.gsc.

register()
{
	maps\_modstack::add( "_zombiemode_ffotd::main_end", maps\tweaks\_tweaks::main_end );
}
