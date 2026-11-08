#include maps\_utility;
#include common_scripts\utility;
#include maps\_zombiemode_utility;

// TWEAKS MOD - not part of the original game. Game settings from the vel.gg Checkpoints extension's mod menu:
//   tweaks_start_round  N > 1: the game starts at round N (as horde_start_round does)
//   tweaks_start_points N > 0: every player starts with N points instead of 500
//   tweaks_power        1: the power is on from the start (the map's own switch)
//   tweaks_third_person 1: third-person camera for every player (also while a checkpoint loads)
// Nothing happens while a checkpoint is being loaded (cp_load 1): the checkpoint's own state wins. The checkpoint mod
// comes after this one in fs_mods, so its main_end still sees cp_load 1 here.

main_end()
{
	// a camera setting, not game state: applies when a checkpoint loads too
	if ( GetDvarInt( #"tweaks_third_person" ) == 1 )
	{
		level thread tweaks_third_person();
	}
	if ( GetDvarInt( #"cp_load" ) == 1 )
	{
		return;
	}
	round = GetDvarInt( #"tweaks_start_round" );
	if ( round > 1 )
	{
		// as horde_start_round (mods/horde/maps/horde/_horde.gsc): first_round false, round_number before round_start(),
		// plus what rounds 1..N-1 would have done to move speed and the spawn delay (retail round_think)
		level.first_round = false;
		level.round_number = round;
		level.zombie_move_speed = level.round_number * level.zombie_vars["zombie_move_speed_multiplier"];
		for ( i = 1; i < level.round_number; i++ )
		{
			timer = level.zombie_vars["zombie_spawn_delay"];
			if ( timer > 0.08 )
				level.zombie_vars["zombie_spawn_delay"] = timer * 0.95;
			else if ( timer < 0.08 )
				level.zombie_vars["zombie_spawn_delay"] = 0.08;
		}
		LogPrint( "tweaks: start round " + round + "\n" );
	}
	points = GetDvarInt( #"tweaks_start_points" );
	if ( points > 0 )
	{
		level thread tweaks_points( points );
	}
	if ( GetDvarInt( #"tweaks_power" ) == 1 )
	{
		level thread tweaks_power();
	}
}


// every player once, including co-op friends who are still connecting during the first minute
tweaks_points( points )
{
	flag_wait( "begin_spawning" );
	wait( .5 );
	for ( t = 0; t < 120; t++ )
	{
		players = get_players();
		for ( p = 0; p < players.size; p++ )
		{
			if ( is_true( players[p].tweaks_points_done ) )
			{
				continue;
			}
			players[p].tweaks_points_done = true;
			players[p] maps\_zombiemode_score::add_to_player_score( points - players[p].score );
			LogPrint( "tweaks: start points " + points + " for player " + p + "\n" );
		}
		wait( .5 );
	}
}


// tweaks_third_person 1: every player's camera behind them (cg_thirdPerson, a cheat-flagged client dvar, which a
// script may set with SetClientDvar). Set again every 2 s, so it survives what resets it (last stand, spectating) and
// reaches co-op friends who join late.
tweaks_third_person()
{
	level endon( "end_game" );
	flag_wait( "all_players_spawned" );
	LogPrint( "tweaks: third person\n" );
	for ( ;; )
	{
		players = get_players();
		for ( p = 0; p < players.size; p++ )
		{
			players[p] SetClientDvar( "cg_thirdPerson", "1" );
		}
		wait( 2 );
	}
}


// the way the retail switch does it (as horde_power_on / sandbox_power_on)
tweaks_power()
{
	flag_wait( "begin_spawning" );
	wait( .5 );
	if ( IsDefined( level.flag ) && IsDefined( level.flag["power_on"] ) && level.flag["power_on"] )
	{
		return;
	}
	trig = GetEnt( "use_elec_switch", "targetname" );
	if ( !IsDefined( trig ) )
	{
		LogPrint( "tweaks: power: no use_elec_switch on this map\n" );
		return;
	}
	trig notify( "trigger", get_players()[0] );
	LogPrint( "tweaks: power switched on\n" );
}
