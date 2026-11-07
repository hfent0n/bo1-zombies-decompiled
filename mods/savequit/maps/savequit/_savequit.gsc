#include maps\_utility;
#include common_scripts\utility;
#include maps\_zombiemode_utility;

// SAVEQUIT MOD - not part of the original game. Save & Quit at round granularity: the saved game is the round number,
// every player's points, weapons (with ammo), offhand items and perks, the doors and debris opened and the power. A
// loaded game starts at the beginning of the saved round with that state; zombies, power-ups, the box location, map
// quests and timers are not saved.
//
// Save: press bo1_mod_savequit_key (default F5) twice within 4 s in game (or the console command bo1_savequit twice).
//   The engine raises bo1_savequit_request (src/game_sp/g_sp_savequit.cpp), this script writes
//   build\Release\savequit\<map>.txt with bo1_savequit_write and leaves to the main menu (savequit_desktop 1: desktop).
//   No save while a player is down or after game over.
// Load: start the same map with +set savequit_load 1 (the launcher's "Continue saved game"). The file is renamed to
//   <map>.loaded once read, so a save is used once.
// Log (games_mp.log): "savequit: ..." lines.

main_end()
{
	level.savequit_name = savequit_name();
	savequit_cache_doors();
	level thread savequit_watch();
	if ( GetDvarInt( #"savequit_load" ) == 1 )
	{
		savequit_load();
	}
}


// the file name: the map, plus the mapkit layout (every kit map is zombie_pentagon underneath)
savequit_name()
{
	name = ToLower( GetDvar( #"mapname" ) );
	layout = GetDvar( #"bo1_mod_mapkit" );
	if ( layout != "" && layout != "0" )
	{
		name = name + "_" + layout;
	}
	return name;
}


savequit_log( msg )
{
	LogPrint( "savequit: " + msg + "\n" );
}


//-------------------------------------------------------------------------------
// the request key
//-------------------------------------------------------------------------------

savequit_watch()
{
	SetDvar( "bo1_savequit_request", "0" );
	last_press = -100000;
	for ( ;; )
	{
		wait( .1 );
		if ( GetDvarInt( #"bo1_savequit_request" ) <= 0 )
		{
			continue;
		}
		SetDvar( "bo1_savequit_request", "0" );
		key = GetDvar( #"bo1_mod_savequit_key" );
		if ( key == "" )
		{
			key = "the save key";
		}
		reason = savequit_cannot_save();
		if ( reason != "" )
		{
			IPrintLnBold( "Cannot save now: " + reason );
			savequit_log( "save refused: " + reason );
			last_press = -100000;
			continue;
		}
		if ( GetTime() - last_press > 4000 )
		{
			last_press = GetTime();
			IPrintLnBold( "Press " + key + " again to Save & Quit" );
			continue;
		}
		if ( savequit_save() )
		{
			IPrintLnBold( "Game saved" );
			wait( 1 );
			bo1_savequit_exit( GetDvarInt( #"savequit_desktop" ) );
			return;
		}
		IPrintLnBold( "Save failed (see the log)" );
		last_press = -100000;
	}
}


// "" when a save is allowed now
savequit_cannot_save()
{
	if ( is_true( level.intermission ) )
	{
		return "the game is over";
	}
	if ( is_true( level.savequit_restoring ) )
	{
		return "the saved game is still loading";
	}
	if ( !IsDefined( level.round_number ) )
	{
		return "the game has not started";
	}
	players = get_players();
	if ( players.size == 0 )
	{
		return "no players";
	}
	for ( i = 0; i < players.size; i++ )
	{
		if ( !is_player_valid( players[i] ) )
		{
			return "a player is down";
		}
	}
	return "";
}


//-------------------------------------------------------------------------------
// doors: every door / airlock / debris trigger, as the level starts (before any is opened)
//-------------------------------------------------------------------------------

savequit_cache_doors()
{
	level.savequit_door_ents = [];
	level.savequit_door_keys = [];
	level.savequit_door_origins = [];
	names = array( "zombie_door", "zombie_airlock_buy", "zombie_debris" );
	for ( k = 0; k < names.size; k++ )
	{
		ents = GetEntArray( names[k], "targetname" );
		for ( i = 0; i < ents.size; i++ )
		{
			n = level.savequit_door_ents.size;
			level.savequit_door_ents[n] = ents[i];
			level.savequit_door_origins[n] = ents[i].origin;
			level.savequit_door_keys[n] = names[k] + "@" + savequit_origin_key( ents[i].origin );
		}
	}
}


savequit_origin_key( o )
{
	return int( o[0] ) + "_" + int( o[1] ) + "_" + int( o[2] );
}


// a door with script_flag is open when all its flags are set (door_think / debris_think set them). One without: its
// trigger was deleted or moved away (trigger_off) since the level started.
savequit_door_is_open( i )
{
	ent = level.savequit_door_ents[i];
	if ( !IsDefined( ent ) )
	{
		return true;
	}
	if ( IsDefined( ent.script_flag ) && ent.script_flag != "" )
	{
		flags = StrTok( ent.script_flag, "," );
		for ( f = 0; f < flags.size; f++ )
		{
			if ( !savequit_flag( flags[f] ) )
			{
				return false;
			}
		}
		return flags.size > 0;
	}
	return ent.origin != level.savequit_door_origins[i];
}


// flag() without its assert on a flag the map never initialised
savequit_flag( name )
{
	return IsDefined( level.flag ) && IsDefined( level.flag[name] ) && level.flag[name];
}


//-------------------------------------------------------------------------------
// save
//-------------------------------------------------------------------------------

savequit_skip_weapon( w )
{
	if ( w == "none" || w == "" )
	{
		return true;
	}
	// transient (perk bottle, revive syrette, knuckle crack, Death Machine power-up) and melee weapons, which retail
	// gives through its own flows
	skip = array( "perk_bottle", "syrette", "knuckle", "flourish", "minigun", "knife", "fists", "melee" );
	for ( i = 0; i < skip.size; i++ )
	{
		if ( IsSubStr( w, skip[i] ) )
		{
			return true;
		}
	}
	return false;
}


savequit_save()
{
	lines = [];
	lines[lines.size] = "version=1";
	lines[lines.size] = "map=" + level.savequit_name;
	lines[lines.size] = "mods=" + GetDvar( #"fs_mods" );
	lines[lines.size] = "round=" + level.round_number;
	power = 0;
	if ( savequit_flag( "power_on" ) )
	{
		power = 1;
	}
	lines[lines.size] = "power=" + power;

	doors = "";
	opened = 0;
	for ( i = 0; i < level.savequit_door_ents.size; i++ )
	{
		if ( savequit_door_is_open( i ) )
		{
			if ( doors != "" )
			{
				doors = doors + "|";
			}
			doors = doors + level.savequit_door_keys[i];
			opened++;
		}
	}
	lines[lines.size] = "doors=" + doors;

	players = get_players();
	lines[lines.size] = "players=" + players.size;
	for ( p = 0; p < players.size; p++ )
	{
		player = players[p];
		pre = "p" + p + ".";
		lines[lines.size] = pre + "score=" + player.score;

		perks = "";
		vending = GetEntArray( "zombie_vending", "targetname" );
		for ( i = 0; i < vending.size; i++ )
		{
			perk = vending[i].script_noteworthy;
			if ( IsDefined( perk ) && ( player HasPerk( perk ) ) && !IsSubStr( "|" + perks + "|", "|" + perk + "|" ) )
			{
				if ( perks != "" )
				{
					perks = perks + "|";
				}
				perks = perks + perk;
			}
		}
		lines[lines.size] = pre + "perks=" + perks;

		primaries = player GetWeaponsListPrimaries();
		list = "";
		for ( i = 0; i < primaries.size; i++ )
		{
			w = primaries[i];
			if ( savequit_skip_weapon( w ) )
			{
				continue;
			}
			if ( list != "" )
			{
				list = list + "|";
			}
			list = list + w + ":" + ( player GetWeaponAmmoClip( w ) ) + ":" + ( player GetWeaponAmmoStock( w ) );
		}
		lines[lines.size] = pre + "weapons=" + list;

		all = player GetWeaponsList();
		list = "";
		for ( i = 0; i < all.size; i++ )
		{
			w = all[i];
			if ( savequit_skip_weapon( w ) || savequit_in_array( primaries, w ) )
			{
				continue;
			}
			if ( list != "" )
			{
				list = list + "|";
			}
			list = list + w + ":" + ( player GetWeaponAmmoClip( w ) ) + ":" + ( player GetWeaponAmmoStock( w ) );
		}
		lines[lines.size] = pre + "offhand=" + list;

		current = player GetCurrentWeapon();
		if ( savequit_skip_weapon( current ) || !savequit_in_array( primaries, current ) )
		{
			current = "";
		}
		lines[lines.size] = pre + "current=" + current;
	}

	text = "";
	for ( i = 0; i < lines.size; i++ )
	{
		text = text + lines[i] + "\n";
	}
	ok = bo1_savequit_write( level.savequit_name, text );
	savequit_log( "save " + level.savequit_name + " round " + level.round_number + ", power " + power + ", doors " + opened + ", players " + players.size + ": " + ok );
	return ok == 1;
}


savequit_in_array( a, v )
{
	for ( i = 0; i < a.size; i++ )
	{
		if ( a[i] == v )
		{
			return true;
		}
	}
	return false;
}


//-------------------------------------------------------------------------------
// load
//-------------------------------------------------------------------------------

// main_end: same frame as the level main, before round_start(), as horde_start_round does it
savequit_load()
{
	text = bo1_savequit_read( level.savequit_name );
	if ( text == "" )
	{
		savequit_log( "load " + level.savequit_name + ": no saved game" );
		level thread savequit_message( "No saved game for this map: a new game starts" );
		return;
	}
	data = [];
	lines = StrTok( text, "\n" );
	for ( i = 0; i < lines.size; i++ )
	{
		line = lines[i];
		parts = StrTok( line, "=" );
		if ( parts.size == 0 )
		{
			continue;
		}
		if ( parts.size == 1 )
		{
			data[parts[0]] = "";
		}
		else
		{
			data[parts[0]] = parts[1];
		}
	}
	if ( !IsDefined( data["version"] ) || data["version"] != "1" || !IsDefined( data["round"] ) )
	{
		savequit_log( "load " + level.savequit_name + ": unreadable save, ignored" );
		level thread savequit_message( "The saved game could not be read: a new game starts" );
		return;
	}
	if ( IsDefined( data["mods"] ) && data["mods"] != GetDvar( #"fs_mods" ) )
	{
		// still loaded: the mods change the rules, not what the save holds
		savequit_log( "load: saved with fs_mods '" + data["mods"] + "', running '" + GetDvar( #"fs_mods" ) + "'" );
	}
	bo1_savequit_retire( level.savequit_name );
	level.savequit_data = data;

	round = int( data["round"] );
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
	}
	savequit_log( "load " + level.savequit_name + ": round " + round );
	level.savequit_restoring = true;
	level thread savequit_restore();
}


savequit_message( msg )
{
	flag_wait( "begin_spawning" );
	wait( 1 );
	IPrintLnBold( msg );
}


savequit_restore()
{
	data = level.savequit_data;
	flag_wait( "begin_spawning" );
	wait( .5 );

	// no zombies and no damage while the players get their things back (perk bottles take a few seconds each)
	spawning = savequit_flag( "spawn_zombies" );
	if ( spawning )
	{
		flag_clear( "spawn_zombies" );
	}
	players = get_players();
	for ( p = 0; p < players.size; p++ )
	{
		players[p] EnableInvulnerability();
	}

	// power before doors and perks: electric doors and perk machines wait for it
	if ( IsDefined( data["power"] ) && data["power"] == "1" )
	{
		savequit_restore_power( players[0] );
	}
	savequit_restore_doors( players[0], data["doors"] );

	for ( p = 0; p < players.size; p++ )
	{
		player = players[p];
		pre = "p" + p + ".";
		if ( !IsDefined( data[pre + "score"] ) )
		{
			savequit_log( "restore: no saved player " + p );
			continue;
		}
		savequit_restore_perks( player, data[pre + "perks"] );
		savequit_restore_weapons( player, data[pre + "weapons"], data[pre + "offhand"], data[pre + "current"] );
		// points last: the perk machines above charged their price
		player maps\_zombiemode_score::add_to_player_score( int( data[pre + "score"] ) - player.score );
		savequit_log( "restore player " + p + ": score " + player.score );
	}

	wait( 1 );
	players = get_players();
	for ( p = 0; p < players.size; p++ )
	{
		players[p] DisableInvulnerability();
	}
	if ( spawning )
	{
		flag_set( "spawn_zombies" );
	}
	level.savequit_restoring = undefined;
	IPrintLnBold( "Saved game loaded: round " + level.round_number );
	savequit_log( "restore done, round " + level.round_number );
}


// the way the retail switch does it (as horde_power_on / sandbox_power_on)
savequit_restore_power( player )
{
	if ( savequit_flag( "power_on" ) )
	{
		return;
	}
	trig = GetEnt( "use_elec_switch", "targetname" );
	if ( !IsDefined( trig ) )
	{
		savequit_log( "restore power: no use_elec_switch on this map" );
		return;
	}
	trig notify( "trigger", player );
	for ( t = 0; t < 100 && !savequit_flag( "power_on" ); t++ )
	{
		wait( .1 );
	}
	savequit_log( "restore power: power_on " + savequit_flag( "power_on" ) );
}


// the doors' own buy triggers, free while zombie_unlock_all is set (as sandbox_open_sesame)
savequit_restore_doors( player, list )
{
	if ( !IsDefined( list ) || list == "" )
	{
		return;
	}
	keys = StrTok( list, "|" );
	SetDvar( "zombie_unlock_all", 1 );
	n = 0;
	for ( i = 0; i < level.savequit_door_ents.size; i++ )
	{
		if ( !savequit_in_array( keys, level.savequit_door_keys[i] ) )
		{
			continue;
		}
		ent = level.savequit_door_ents[i];
		if ( !IsDefined( ent ) || savequit_door_is_open( i ) )
		{
			continue; // opened with another trigger of the same door
		}
		ent notify( "trigger", player );
		n++;
		wait( .05 );
	}
	wait( 1 );
	SetDvar( "zombie_unlock_all", 0 );
	savequit_log( "restore doors: " + n + " triggers of " + keys.size + " saved" );
}


// each perk from its machine (as zombie_devgui_give_perk / the sandbox perk pads): the retail bottle, HUD and effects
savequit_restore_perks( player, list )
{
	if ( !IsDefined( list ) || list == "" )
	{
		return;
	}
	perks = StrTok( list, "|" );
	vending = GetEntArray( "zombie_vending", "targetname" );
	for ( k = 0; k < perks.size; k++ )
	{
		perk = perks[k];
		if ( player HasPerk( perk ) )
		{
			continue;
		}
		machine = undefined;
		for ( i = 0; i < vending.size; i++ )
		{
			if ( IsDefined( vending[i].script_noteworthy ) && vending[i].script_noteworthy == perk )
			{
				machine = vending[i];
				break;
			}
		}
		if ( !IsDefined( machine ) )
		{
			savequit_log( "restore perk " + perk + ": no machine on this map" );
			continue;
		}
		if ( player.score < 10000 )
		{
			player maps\_zombiemode_score::add_to_player_score( 10000 );
		}
		for ( t = 0; t < 40 && ( player IsSwitchingWeapons() || is_true( player.is_drinking ) ); t++ )
		{
			wait( .25 );
		}
		machine notify( "trigger", player );
		for ( t = 0; t < 60 && !( player HasPerk( perk ) ); t++ )
		{
			wait( .25 );
		}
		for ( t = 0; t < 40 && IsDefined( player.perk_purchased ); t++ )
		{
			wait( .25 );
		}
		savequit_log( "restore perk " + perk + ": " + ( player HasPerk( perk ) ) );
		wait( .25 );
	}
}


savequit_restore_weapons( player, primaries, offhand, current )
{
	for ( t = 0; t < 40 && ( player IsSwitchingWeapons() || is_true( player.is_drinking ) ); t++ )
	{
		wait( .25 );
	}
	saved = [];
	if ( IsDefined( primaries ) && primaries != "" )
	{
		entries = StrTok( primaries, "|" );
		for ( i = 0; i < entries.size; i++ )
		{
			f = StrTok( entries[i], ":" );
			w = f[0];
			saved[saved.size] = w;
			if ( !( player HasWeapon( w ) ) )
			{
				if ( IsSubStr( w, "upgraded" ) )
				{
					player GiveWeapon( w, 0, player maps\_zombiemode_weapons::get_pack_a_punch_weapon_options( w ) );
				}
				else
				{
					player GiveWeapon( w );
				}
			}
			savequit_set_ammo( player, w, f );
		}
	}
	// the start pistol (and any other gun not in the save) goes, once the saved ones are in hand
	if ( saved.size > 0 )
	{
		have = player GetWeaponsListPrimaries();
		for ( i = 0; i < have.size; i++ )
		{
			if ( !savequit_in_array( saved, have[i] ) && !savequit_skip_weapon( have[i] ) )
			{
				player TakeWeapon( have[i] );
			}
		}
	}
	if ( IsDefined( offhand ) && offhand != "" )
	{
		entries = StrTok( offhand, "|" );
		for ( i = 0; i < entries.size; i++ )
		{
			f = StrTok( entries[i], ":" );
			w = f[0];
			if ( !( player HasWeapon( w ) ) )
			{
				// the box's give: claymores, monkey bombs and the other action-slot items get their slot and watcher
				player maps\_zombiemode_weapons::weapon_give( w );
				wait( .1 );
			}
			savequit_set_ammo( player, w, f );
		}
	}
	if ( IsDefined( current ) && current != "" && player HasWeapon( current ) )
	{
		player SwitchToWeapon( current );
	}
	else if ( saved.size > 0 && player HasWeapon( saved[0] ) )
	{
		player SwitchToWeapon( saved[0] );
	}
	savequit_log( "restore weapons: " + saved.size + " primaries, current " + ( player GetCurrentWeapon() ) );
}


// f = [ name, clip, stock ]
savequit_set_ammo( player, w, f )
{
	if ( !( player HasWeapon( w ) ) )
	{
		savequit_log( "restore weapon " + w + ": not given" );
		return;
	}
	if ( f.size > 1 )
	{
		player SetWeaponAmmoClip( w, int( f[1] ) );
	}
	if ( f.size > 2 )
	{
		player SetWeaponAmmoStock( w, int( f[2] ) );
	}
}
