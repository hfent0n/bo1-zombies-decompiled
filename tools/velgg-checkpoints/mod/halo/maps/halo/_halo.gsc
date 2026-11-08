#include maps\_utility;
#include common_scripts\utility;
#include maps\_zombiemode_utility;

// HALO MOD - not part of the original game. Loaded only with +set fs_mods "... halo" (maps/halo/_hooks.gsc).
// Side-loadable: mods/halo is the whole mod, these scripts and mods/halo/mod.ff (tools\halo\build_ff.ps1), using retail
// script functions only, so it needs no engine change.
// mod.ff holds the Halo Reach models and weapons (halo_<id>_zm and halo_<id>_upgraded_zm), and the list of them,
// maps/halo/_halo_list.gsc, which the build writes into mod.ff itself: the scripts precache exactly what that mod.ff
// has. Without mod.ff that list is missing and the mod does not load (the log names maps/halo/_halo_list).
// The weapons are buyable at spots around the first player's spawn, and optionally in the Mystery Box and on walls.
// mods/halo/README.md has the asset pipeline.
//
// Dvars:
//   halo_buys 0/1        buy spots for every Halo weapon around the first player's spawn (default 1; read at the start)
//   halo_buy_free 0/1    the buy spots cost nothing (default 0)
//   halo_box 0/1         the weapons also in the Mystery Box and the retail wall-buy tables (default 0; read at the
//                        start): uses retail include_zombie_weapon / add_zombie_weapon, whose signatures are assumed
//   halo_give <weapon>   console test: gives player 1 the weapon ("magnum" or "halo_magnum_zm"); cleared once read
//   halo_show <model>    console test: "magnum" or a full model name spins that model in front of player 1, "all"
//                        every model in rows, "test" the diagnostic models (tools/halo/make_test_models.py), "clear"
//                        removes them; cleared once read

