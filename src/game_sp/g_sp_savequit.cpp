// mod (not part of the original game): Save & Quit for zombies. The game state itself is kept by the
// script mod mods/savequit (maps\savequit\_savequit.gsc): the round, points, weapons, perks, opened doors
// and power. This file is the engine half:
//
//   bo1_mod_savequit 1         turns it on (the launcher sets it, with fs_mods ... savequit)
//   bo1_mod_savequit_key F5    the key that asks for Save & Quit (press it twice: the script asks to confirm)
//   bo1_savequit               console command, the same as the key
//   bo1_savequit_request       counter the key and the command raise; the script polls it and sets it back to 0
//
// Script builtins (server instance):
//   bo1_savequit_write( name, text )  -> 1 / 0      writes <fs_homepath>/savequit/<name>.txt
//   bo1_savequit_read( name )         -> text / ""  reads it back
//   bo1_savequit_retire( name )       -> 1 / 0      renames it to <name>.loaded (a save is used once)
//   bo1_savequit_exit( desktop )                    queues "disconnect" (main menu) or "quit" (desktop)
//
// The file lives outside fs_game / fs_mods on purpose, so the launcher finds it at build\Release\savequit\
// whatever mods were loaded; the script stores the mod list in it and refuses a save made with other mods.

#include "g_sp_loadgame.h"
#include "g_sp_levelstart.h"
#include <client/cl_keys.h>
#include <qcommon/cmd.h>
#include <qcommon/common.h>
#include <universal/com_files.h>
#include <universal/dvar.h>
#include <universal/q_shared.h>
#include <clientscript/cscr_vm.h>
#include <stdio.h>
#include <string.h>

static const dvar_s *bo1_mod_savequit;
static const dvar_s *bo1_mod_savequit_key;
static const dvar_s *bo1_savequit_request;

static void SP_SaveQuit_RegisterDvars()
{
    if (bo1_mod_savequit)
        return;
    bo1_mod_savequit = _Dvar_RegisterBool("bo1_mod_savequit", false, 0,
        "mod: Save & Quit (mods/savequit): the save key and the console command bo1_savequit");
    bo1_mod_savequit_key = _Dvar_RegisterString("bo1_mod_savequit_key", "F5", 0,
        "mod: the key that asks for Save & Quit (press twice)");
    bo1_savequit_request = _Dvar_RegisterInt("bo1_savequit_request", 0, 0, 0x7FFFFFFF, 0,
        "mod: Save & Quit requests not yet seen by the script (mods/savequit resets it)");
}

static bool SP_SaveQuit_Request()
{
    SP_SaveQuit_RegisterDvars();
    if (!bo1_mod_savequit->current.enabled || !G_SP_IsSPLevel() || !Dvar_GetBool("sv_running"))
        return false;
    Dvar_SetInt((dvar_s *)bo1_savequit_request, bo1_savequit_request->current.integer + 1);
    return true;
}

bool SP_SaveQuitKey(int key)
{
    SP_SaveQuit_RegisterDvars();
    if (!bo1_mod_savequit->current.enabled)
        return false;
    const char *name = bo1_mod_savequit_key->current.string;
    if (!name || !*name || Key_StringToKeynum(name) != key)
        return false;
    return SP_SaveQuit_Request();
}

static void SP_SaveQuit_f()
{
    if (!SP_SaveQuit_Request())
        Com_Printf(15, "bo1_savequit: off (bo1_mod_savequit 0, or no zombies level running)\n");
}

static cmd_function_s SP_SaveQuit_f_VAR;

void SP_SaveQuit_Register()
{
    static bool registered;
    if (registered)
        return;
    registered = true;
    SP_SaveQuit_RegisterDvars();
    Cmd_AddCommandInternal("bo1_savequit", SP_SaveQuit_f, &SP_SaveQuit_f_VAR);
}

