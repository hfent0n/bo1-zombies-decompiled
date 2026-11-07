// SAVEQUIT MOD - not part of the original game. With +set fs_mods "... savequit" +set bo1_mod_savequit 1: Save & Quit
// (maps\savequit\_savequit.gsc; engine half src/game_sp/g_sp_savequit.cpp). mods/_stack/maps/_modstack.gsc.
// Put savequit last in fs_mods: its main_end then runs after the other mods' (horde's horde_start_round included), so a
// loaded save's round wins.

register()
{
	maps\_modstack::add( "_zombiemode_ffotd::main_end", maps\savequit\_savequit::main_end );
}
