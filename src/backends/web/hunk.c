/*
 * Copyright (C) 1997-2001 Id Software, Inc.
 * Copyright (C) 2026 quake2-wasm contributors
 *
 * GPL-2.0-or-later. Browser replacement for the native mmap hunk.
 */

#include <stdlib.h>

#include "../../common/header/common.h"

static byte *membase;
static size_t maxhunksize;
static size_t curhunksize;

void *
Hunk_Begin(int maxsize)
{
	maxhunksize = (size_t)maxsize + sizeof(size_t) + 32;
	curhunksize = 0;
	membase = malloc(maxhunksize);

	if (!membase)
	{
		Sys_Error("unable to allocate %d hunk bytes", maxsize);
	}

	*((size_t *)membase) = 0;
	return membase + sizeof(size_t);
}

void *
Hunk_Alloc(int size)
{
	byte *result;
	size = (size + 31) & ~31;

	if (curhunksize + (size_t)size + sizeof(size_t) > maxhunksize)
	{
		Sys_Error("%s: overflow %zu > %zu", __func__,
			curhunksize + (size_t)size, maxhunksize);
	}

	result = membase + sizeof(size_t) + curhunksize;
	curhunksize += (size_t)size;
	return result;
}

int
Hunk_End(void)
{
	*((size_t *)membase) = curhunksize + sizeof(size_t);
	return (int)curhunksize;
}

void
Hunk_Free(void *base)
{
	if (base)
	{
		free(((byte *)base) - sizeof(size_t));
	}

	membase = NULL;
	maxhunksize = 0;
	curhunksize = 0;
}
