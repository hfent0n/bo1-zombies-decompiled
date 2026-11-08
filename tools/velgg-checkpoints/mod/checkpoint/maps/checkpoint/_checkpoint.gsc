#include maps\_utility;
#include common_scripts\utility;
#include maps\_zombiemode_utility;

// CHECKPOINT MOD - not part of the original game. The script half of the vel.gg Checkpoints browser extension
// (tools/velgg-checkpoints). Based on mods/savequit, but the browser build of the engine has no savequit builtins, so:
//
// Save: every 2 s while every player is up, the game state is kept in a few script strings of the form
//   ~cP9|<game id>|<seq>|<chunk>|<chunks>|<fields>|~cE
//   The extension finds the newest ones in the engine's memory (it never runs any engine code). The marker is built by
//   concatenation so this file's own text never contains it.
// Load: the extension writes mods/checkpoint/checkpoint_load.cfg (set cp_load 1, cp_token, cp_n, cp_0 .. cp_<n-1>, each
//   cp_i one saved chunk's fields) and starts the engine with +exec checkpoint_load.cfg. The game starts at the
//   beginning of the saved round with that state, as Save & Quit does. Once read, ~cP9L|<token>|~cE tells the
//   extension the checkpoint was used.
//
// Saved: round, power, doors and debris opened, every player's points, perks, weapons with ammo and offhand items.
// Not saved: zombies, power-ups, the box location, map quests and timers.
// Co-op: this runs on the host's engine only (the extension adds the mod there); every player is saved, p0 = the
// host, and restored by join order.
// Fields are key=value, joined with '#'. Values never hold '#', '=', '"', '/', ';', '+' or spaces.

