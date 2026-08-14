# syntax=docker/dockerfile:1.7

FROM python:3.13-slim

ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="Quake II WASM" \
      org.opencontainers.image.description="Assetless Quake II browser checkpoint" \
      org.opencontainers.image.source="https://github.com/theodorecharles/quake2-wasm" \
      org.opencontainers.image.revision="$VCS_REF"

WORKDIR /opt/quake2
COPY release ./release
COPY scripts/serve-local.py ./scripts/serve-local.py
COPY docker/entrypoint.sh /usr/local/bin/quake2-entrypoint

RUN useradd --create-home --uid 10002 --shell /usr/sbin/nologin quake2 \
    && mkdir -p /data/baseq2 /data/custom_maps /data/runtime \
    && chmod 0755 /usr/local/bin/quake2-entrypoint /opt/quake2/release/q2ded \
    && chown -R quake2:quake2 /opt/quake2 /data

ENV HTTP_PORT=8088 \
    Q2_DED_PORT=27910 \
    GAME_SLOTS=8 \
    KEEP_ALIVE=false \
    IDLE_TIMEOUT=15m \
    GAME_MODE=vanilla

VOLUME ["/data"]
EXPOSE 8088/tcp 27910/udp
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8088/health', timeout=3)"

USER quake2
ENTRYPOINT ["/usr/local/bin/quake2-entrypoint"]