main_end()
{
	// still inside maps\_zombiemode::main(), before its first wait: precaching works here
	halo_default_dvar( "halo_buys", "1" );
	halo_default_dvar( "halo_box", "0" );
	SetDvar( "halo_give", "" );
	SetDvar( "halo_show", "" );

	// what this mod.ff holds (written by tools\halo\build_ff.ps1 into mod.ff)
	in_ff = StrTok( maps\halo\_halo_list::weapons(), " " );
	level.halo_models = StrTok( maps\halo\_halo_list::models(), " " );
	for ( i = 0; i < level.halo_models.size; i++ )
	{
		PrecacheModel( level.halo_models[i] );
	}

	// name, wall-buy hint (mod.ff's localizedstrings/halo.str), in the box, wall-buy cost, display name
	level.halo_weapons = [];
	halo_weapon( "magnum", &"HALO_MAGNUM", true, 500, "M6G Magnum" );
	halo_weapon( "assault_rifle", &"HALO_ASSAULT_RIFLE", true, 1200, "MA37 Assault Rifle" );
	halo_weapon( "dmr", &"HALO_DMR", true, 1000, "M392 DMR" );
	halo_weapon( "shotgun", &"HALO_SHOTGUN", true, 1500, "M45 Shotgun" );
	halo_weapon( "sniper_rifle", &"HALO_SNIPER_RIFLE", true, 2500, "SRS99 Sniper Rifle" );
	halo_weapon( "grenade_launcher", &"HALO_GRENADE_LAUNCHER", true, 2000, "M319 Grenade Launcher" );
	halo_weapon( "rocket_launcher", &"HALO_ROCKET_LAUNCHER", true, 3000, "M41 Rocket Launcher" );
	halo_weapon( "spartan_laser", &"HALO_SPARTAN_LASER", true, 5000, "M6 Spartan Laser" );
	halo_weapon( "plasma_pistol", &"HALO_PLASMA_PISTOL", true, 750, "Plasma Pistol" );
	halo_weapon( "needler", &"HALO_NEEDLER", true, 1500, "Needler" );
	halo_weapon( "plasma_rifle", &"HALO_PLASMA_RIFLE", true, 1500, "Plasma Rifle" );
	halo_weapon( "plasma_repeater", &"HALO_PLASMA_REPEATER", true, 1500, "Plasma Repeater" );
	halo_weapon( "spiker", &"HALO_SPIKER", true, 1200, "Type-25 Spiker" );
	halo_weapon( "needle_rifle", &"HALO_NEEDLE_RIFLE", true, 1500, "Needle Rifle" );
	halo_weapon( "concussion_rifle", &"HALO_CONCUSSION_RIFLE", true, 2000, "Concussion Rifle" );
	halo_weapon( "focus_rifle", &"HALO_FOCUS_RIFLE", true, 2500, "Focus Rifle" );
	halo_weapon( "plasma_launcher", &"HALO_PLASMA_LAUNCHER", true, 3000, "Plasma Launcher" );
	halo_weapon( "fuel_rod", &"HALO_FUEL_ROD", true, 3000, "Fuel Rod Gun" );
	// not in the box (tools/halo/weapons.json "special"); fire bullets until they get their own behaviour
	halo_weapon( "energy_sword", &"HALO_ENERGY_SWORD", false, 1000, "Energy Sword" );
	halo_weapon( "gravity_hammer", &"HALO_GRAVITY_HAMMER", false, 1000, "Gravity Hammer" );
	halo_weapon( "frag_grenade", &"HALO_FRAG_GRENADE", false, 250, "M9 Frag Grenade" );
	halo_weapon( "plasma_grenade", &"HALO_PLASMA_GRENADE", false, 250, "Plasma Grenade" );

	box = GetDvarInt( #"halo_box" ) != 0;
	loaded = 0;
	for ( i = 0; i < level.halo_weapons.size; i++ )
	{
		w = level.halo_weapons[i];
		for ( j = 0; j < in_ff.size; j++ )
		{
			if ( in_ff[j] == w.id )
			{
				w.loaded = true;
			}
		}
		if ( !w.loaded )
		{
			continue;
		}
		loaded++;
		PrecacheItem( w.name );
		PrecacheItem( w.upgrade );
		if ( box )
		{
			halo_register( w, w.in_box );
		}
	}
	halo_log( loaded + " of " + level.halo_weapons.size + " weapons and " + level.halo_models.size + " models in mod.ff, box " + box );
	level thread halo_give_watch();
	level thread halo_show_watch();
	if ( GetDvarInt( #"halo_buys" ) != 0 )
	{
		level thread halo_buy_spots();
	}
}


halo_default_dvar( name, value )
{
	if ( GetDvar( name ) == "" )
	{
		SetDvar( name, value );
	}
}


halo_weapon( id, hint, in_box, cost, display )
{
	w = SpawnStruct();
	w.id = id;
	w.name = "halo_" + id + "_zm";
	w.upgrade = "halo_" + id + "_upgraded_zm";
	w.model = "halo_" + id + "_view";
	w.hint = hint;
	w.in_box = in_box;
	w.cost = cost;
	w.display = display;
	w.loaded = false;
	level.halo_weapons[level.halo_weapons.size] = w;
}


halo_log( msg )
{
	LogPrint( "halo: " + msg + "\n" );
}


halo_find_weapon( value )
{
	for ( i = 0; i < level.halo_weapons.size; i++ )
	{
		w = level.halo_weapons[i];
		if ( w.loaded && ( w.id == value || w.name == value ) )
		{
			return w;
		}
	}
	return undefined;
}


// The retail registration a map's include_weapons() and _zombiemode_weapons' init use for their own weapons.
// CHECK against raw/maps/_zombiemode_weapons.gsc of the Black Ops mod tools: this assumes
// include_zombie_weapon( weapon_name, in_box ) and add_zombie_weapon( weapon_name, upgrade_name, hint, cost ).
halo_register( w, in_box )
{
	maps\_zombiemode_weapons::include_zombie_weapon( w.name, in_box );
	maps\_zombiemode_weapons::add_zombie_weapon( w.name, w.upgrade, w.hint, w.cost );
}


halo_is_registered( name )
{
	return IsDefined( level.zombie_weapons ) && IsDefined( level.zombie_weapons[name] );
}


// self = player: the weapon in hand with full ammo. A weapon the retail tables know goes through retail weapon_give
// (as mods/sandbox's weapon pads); otherwise full hands (two primaries, three with Mule Kick) drop the current one, as
// a wall buy does.
halo_take( w )
{
	if ( halo_is_registered( w.name ) )
	{
		self maps\_zombiemode_weapons::weapon_give( w.name );
		return;
	}
	if ( !self HasWeapon( w.name ) )
	{
		limit = 2;
		if ( self HasPerk( "specialty_additionalprimaryweapon" ) )
		{
			limit = 3;
		}
		primaries = self GetWeaponsListPrimaries();
		current = self GetCurrentWeapon();
		if ( primaries.size >= limit && IsDefined( current ) && current != "none" )
		{
			self TakeWeapon( current );
		}
		self GiveWeapon( w.name );
	}
	self GiveMaxAmmo( w.name );
	self SwitchToWeapon( w.name );
}


//-------------------------------------------------------------------------------
// console tests
//-------------------------------------------------------------------------------

// /set halo_give magnum (or the full name)
halo_give_watch()
{
	level endon( "end_game" );
	flag_wait( "all_players_spawned" );
	for ( ;; )
	{
		wait( 0.5 );
		value = GetDvar( #"halo_give" );
		if ( value == "" )
		{
			continue;
		}
		SetDvar( "halo_give", "" );
		player = get_players()[0];
		w = halo_find_weapon( value );
		if ( !IsDefined( w ) )
		{
			halo_log( "halo_give " + value + ": not in mod.ff" );
			IPrintLn( "Halo: " + value + " is not in mod.ff" );
			continue;
		}
		player halo_take( w );
		halo_log( "halo_give " + w.name + " -> player 1, current " + player GetCurrentWeapon() );
	}
}


halo_model_loaded( name )
{
	for ( i = 0; i < level.halo_models.size; i++ )
	{
		if ( level.halo_models[i] == name )
		{
			return true;
		}
	}
	return false;
}


// /set halo_show magnum | all | clear: script models in front of player 1, side on, spinning
halo_show_watch()
{
	level endon( "end_game" );
	flag_wait( "all_players_spawned" );
	level.halo_shown = [];
	for ( ;; )
	{
		wait( 0.5 );
		value = GetDvar( #"halo_show" );
		if ( value == "" )
		{
			continue;
		}
		SetDvar( "halo_show", "" );
		for ( i = 0; i < level.halo_shown.size; i++ )
		{
			level.halo_shown[i] Delete();
		}
		level.halo_shown = [];
		if ( value == "clear" )
		{
			continue;
		}
		names = [];
		if ( value == "all" )
		{
			names = level.halo_models;
		}
		else if ( value == "test" )
		{
			// tools/halo/make_test_models.py: which of these draw right shows where a broken model goes wrong
			names = StrTok( "halo_test_cube halo_test_cube2 halo_magnum_1bone halo_magnum_view", " " );
		}
		else if ( IsSubStr( value, "halo_" ) )
		{
			names[0] = value;
		}
		else
		{
			names[0] = "halo_" + value + "_view";
		}
		player = get_players()[0];
		yaw = player.angles[1];
		forward = AnglesToForward( ( 0, yaw, 0 ) );
		right = AnglesToRight( ( 0, yaw, 0 ) );
		row = 0;
		col = 0;
		for ( i = 0; i < names.size; i++ )
		{
			if ( !halo_model_loaded( names[i] ) )
			{
				halo_log( "halo_show " + names[i] + ": not in mod.ff" );
				IPrintLn( "Halo: " + names[i] + " is not in mod.ff" );
				continue;
			}
			// rows of six, 30 units apart, starting 50 in front at about chest height
			pos = player.origin + forward * ( 50 + row * 30 ) + right * ( ( col - 2.5 ) * 30 ) + ( 0, 0, 48 );
			if ( names.size == 1 )
			{
				pos = player.origin + forward * 40 + ( 0, 0, 56 );
			}
			model = Spawn( "script_model", pos );
			model SetModel( names[i] );
			model.angles = ( 0, yaw - 90, 0 ); // the model's +X (muzzle) to the player's right
			model thread halo_spin();
			level.halo_shown[level.halo_shown.size] = model;
			halo_log( "halo_show " + names[i] + " at " + pos );
			col++;
			if ( col == 6 )
			{
				col = 0;
				row++;
			}
		}
	}
}


halo_spin()
{
	self endon( "death" );
	for ( ;; )
	{
		self RotateYaw( 360, 8 );
		wait( 8 );
	}
}


//-------------------------------------------------------------------------------
// buy spots: each weapon's model spinning over a use trigger around the first player's spawn
//-------------------------------------------------------------------------------

halo_buy_spots()
{
	level endon( "end_game" );
	flag_wait( "all_players_spawned" );
	wait( 1 );
	sellable = [];
	for ( i = 0; i < level.halo_weapons.size; i++ )
	{
		if ( level.halo_weapons[i].loaded )
		{
			sellable[sellable.size] = level.halo_weapons[i];
		}
	}
	player = get_players()[0];
	spots = halo_find_spots( player.origin, sellable.size, player );
	for ( i = 0; i < spots.size; i++ )
	{
		halo_spawn_buy( sellable[i], spots[i] );
	}
	halo_log( "buy spots " + spots.size + " of " + sellable.size + " around " + player.origin );
}


halo_spawn_buy( w, origin )
{
	trig = Spawn( "trigger_radius_use", origin, 0, 28, 72 );
	trig SetCursorHint( "HINT_NOICON" );
	trig SetHintString( "Press ^3[{+activate}]^7 for the " + w.display + " [Cost: " + w.cost + "]" );
	trig.weapon = w;
	trig.display = Spawn( "script_model", origin + ( 0, 0, 44 ) );
	trig.display SetModel( w.model );
	trig.display thread halo_spin();
	trig thread halo_buy_think();
}


halo_buy_think()
{
	level endon( "end_game" );
	w = self.weapon;
	for ( ;; )
	{
		self waittill( "trigger", player );
		if ( !IsDefined( player ) || !IsPlayer( player ) || !IsAlive( player ) || player maps\_laststand::player_is_in_laststand() )
		{
			continue;
		}
		free = GetDvarInt( #"halo_buy_free" ) != 0;
		if ( !free && player.score < w.cost )
		{
			IPrintLn( "Halo: the " + w.display + " costs " + w.cost );
			wait( 0.5 );
			continue;
		}
		if ( !free )
		{
			player.score = player.score - w.cost; // as mods/resume sets it: the networked score field
		}
		player halo_take( w );
		halo_log( "bought " + w.name + ", current " + player GetCurrentWeapon() + ", score " + player.score );
		wait( 0.5 );
	}
}


// count floor spots around center that a player there can see, nearest first, 64 apart and clear of the map's own
// use triggers (wall buys, perks, doors, the box)
halo_find_spots( center, count, ignore )
{
	avoid = [];
	classes = StrTok( "trigger_use trigger_use_touch trigger_radius_use", " " );
	for ( c = 0; c < classes.size; c++ )
	{
		ents = GetEntArray( classes[c], "classname" );
		for ( i = 0; i < ents.size; i++ )
		{
			avoid[avoid.size] = ents[i].origin;
		}
	}
	eye = center + ( 0, 0, 50 );
	spots = [];
	for ( r = 72; r <= 720 && spots.size < count; r += 52 )
	{
		steps = int( 6.2832 * r / 60 );
		for ( a = 0; a < steps && spots.size < count; a++ )
		{
			angle = a * 360 / steps;
			spot = halo_floor_spot( center + ( cos( angle ) * r, sin( angle ) * r, 0 ), center[2] );
			if ( !IsDefined( spot ) )
			{
				continue;
			}
			ok = BulletTracePassed( eye, spot + ( 0, 0, 40 ), false, ignore );
			for ( i = 0; ok && i < spots.size; i++ )
			{
				ok = Distance2D( spot, spots[i] ) >= 64;
			}
			for ( i = 0; ok && i < avoid.size; i++ )
			{
				ok = Distance2D( spot, avoid[i] ) >= 80 || abs( spot[2] - avoid[i][2] ) > 120;
			}
			if ( ok )
			{
				spots[spots.size] = spot;
			}
		}
	}
	return spots;
}


// the floor under p, within 40 units of the spawn's height, with 24 units of room around it
halo_floor_spot( p, z )
{
	trace = BulletTrace( p + ( 0, 0, 72 ), p - ( 0, 0, 72 ), false, undefined );
	if ( trace["fraction"] >= 1 )
	{
		return undefined;
	}
	floor = trace["position"];
	if ( abs( floor[2] - z ) > 40 )
	{
		return undefined;
	}
	dirs = [];
	dirs[0] = ( 24, 0, 0 );
	dirs[1] = ( -24, 0, 0 );
	dirs[2] = ( 0, 24, 0 );
	dirs[3] = ( 0, -24, 0 );
	for ( h = 16; h <= 64; h += 48 )
	{
		c = floor + ( 0, 0, h );
		for ( i = 0; i < dirs.size; i++ )
		{
			if ( !BulletTracePassed( c, c + dirs[i], false, undefined ) )
			{
				return undefined;
			}
		}
	}
	return floor;
}
