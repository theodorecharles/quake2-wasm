/*
 * Copyright (C) 1997-2001 Id Software, Inc.
 * Copyright (C) 2026 quake2-wasm contributors
 *
 * GPL-2.0-or-later. The first browser milestone intentionally provides only
 * the engine's in-process loopback transport used by single player.
 */

#include <arpa/inet.h>
#include <stdlib.h>
#include <string.h>

#include "../../common/header/common.h"

#define MAX_LOOPBACK 4

typedef struct
{
	byte data[MAX_MSGLEN];
	int datalen;
} loopmsg_t;

typedef struct
{
	loopmsg_t msgs[MAX_LOOPBACK];
	int get;
	int send;
} loopback_t;

static loopback_t loopbacks[2];
netadr_t net_local_adr;

void
NET_Init(void)
{
	memset(loopbacks, 0, sizeof(loopbacks));
	memset(&net_local_adr, 0, sizeof(net_local_adr));
	net_local_adr.type = NA_LOOPBACK;
	Com_Printf("[quake2-wasm] network: in-process loopback enabled; remote transport disabled\n");
}

void
NET_Shutdown(void)
{
}

void
NET_Config(qboolean multiplayer)
{
	static qboolean warned;
	if (multiplayer && !warned)
	{
		warned = true;
		Com_Printf("[quake2-wasm] remote multiplayer requires the pending WebSocket bridge\n");
	}
}

qboolean
NET_CompareAdr(netadr_t a, netadr_t b)
{
	if (a.type != b.type)
	{
		return false;
	}

	if (a.type == NA_LOOPBACK)
	{
		return true;
	}

	if (a.type == NA_IP)
	{
		return memcmp(a.ip, b.ip, 4) == 0 && a.port == b.port;
	}

	if (a.type == NA_IP6)
	{
		return memcmp(a.ip, b.ip, 16) == 0 && a.port == b.port;
	}

	return false;
}

qboolean
NET_CompareBaseAdr(netadr_t a, netadr_t b)
{
	if (a.type != b.type)
	{
		return false;
	}

	if (a.type == NA_LOOPBACK)
	{
		return true;
	}

	if (a.type == NA_IP)
	{
		return memcmp(a.ip, b.ip, 4) == 0;
	}

	if (a.type == NA_IP6)
	{
		return memcmp(a.ip, b.ip, 16) == 0;
	}

	return false;
}

char *
NET_AdrToString(netadr_t a)
{
	static char result[80];

	if (a.type == NA_LOOPBACK)
	{
		Com_sprintf(result, sizeof(result), "loopback");
	}
	else if (a.type == NA_IP)
	{
		Com_sprintf(result, sizeof(result), "%u.%u.%u.%u:%u",
			a.ip[0], a.ip[1], a.ip[2], a.ip[3], ntohs(a.port));
	}
	else
	{
		Com_sprintf(result, sizeof(result), "unsupported");
	}

	return result;
}

qboolean
NET_StringToAdr(const char *string, netadr_t *address)
{
	char *end;
	long port = 0;

	memset(address, 0, sizeof(*address));
	if (strncmp(string, "localhost", 9) != 0 &&
		strncmp(string, "loopback", 8) != 0)
	{
		return false;
	}

	end = strchr(string, ':');
	if (end)
	{
		port = strtol(end + 1, NULL, 10);
	}

	address->type = NA_LOOPBACK;
	address->port = htons((unsigned short)port);
	return true;
}

qboolean
NET_IsLocalAddress(netadr_t address)
{
	return address.type == NA_LOOPBACK;
}

static qboolean
NET_GetLoopPacket(netsrc_t socket, netadr_t *from, sizebuf_t *message)
{
	loopback_t *loop = &loopbacks[socket];
	int index;

	if (loop->send - loop->get > MAX_LOOPBACK)
	{
		loop->get = loop->send - MAX_LOOPBACK;
	}

	if (loop->get >= loop->send)
	{
		return false;
	}

	index = loop->get & (MAX_LOOPBACK - 1);
	loop->get++;
	memcpy(message->data, loop->msgs[index].data, loop->msgs[index].datalen);
	message->cursize = loop->msgs[index].datalen;
	*from = net_local_adr;
	return true;
}

qboolean
NET_GetPacket(netsrc_t socket, netadr_t *from, sizebuf_t *message)
{
	return NET_GetLoopPacket(socket, from, message);
}

void
NET_SendPacket(netsrc_t socket, int length, void *data, netadr_t to)
{
	loopback_t *loop;
	int index;

	if (to.type != NA_LOOPBACK)
	{
		return;
	}

	loop = &loopbacks[socket ^ 1];
	index = loop->send & (MAX_LOOPBACK - 1);
	loop->send++;

	if (length > MAX_MSGLEN)
	{
		length = MAX_MSGLEN;
	}

	memcpy(loop->msgs[index].data, data, length);
	loop->msgs[index].datalen = length;
}

void
NET_Sleep(int msec)
{
	(void)msec;
}
