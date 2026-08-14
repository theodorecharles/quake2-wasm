/*
 * Copyright (C) 1997-2001 Id Software, Inc.
 * Copyright (C) 2026 quake2-wasm contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#include <emscripten.h>

#include "../../client/header/client.h"
#include "../../client/header/keyboard.h"
#include "../../client/vid/header/vid.h"
#include "../../common/header/common.h"

qboolean q2web_input_captured = false;
static qboolean q2web_started = false;
static qboolean q2web_controls_announced = false;

void
Q2Web_ConfigureControls(void)
{
	Key_SetBinding('w', "+forward");
	Key_SetBinding('s', "+back");
	Key_SetBinding('a', "+moveleft");
	Key_SetBinding('d', "+moveright");
	Key_SetBinding(K_SPACE, "+moveup");
	Key_SetBinding('e', "+use");
	Key_SetBinding(K_MOUSE1, "+attack");
	Key_SetBinding(K_MOUSE2, "+moveup");
	Key_SetBinding(K_SHIFT, "+speed");
	Key_SetBinding('z', "");
	Cvar_Set("sensitivity", "4");
	Cvar_Set("m_filter", "0");
	if (!q2web_controls_announced)
	{
		Com_Printf("[quake2-wasm] browser controls: WASD, sensitivity 4, mouse look/fire, Space jump, E use\n");
		q2web_controls_announced = true;
	}
}

EMSCRIPTEN_KEEPALIVE void
Q2Web_SetInputCaptured(int captured)
{
	q2web_input_captured = captured ? true : false;
	if (!q2web_input_captured)
	{
		Key_MarkAllUp();
	}
}

EMSCRIPTEN_KEEPALIVE void
Q2Web_EnsureMenu(void)
{
	if (!q2web_started || cls.key_dest != key_game)
	{
		return;
	}
	Key_Event(K_ESCAPE, true, true);
	Key_Event(K_ESCAPE, false, true);
}

EMSCRIPTEN_KEEPALIVE int
Q2Web_ControlsMask(void)
{
	int mask = 0;
	if (keybindings['w'] && strcmp(keybindings['w'], "+forward") == 0) mask |= 1;
	if (keybindings['s'] && strcmp(keybindings['s'], "+back") == 0) mask |= 2;
	if (keybindings['a'] && strcmp(keybindings['a'], "+moveleft") == 0) mask |= 4;
	if (keybindings['d'] && strcmp(keybindings['d'], "+moveright") == 0) mask |= 8;
	if (keybindings['z'] && keybindings['z'][0] == '\0') mask |= 16;
	if (Cvar_VariableValue("sensitivity") == 4.0f) mask |= 32;
	if (Cvar_VariableValue("m_filter") == 0.0f) mask |= 64;
	return mask;
}

EMSCRIPTEN_KEEPALIVE void
Q2Web_ApplyQuality(int level)
{
	if (level < 0)
	{
		level = 0;
	}
	else if (level > 2)
	{
		level = 2;
	}

	Cvar_SetValue("cl_particles", level > 0);
	Cvar_SetValue("cl_lights", level > 0);
	Cvar_SetValue("r_shadows", level > 1);
	Cvar_SetValue("r_anisotropic", level == 0 ? 2 : (level == 1 ? 8 : 16));
}

EMSCRIPTEN_KEEPALIVE void
Q2Web_ResizeViewport(int width, int height)
{
	if (!q2web_started || width < 320 || height < 200 || width > 8192 || height > 8192)
	{
		return;
	}
	if ((int)Cvar_VariableValue("r_customwidth") == width &&
		(int)Cvar_VariableValue("r_customheight") == height)
	{
		return;
	}
	Cvar_SetValue("r_mode", -1);
	Cvar_SetValue("r_customwidth", width);
	Cvar_SetValue("r_customheight", height);
	Cbuf_AddText("vid_restart\n");
	Com_Printf("[quake2-wasm] browser viewport: %dx%d\n", width, height);
}

int
main(int argc, char **argv)
{
	Sys_SetupFPU();

	for (int i = 0; i < argc; ++i)
	{
		if (strcmp(argv[i], "-portable") == 0)
		{
			is_portable = true;
		}
		else if (strcmp(argv[i], "-datadir") == 0)
		{
			struct stat sb;

			if (++i >= argc)
			{
				fprintf(stderr, "-datadir needs an argument\n");
				return 1;
			}

			if (stat(argv[i], &sb) != 0 || !S_ISDIR(sb.st_mode))
			{
				fprintf(stderr, "-datadir %s is not a directory: %s\n",
					argv[i], strerror(errno));
				return 1;
			}

			Q_strlcpy(datadir, argv[i], sizeof(datadir));
		}
	}

	printf("[quake2-wasm] browser filesystem ready; starting Yamagi Quake II\n");
	Qcommon_Init(argc, argv);
	q2web_started = true;
	return 0;
}
