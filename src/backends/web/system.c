/*
 * Copyright (C) 1997-2001 Id Software, Inc.
 * Copyright (C) 2026 quake2-wasm contributors
 *
 * GPL-2.0-or-later. Browser system services for the standalone WASM build.
 */

#include <dirent.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <emscripten.h>

#include "../../client/vid/header/ref.h"
#include "../../common/header/common.h"
#include "../../common/header/glob.h"
#include "../../game/header/game.h"

extern game_export_t *GetGameAPI(const game_import_t *import);
extern refexport_t GetRefAPI(refimport_t import);

qboolean stdin_active = false;
char cfgdir[MAX_OSPATH] = CFGDIRNAME;

static char findbase[MAX_OSPATH];
static char findpath[MAX_OSPATH];
static char findpattern[MAX_OSPATH];
static DIR *finddir;

void
setCustomCfgDir(const char *dir)
{
	Q_strlcpy(cfgdir, dir, sizeof(cfgdir));
}

void
Sys_Error(const char *error, ...)
{
	char message[2048];
	va_list args;

	va_start(args, error);
	vsnprintf(message, sizeof(message), error, args);
	va_end(args);

	fprintf(stderr, "[quake2-wasm] fatal: %s\n", message);
#ifndef DEDICATED_ONLY
	CL_Shutdown();
#endif
	Qcommon_Shutdown();
	emscripten_cancel_main_loop();
	exit(1);
}

void
Sys_Quit(void)
{
#ifndef DEDICATED_ONLY
	CL_Shutdown();
#endif
	Qcommon_Shutdown();
	emscripten_cancel_main_loop();
	exit(0);
	__builtin_unreachable();
}

void
Sys_Init(void)
{
	Sys_ConsoleOutput("[quake2-wasm] WebAssembly platform initialized\n");
}

char *
Sys_ConsoleInput(void)
{
	return NULL;
}

void
Sys_ConsoleOutput(char *string)
{
	fputs(string, stdout);
}

long long
Sys_Microseconds(void)
{
	static double first = -1.0;
	double now = emscripten_get_now();

	if (first < 0.0)
	{
		first = now - 1.0;
	}

	return (long long)((now - first) * 1000.0);
}

int
Sys_Milliseconds(void)
{
	return (int)(Sys_Microseconds() / 1000ll);
}

void
Sys_Nanosleep(int nanosec)
{
	(void)nanosec;
}

static char *
FindNextMatch(void)
{
	struct dirent *entry;

	while (finddir && (entry = readdir(finddir)) != NULL)
	{
		if ((!*findpattern || glob_match(findpattern, entry->d_name)) &&
			strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0)
		{
			Com_sprintf(findpath, sizeof(findpath), "%s/%s", findbase, entry->d_name);
			return findpath;
		}
	}

	return NULL;
}

char *
Sys_FindFirst(const char *path, unsigned musthave, unsigned canhave)
{
	char *slash;
	(void)musthave;
	(void)canhave;

	if (finddir)
	{
		Sys_Error("Sys_FindFirst without Sys_FindClose");
	}

	Q_strlcpy(findbase, path, sizeof(findbase));
	slash = strrchr(findbase, '/');
	if (slash)
	{
		*slash = '\0';
		Q_strlcpy(findpattern, slash + 1, sizeof(findpattern));
	}
	else
	{
		Q_strlcpy(findbase, ".", sizeof(findbase));
		Q_strlcpy(findpattern, path, sizeof(findpattern));
	}

	if (strcmp(findpattern, "*.*") == 0)
	{
		Q_strlcpy(findpattern, "*", sizeof(findpattern));
	}

	finddir = opendir(findbase);
	return FindNextMatch();
}

char *
Sys_FindNext(unsigned musthave, unsigned canhave)
{
	(void)musthave;
	(void)canhave;
	return FindNextMatch();
}

void
Sys_FindClose(void)
{
	if (finddir)
	{
		closedir(finddir);
		finddir = NULL;
	}
}

void
Sys_UnloadGame(void)
{
}

void *
Sys_GetGameAPI(void *parameters)
{
	return GetGameAPI((const game_import_t *)parameters);
}

void
Sys_Mkdir(const char *path)
{
	if (mkdir(path, 0755) != 0 && errno != EEXIST)
	{
		Sys_Error("Couldn't create directory %s: %s", path, strerror(errno));
	}
}

qboolean
Sys_IsDir(const char *path)
{
	struct stat info;
	return stat(path, &info) == 0 && S_ISDIR(info.st_mode);
}

qboolean
Sys_IsFile(const char *path)
{
	struct stat info;
	return stat(path, &info) == 0 && S_ISREG(info.st_mode);
}

char *
Sys_GetHomeDir(void)
{
	static char home[] = "/persist/";
	Sys_Mkdir("/persist");
	return home;
}

void
Sys_Remove(const char *path)
{
	if (remove(path) != 0 && errno != ENOENT)
	{
		Com_Printf("Couldn't remove %s: %s\n", path, strerror(errno));
	}
}

int
Sys_Rename(const char *from, const char *to)
{
	return rename(from, to);
}

void
Sys_RemoveDir(const char *path)
{
	DIR *directory = opendir(path);
	struct dirent *entry;
	char child[MAX_OSPATH];

	if (!directory)
	{
		return;
	}

	while ((entry = readdir(directory)) != NULL)
	{
		if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
		{
			continue;
		}
		Com_sprintf(child, sizeof(child), "%s/%s", path, entry->d_name);
		Sys_Remove(child);
	}

	closedir(directory);
	rmdir(path);
}

qboolean
Sys_Realpath(const char *input, char *output, size_t size)
{
	char *resolved = realpath(input, NULL);
	if (!resolved)
	{
		return false;
	}
	Q_strlcpy(output, resolved, (int)size);
	free(resolved);
	return true;
}

void *
Sys_GetProcAddress(void *handle, const char *symbol)
{
	(void)handle;
	if (symbol && strcmp(symbol, "GetRefAPI") == 0)
	{
		return (void *)(uintptr_t)&GetRefAPI;
	}
	return NULL;
}

void
Sys_FreeLibrary(void *handle)
{
	(void)handle;
}

void *
Sys_LoadLibrary(const char *path, const char *symbol, void **handle)
{
	(void)path;
	*handle = NULL;
	if (symbol && strcmp(symbol, "GetRefAPI") == 0)
	{
		*handle = (void *)1;
		return (void *)(uintptr_t)&GetRefAPI;
	}

	Com_Printf("[quake2-wasm] dynamic library request rejected: %s\n",
		symbol ? symbol : "(no symbol)");
	return NULL;
}

void
Sys_GetWorkDir(char *buffer, size_t length)
{
	if (!getcwd(buffer, length))
	{
		buffer[0] = '\0';
	}
}

qboolean
Sys_SetWorkDir(char *path)
{
	return chdir(path) == 0;
}
