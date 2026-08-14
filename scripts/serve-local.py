#!/usr/bin/env python3
"""Loopback static host and bounded Emscripten SOCKFS-to-Quake-II UDP bridge."""

from __future__ import annotations

import argparse
import base64
import hashlib
import logging
import selectors
import socket
import struct
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


MAX_PACKET = 1400
MAX_INPUT_BUFFER = 64 * 1024
MAX_OUTPUT_BUFFER = 64 * 1024
PORT_PREFIX = b"\xff\xff\xff\xffport"
WEBSOCKET_GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class ProtocolError(Exception):
    pass


def encode_frame(opcode: int, payload: bytes = b"") -> bytes:
    first = 0x80 | opcode
    length = len(payload)
    if length < 126:
        return bytes((first, length)) + payload
    return bytes((first, 126)) + struct.pack("!H", length) + payload


def decode_frames(buffer: bytearray):
    while len(buffer) >= 2:
        first, second = buffer[0], buffer[1]
        if first & 0x70:
            raise ProtocolError("reserved WebSocket bits are unsupported")
        if not first & 0x80:
            raise ProtocolError("fragmented WebSocket frames are unsupported")
        if not second & 0x80:
            raise ProtocolError("browser frames must be masked")

        opcode = first & 0x0F
        length = second & 0x7F
        offset = 2
        if length == 126:
            if len(buffer) < 4:
                return
            length = struct.unpack("!H", buffer[2:4])[0]
            offset = 4
        elif length == 127:
            raise ProtocolError("oversized WebSocket frame")

        limit = 125 if opcode in (0x8, 0x9, 0xA) else MAX_PACKET
        if length > limit:
            raise ProtocolError(f"frame payload exceeds {limit} bytes")
        frame_length = offset + 4 + length
        if len(buffer) < frame_length:
            return

        mask = buffer[offset:offset + 4]
        payload = bytes(value ^ mask[index & 3]
                        for index, value in enumerate(buffer[offset + 4:frame_length]))
        del buffer[:frame_length]
        yield opcode, payload


