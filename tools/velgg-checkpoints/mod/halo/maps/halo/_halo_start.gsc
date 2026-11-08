#include maps\_utility;
#include common_scripts\utility;
#include maps\_zombiemode_utility;

// HALO MOD addition (vel.gg extension, not in the friend's build): a Halo gun instead of the starting pistol.
//   halo_start_weapon <id>   "magnum", "assault_rifle", ... (maps\halo\_halo.gsc's ids), "" = the retail pistol
// Whenever a player holds the retail start pistol (m1911_zm) and is not down, it is swapped for that Halo gun with
// full ammo. That covers the start, and the pistol a bled-out player gets back when they respawn. The Pack-a-Punched
// pistol (m1911_upgraded_zm) and a downed player's last-stand pistol are left alone.
// Runs after maps\halo\_halo::main_end (registered after it), so level.halo_weapons is filled in.

main_end()
{
	level thread halo_status();
	// halo_test_models 1: the friend's diagnostic models ("halo_show test") in front of player 1 once the game starts.
	// The browser has no console to type /set halo_show test, and _halo::main_end clears halo_show at the start.
	if ( GetDvarInt( #"halo_test_models" ) == 1 )
	{
		level thread halo_test_models();
	}
	id = GetDvar( #"halo_start_weapon" );
	if ( id == "" || id == "0" || !IsDefined( level.halo_weapons ) )
	{
		return;
	}
	w = maps\halo\_halo::halo_find_weapon( id );
	if ( !IsDefined( w ) )
	{
		maps\halo\_halo::halo_log( "halo_start_weapon " + id + ": not in mod.ff, the retail pistol stays" );
		return;
	}
	level thread halo_start_watch( w );
}


// a status line for the extension's popup, kept in level.halo_status_line and refreshed every 2 s (the extension reads
// it out of the engine's memory: ~cP9S|<seq>|<text>|~cE, as the checkpoint strings). No line at all means these
// scripts never ran.
halo_status()
{
	level endon( "end_game" );
	for ( ;; )
	{
		loaded = 0;
		for ( i = 0; i < level.halo_weapons.size; i++ )
		{
			if ( level.halo_weapons[i].loaded )
			{
				loaded++;
			}
		}
		buys = 0;
		trigs = GetEntArray( "trigger_radius_use", "classname" );
		for ( i = 0; i < trigs.size; i++ )
		{
			if ( IsDefined( trigs[i].weapon ) && IsDefined( trigs[i].display ) )
			{
				buys++;
			}
		}
		text = "halo: weapons " + loaded + "/" + level.halo_weapons.size + ", models " + level.halo_models.size + ", buy spots " + buys;
		text = text + ", start " + GetDvar( #"halo_start_weapon" );
		players = get_players();
		if ( players.size > 0 )
		{
			text = text + ", player 1 holds " + players[0] GetCurrentWeapon();
		}
		// the halo_show models (maps\halo\_halo::halo_show_watch): how many exist, and the first one's distance
		if ( IsDefined( level.halo_shown ) && level.halo_shown.size > 0 )
		{
			text = text + ", test models shown " + level.halo_shown.size;
			if ( players.size > 0 && IsDefined( level.halo_shown[0] ) )
			{
				text = text + ", first " + level.halo_shown[0].model + " " + int( Distance( players[0].origin, level.halo_shown[0].origin ) ) + " units away";
			}
		}
		else if ( GetDvarInt( #"halo_test_models" ) == 1 )
		{
			text = text + ", test models shown 0";
		}
		level.halo_status_line = "~c" + "P9S|" + GetTime() + "|" + text + "|~c" + "E";
		wait( 2 );
	}
}


// every 15 s again, so the row is always in front of where player 1 looks now (halo_show_watch deletes the old row
// and places the new one 50-80 units ahead at chest height)
halo_test_models()
{
	level endon( "end_game" );
	flag_wait( "all_players_spawned" );
	wait( 3 );
	for ( ;; )
	{
		SetDvar( "halo_show", "test" ); // maps\halo\_halo::halo_show_watch picks it up within 0.5 s
		maps\halo\_halo::halo_log( "halo_test_models: halo_show test" );
		wait( 15 );
	}
}


halo_start_watch( w )
{
	level endon( "end_game" );
	flag_wait( "all_players_spawned" );
	maps\halo\_halo::halo_log( "start weapon " + w.name );
	for ( ;; )
	{
		players = get_players();
		for ( p = 0; p < players.size; p++ )
		{
			player = players[p];
			if ( !IsAlive( player ) || player maps\_laststand::player_is_in_laststand() || !( player HasWeapon( "m1911_zm" ) ) )
			{
				continue;
			}
			if ( player IsSwitchingWeapons() )
			{
				continue; // next pass: taking a gun mid-switch can leave empty hands
			}
			player TakeWeapon( "m1911_zm" );
			player maps\halo\_halo::halo_take( w );
			maps\halo\_halo::halo_log( "start weapon: player " + p + " now has " + player GetCurrentWeapon() );
		}
		wait( 0.5 );
	}
}