// <fs_homepath>/savequit/<name><ext>; false for an empty name or one with characters other than A-Z a-z 0-9 _ -
static bool SP_SaveQuit_Path(const char *name, const char *ext, char *ospath)
{
    if (!name || !*name || strlen(name) > 64)
        return false;
    for (const char *c = name; *c; ++c)
    {
        if (!((*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z') || (*c >= '0' && *c <= '9') || *c == '_' || *c == '-'))
            return false;
    }
    char qpath[96];
    Com_sprintf(qpath, sizeof(qpath), "%s%s", name, ext);
    FS_BuildOSPath((char *)fs_homepath->current.string, (char *)"savequit", qpath, ospath);
    return true;
}

void G_SaveQuit_f_write()
{
    const char *name = Scr_GetString(0, SCRIPTINSTANCE_SERVER);
    const char *text = Scr_GetString(1, SCRIPTINSTANCE_SERVER);
    char ospath[256];
    char tmppath[256];
    if (!SP_SaveQuit_Path(name, ".txt", ospath) || !SP_SaveQuit_Path(name, ".tmp", tmppath))
    {
        Com_Printf(15, "savequit: bad save name '%s'\n", name);
        Scr_AddInt(0, SCRIPTINSTANCE_SERVER);
        return;
    }
    if (FS_CreatePath(tmppath))
    {
        Com_Printf(15, "savequit: cannot create the folder for %s\n", tmppath);
        Scr_AddInt(0, SCRIPTINSTANCE_SERVER);
        return;
    }
    // write next to it, then replace: a crash while writing never leaves half a save
    FILE *f = fopen(tmppath, "wb");
    const size_t len = strlen(text);
    const bool ok = f && fwrite(text, 1, len, f) == len;
    if (f)
        fclose(f);
    if (ok)
    {
        remove(ospath);
        if (rename(tmppath, ospath))
        {
            Com_Printf(15, "savequit: cannot rename %s to %s\n", tmppath, ospath);
            Scr_AddInt(0, SCRIPTINSTANCE_SERVER);
            return;
        }
        Com_Printf(15, "savequit: wrote %s (%i bytes)\n", ospath, (int)len);
    }
    else
    {
        remove(tmppath);
        Com_Printf(15, "savequit: cannot write %s\n", tmppath);
    }
    Scr_AddInt(ok ? 1 : 0, SCRIPTINSTANCE_SERVER);
}

void G_SaveQuit_f_read()
{
    const char *name = Scr_GetString(0, SCRIPTINSTANCE_SERVER);
    char ospath[256];
    static char text[16384];
    text[0] = 0;
    if (SP_SaveQuit_Path(name, ".txt", ospath))
    {
        if (FILE *f = fopen(ospath, "rb"))
        {
            const size_t n = fread(text, 1, sizeof(text) - 1, f);
            text[n] = 0;
            if (!feof(f))
            {
                Com_Printf(15, "savequit: %s is larger than %i bytes, ignored\n", ospath, (int)sizeof(text) - 1);
                text[0] = 0;
            }
            fclose(f);
        }
    }
    Scr_AddString(text, SCRIPTINSTANCE_SERVER);
}

void G_SaveQuit_f_retire()
{
    const char *name = Scr_GetString(0, SCRIPTINSTANCE_SERVER);
    char ospath[256];
    char usedpath[256];
    bool ok = false;
    if (SP_SaveQuit_Path(name, ".txt", ospath) && SP_SaveQuit_Path(name, ".loaded", usedpath))
    {
        remove(usedpath);
        ok = !rename(ospath, usedpath);
    }
    Scr_AddInt(ok ? 1 : 0, SCRIPTINSTANCE_SERVER);
}

void G_SaveQuit_f_exit()
{
    const bool desktop = Scr_GetNumParam(SCRIPTINSTANCE_SERVER) > 0 && Scr_GetInt(0, SCRIPTINSTANCE_SERVER) != 0;
    Com_Printf(15, "savequit: leaving the game (%s)\n", desktop ? "quit" : "disconnect");
    Cbuf_AddText(0, desktop ? "quit\n" : "disconnect\n");
}