main_end()
{
	level.cp_name = cp_name();
	level.cp_gid = "" + RandomInt( 100000 ) + RandomInt( 100000 );
	level.cp_pub = [];
	cp_cache_doors();
	if ( GetDvarInt( #"cp_load" ) == 1 )
	{
		cp_load();
	}
	level thread cp_watch();
}


// the map, plus the mapkit layout (every kit map is zombie_pentagon underneath)
cp_name()
{
	name = ToLower( GetDvar( #"mapname" ) );
	layout = GetDvar( #"bo1_mod_mapkit" );
	if ( layout != "" && layout != "0" )
	{
		name = name + "_" + layout;
	}
	return name;
}


cp_log( msg )
{
	LogPrint( "checkpoint: " + msg + "\n" );
}


//-------------------------------------------------------------------------------
// publishing the state for the extension
//-------------------------------------------------------------------------------

cp_watch()
{
	flag_wait( "begin_spawning" );
	for ( ;; )
	{
		wait( 2 );
		if ( cp_cannot_save() != "" )
		{
			continue;
		}
		cp_publish( cp_fields() );
	}
}


// "" when the state may be saved now
cp_cannot_save()
{
	if ( is_true( level.intermission ) )
	{
		return "the game is over";
	}
	if ( is_true( level.cp_restoring ) )
	{
		return "a checkpoint is still loading";
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


// fields -> chunks of at most ~700 characters, each kept alive in level.cp_pub until the next publish
cp_publish( fields )
{
	chunks = [];
	current = "";
	for ( i = 0; i < fields.size; i++ )
	{
		if ( current != "" && current.size + fields[i].size + 1 > 700 )
		{
			chunks[chunks.size] = current;
			current = "";
		}
		if ( current == "" )
		{
			current = fields[i];
		}
		else
		{
			current = current + "#" + fields[i];
		}
	}
	if ( current != "" )
	{
		chunks[chunks.size] = current;
	}
	seq = GetTime();
	head = "~c" + "P9|" + level.cp_gid + "|" + seq + "|";
	tail = "|~c" + "E";
	pub = [];
	for ( i = 0; i < chunks.size; i++ )
	{
		pub[i] = head + i + "|" + chunks.size + "|" + chunks[i] + tail;
	}
	level.cp_pub = pub;
}


//-------------------------------------------------------------------------------
// doors: every door / airlock / debris trigger, as the level starts (before any is opened)
//-------------------------------------------------------------------------------

cp_cache_doors()
{
	level.cp_door_ents = [];
	level.cp_door_keys = [];
	level.cp_door_origins = [];
	names = array( "zombie_door", "zombie_airlock_buy", "zombie_debris" );
	for ( k = 0; k < names.size; k++ )
	{
		ents = GetEntArray( names[k], "targetname" );
		for ( i = 0; i < ents.size; i++ )
		{
			n = level.cp_door_ents.size;
			level.cp_door_ents[n] = ents[i];
			level.cp_door_origins[n] = ents[i].origin;
			level.cp_door_keys[n] = names[k] + "@" + cp_origin_key( ents[i].origin );
		}
	}
}


cp_origin_key( o )
{
	return int( o[0] ) + "_" + int( o[1] ) + "_" + int( o[2] );
}


// a door with script_flag is open when all its flags are set (door_think / debris_think set them). One without: its
// trigger was deleted or moved away (trigger_off) since the level started.
cp_door_is_open( i )
{
	ent = level.cp_door_ents[i];
	if ( !IsDefined( ent ) )
	{
		return true;
	}
	if ( IsDefined( ent.script_flag ) && ent.script_flag != "" )
	{
		flags = StrTok( ent.script_flag, "," );
		for ( f = 0; f < flags.size; f++ )
		{
			if ( !cp_flag( flags[f] ) )
			{
				return false;
			}
		}
		return flags.size > 0;
	}
	return ent.origin != level.cp_door_origins[i];
}


// flag() without its assert on a flag the map never initialised
cp_flag( name )
{
	return IsDefined( level.flag ) && IsDefined( level.flag[name] ) && level.flag[name];
}


//-------------------------------------------------------------------------------
// the saved fields
//-------------------------------------------------------------------------------

cp_skip_weapon( w )
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


cp_fields()
{
	fields = [];
	fields[fields.size] = "v=1";
	fields[fields.size] = "map=" + level.cp_name;
	fields[fields.size] = "round=" + level.round_number;
	power = 0;
	if ( cp_flag( "power_on" ) )
	{
		power = 1;
	}
	fields[fields.size] = "power=" + power;

	for ( i = 0; i < level.cp_door_ents.size; i++ )
	{
		if ( cp_door_is_open( i ) )
		{
			fields[fields.size] = "d=" + level.cp_door_keys[i];
		}
	}

	players = get_players();
	fields[fields.size] = "players=" + players.size;
	vending = GetEntArray( "zombie_vending", "targetname" );
	for ( p = 0; p < players.size; p++ )
	{
		player = players[p];
		pre = "p" + p + ".";
		fields[fields.size] = pre + "score=" + player.score;

		perks = "";
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
		fields[fields.size] = pre + "perks=" + perks;

		primaries = player GetWeaponsListPrimaries();
		list = "";
		for ( i = 0; i < primaries.size; i++ )
		{
			w = primaries[i];
			if ( cp_skip_weapon( w ) )
			{
				continue;
			}
			if ( list != "" )
			{
				list = list + "|";
			}
			list = list + w + ":" + ( player GetWeaponAmmoClip( w ) ) + ":" + ( player GetWeaponAmmoStock( w ) );
		}
		fields[fields.size] = pre + "weapons=" + list;

		all = player GetWeaponsList();
		list = "";
		for ( i = 0; i < all.size; i++ )
		{
			w = all[i];
			if ( cp_skip_weapon( w ) || cp_in_array( primaries, w ) )
			{
				continue;
			}
			if ( list != "" )
			{
				list = list + "|";
			}
			list = list + w + ":" + ( player GetWeaponAmmoClip( w ) ) + ":" + ( player GetWeaponAmmoStock( w ) );
		}
		fields[fields.size] = pre + "offhand=" + list;

		current = player GetCurrentWeapon();
		if ( cp_skip_weapon( current ) || !cp_in_array( primaries, current ) )
		{
			current = "";
		}
		fields[fields.size] = pre + "current=" + current;
	}
	return fields;
}


cp_in_array( a, v )
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
cp_load()
{
	SetDvar( "cp_load", "0" ); // a map restart starts a new game
	level.cp_ack = "~c" + "P9L|" + GetDvar( #"cp_token" ) + "|~c" + "E";

	data = [];
	doors = [];
	n = GetDvarInt( #"cp_n" );
	for ( c = 0; c < n; c++ )
	{
		fields = StrTok( GetDvar( "cp_" + c ), "#" );
		for ( i = 0; i < fields.size; i++ )
		{
			kv = StrTok( fields[i], "=" );
			if ( kv.size == 0 )
			{
				continue;
			}
			value = "";
			if ( kv.size > 1 )
			{
				value = kv[1];
			}
			if ( kv[0] == "d" )
			{
				doors[doors.size] = value;
			}
			else
			{
				data[kv[0]] = value;
			}
		}
	}
	if ( !IsDefined( data["v"] ) || data["v"] != "1" || !IsDefined( data["round"] ) )
	{
		cp_log( "load " + level.cp_name + ": unreadable checkpoint, ignored" );
		level thread cp_message( "The checkpoint could not be read: a new game starts" );
		return;
	}
	if ( IsDefined( data["map"] ) && data["map"] != level.cp_name )
	{
		cp_log( "load: checkpoint is for " + data["map"] + ", this is " + level.cp_name + ": ignored" );
		level thread cp_message( "That checkpoint is for another map: a new game starts" );
		return;
	}
	level.cp_data = data;
	level.cp_load_doors = doors;

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
	cp_log( "load " + level.cp_name + ": round " + round );
	level.cp_restoring = true;
	level thread cp_restore();
}


cp_message( msg )
{
	flag_wait( "begin_spawning" );
	wait( 1 );
	IPrintLnBold( msg );
}


cp_restore()
{
	data = level.cp_data;
	flag_wait( "begin_spawning" );
	wait( .5 );

	// co-op (web: kisak_coop_players, the host's start count): wait up to 30 s for the saved players who are coming,
	// so a friend still connecting gets their things back too. Players are matched by join order (p0 = the host).
	expected = 1;
	if ( IsDefined( data["players"] ) )
	{
		expected = int( data["players"] );
	}
	coming = GetDvarInt( #"kisak_coop_players" ); // unset (0) in solo: only this player is coming
	if ( coming < 1 )
	{
		coming = 1;
	}
	if ( coming < expected )
	{
		expected = coming;
	}
	for ( t = 0; t < 60 && get_players().size < expected; t++ )
	{
		wait( .5 );
	}

	// no zombies and no damage while the players get their things back (perk bottles take a few seconds each)
	spawning = cp_flag( "spawn_zombies" );
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
		cp_restore_power( players[0] );
	}
	cp_restore_doors( players[0], level.cp_load_doors );

	// every player at once (each one's perk bottles take seconds); at most 2 minutes, in case a player leaves
	level.cp_restore_left = 0;
	for ( p = 0; p < players.size; p++ )
	{
		pre = "p" + p + ".";
		if ( !IsDefined( data[pre + "score"] ) )
		{
			cp_log( "restore: no saved player " + p );
			continue;
		}
		level.cp_restore_left++;
		players[p] thread cp_restore_player( p, data );
	}
	for ( t = 0; t < 240 && level.cp_restore_left > 0; t++ )
	{
		wait( .5 );
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
	level.cp_restoring = undefined;
	IPrintLnBold( "Checkpoint loaded: round " + level.round_number );
	cp_log( "restore done, round " + level.round_number );
}


// self = the player; p = their index in the checkpoint
cp_restore_player( p, data )
{
	pre = "p" + p + ".";
	cp_restore_perks( self, data[pre + "perks"] );
	cp_restore_weapons( self, data[pre + "weapons"], data[pre + "offhand"], data[pre + "current"] );
	// points last: the perk machines above charged their price
	self maps\_zombiemode_score::add_to_player_score( int( data[pre + "score"] ) - self.score );
	cp_log( "restore player " + p + ": score " + self.score );
	level.cp_restore_left--;
}


// the way the retail switch does it (as horde_power_on / sandbox_power_on)
cp_restore_power( player )
{
	if ( cp_flag( "power_on" ) )
	{
		return;
	}
	trig = GetEnt( "use_elec_switch", "targetname" );
	if ( !IsDefined( trig ) )
	{
		cp_log( "restore power: no use_elec_switch on this map" );
		return;
	}
	trig notify( "trigger", player );
	for ( t = 0; t < 100 && !cp_flag( "power_on" ); t++ )
	{
		wait( .1 );
	}
	cp_log( "restore power: power_on " + cp_flag( "power_on" ) );
}


// the doors' own buy triggers, free while zombie_unlock_all is set (as sandbox_open_sesame)
cp_restore_doors( player, keys )
{
	if ( !IsDefined( keys ) || keys.size == 0 )
	{
		return;
	}
	SetDvar( "zombie_unlock_all", 1 );
	n = 0;
	for ( i = 0; i < level.cp_door_ents.size; i++ )
	{
		if ( !cp_in_array( keys, level.cp_door_keys[i] ) )
		{
			continue;
		}
		ent = level.cp_door_ents[i];
		if ( !IsDefined( ent ) || cp_door_is_open( i ) )
		{
			continue; // opened with another trigger of the same door
		}
		ent notify( "trigger", player );
		n++;
		wait( .05 );
	}
	wait( 1 );
	SetDvar( "zombie_unlock_all", 0 );
	cp_log( "restore doors: " + n + " triggers of " + keys.size + " saved" );
}


// each perk from its machine (as zombie_devgui_give_perk / the sandbox perk pads): the retail bottle, HUD and effects
cp_restore_perks( player, list )
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
			cp_log( "restore perk " + perk + ": no machine on this map" );
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
		cp_log( "restore perk " + perk + ": " + ( player HasPerk( perk ) ) );
		wait( .25 );
	}
}


cp_restore_weapons( player, primaries, offhand, current )
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
			cp_set_ammo( player, w, f );
		}
	}
	// the start pistol (and any other gun not in the checkpoint) goes, once the saved ones are in hand
	if ( saved.size > 0 )
	{
		have = player GetWeaponsListPrimaries();
		for ( i = 0; i < have.size; i++ )
		{
			if ( !cp_in_array( saved, have[i] ) && !cp_skip_weapon( have[i] ) )
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
			cp_set_ammo( player, w, f );
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
	cp_log( "restore weapons: " + saved.size + " primaries, current " + ( player GetCurrentWeapon() ) );
}


// f = [ name, clip, stock ]
cp_set_ammo( player, w, f )
{
	if ( !( player HasWeapon( w ) ) )
	{
		cp_log( "restore weapon " + w + ": not given" );
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