class BridgeHandler(SimpleHTTPRequestHandler):
    server_version = "quake2-local/1"
    protocol_version = "HTTP/1.1"
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".data": "application/octet-stream"}

    def do_GET(self):
        if urlsplit(self.path).path == "/ws":
            self.handle_websocket()
            return
        if self.path == "/":
            self.send_response(302)
            self.send_header("Location", "/release/")
            self.end_headers()
            return
        super().do_GET()

    def origin_allowed(self, origin: str | None) -> bool:
        if not origin:
            return False
        if self.server.allowed_origins:
            return origin in self.server.allowed_origins
        parsed = urlsplit(origin)
        default_port = 443 if parsed.scheme == "https" else 80
        return (parsed.scheme in ("http", "https") and
                parsed.hostname in ("127.0.0.1", "localhost", "::1") and
                (parsed.port or default_port) == self.server.server_port)

    def reject_upgrade(self, status: int, message: str):
        body = f"{message}\n".encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_websocket(self):
        if self.headers.get("Upgrade", "").lower() != "websocket":
            self.reject_upgrade(426, "WebSocket upgrade required")
            return
        if not self.origin_allowed(self.headers.get("Origin")):
            self.reject_upgrade(403, "WebSocket origin rejected")
            return
        protocols = {item.strip() for item in self.headers.get("Sec-WebSocket-Protocol", "").split(",")}
        if "binary" not in protocols:
            self.reject_upgrade(400, "The Emscripten binary subprotocol is required")
            return
        key = self.headers.get("Sec-WebSocket-Key", "")
        try:
            if len(base64.b64decode(key, validate=True)) != 16:
                raise ValueError
        except ValueError:
            self.reject_upgrade(400, "Invalid WebSocket key")
            return

        accept = base64.b64encode(hashlib.sha1(key.encode() + WEBSOCKET_GUID).digest()).decode()
        self.send_response(101, "Switching Protocols")
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.send_header("Sec-WebSocket-Protocol", "binary")
        self.end_headers()
        self.close_connection = True
        self.bridge_udp()

    def bridge_udp(self):
        peer = self.client_address[0]
        packets_in = packets_out = dropped = 0
        started = time.monotonic()
        last_activity = started
        websocket = self.connection
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp.connect(self.server.q2ded_target)
        websocket.setblocking(False)
        udp.setblocking(False)
        selector = selectors.DefaultSelector()
        selector.register(websocket, selectors.EVENT_READ)
        selector.register(udp, selectors.EVENT_READ)
        incoming = bytearray()
        outgoing = bytearray()
        first_binary = True
        reason = "peer closed"

        logging.info("bridge open peer=%s target=%s:%d", peer, *self.server.q2ded_target)
        try:
            while True:
                if time.monotonic() - last_activity > self.server.bridge_idle_timeout:
                    reason = "idle timeout"
                    break
                websocket_events = selectors.EVENT_READ | (selectors.EVENT_WRITE if outgoing else 0)
                selector.modify(websocket, websocket_events)
                for key, mask in selector.select(timeout=1.0):
                    if key.fileobj is websocket:
                        if mask & selectors.EVENT_READ:
                            chunk = websocket.recv(MAX_INPUT_BUFFER)
                            if not chunk:
                                return
                            incoming.extend(chunk)
                            last_activity = time.monotonic()
                            if len(incoming) > MAX_INPUT_BUFFER:
                                raise ProtocolError("input buffer limit exceeded")
                            for opcode, payload in decode_frames(incoming):
                                if opcode == 0x8:
                                    reason = "WebSocket close"
                                    return
                                if opcode == 0x9:
                                    outgoing.extend(encode_frame(0xA, payload))
                                    continue
                                if opcode == 0xA:
                                    continue
                                if opcode != 0x2:
                                    raise ProtocolError("only binary data frames are accepted")
                                if first_binary and len(payload) == 10 and payload.startswith(PORT_PREFIX):
                                    first_binary = False
                                    continue
                                first_binary = False
                                if payload:
                                    udp.send(payload)
                                    packets_in += 1
                        if mask & selectors.EVENT_WRITE and outgoing:
                            sent = websocket.send(outgoing)
                            del outgoing[:sent]
                    elif key.fileobj is udp:
                        payload = udp.recv(MAX_PACKET + 1)
                        last_activity = time.monotonic()
                        if len(payload) > MAX_PACKET:
                            dropped += 1
                            continue
                        frame = encode_frame(0x2, payload)
                        if len(outgoing) + len(frame) > MAX_OUTPUT_BUFFER:
                            dropped += 1
                            continue
                        outgoing.extend(frame)
                        packets_out += 1
        except (ConnectionError, OSError) as error:
            reason = error.__class__.__name__
        except ProtocolError as error:
            reason = str(error)
            close_payload = struct.pack("!H", 1002) + reason.encode()[:120]
            try:
                websocket.send(encode_frame(0x8, close_payload))
            except OSError:
                pass
        finally:
            selector.close()
            udp.close()
            duration = time.monotonic() - started
            logging.info("bridge close peer=%s reason=%s seconds=%.1f in=%d out=%d dropped=%d",
                         peer, reason, duration, packets_in, packets_out, dropped)


class BridgeServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> None:
    repo_dir = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8082)
    parser.add_argument("--root", type=Path, default=repo_dir)
    parser.add_argument("--q2ded-host", default="127.0.0.1")
    parser.add_argument("--q2ded-port", type=int, default=27910)
    parser.add_argument("--idle-timeout", type=float, default=90.0)
    parser.add_argument("--allow-origin", action="append", default=[])
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    handler = lambda *handler_args, **kwargs: BridgeHandler(
        *handler_args, directory=str(args.root.resolve()), **kwargs)
    server = BridgeServer((args.bind, args.port), handler)
    server.q2ded_target = (socket.gethostbyname(args.q2ded_host), args.q2ded_port)
    server.bridge_idle_timeout = args.idle_timeout
    server.allowed_origins = frozenset(args.allow_origin)
    logging.info("serving %s at http://%s:%d; /ws -> %s:%d",
                 args.root.resolve(), args.bind, args.port, *server.q2ded_target)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
