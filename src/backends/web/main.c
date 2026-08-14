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

#include "../../common/header/common.h"

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
	return 0;
}
