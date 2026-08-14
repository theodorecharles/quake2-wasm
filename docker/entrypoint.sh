#!/bin/sh
set -eu

mkdir -p /data/baseq2 /data/custom_maps /data/runtime
exec python3 /opt/quake2/scripts/serve-local.py \
  --port "${HTTP_PORT:-8088}" \
  --bind 0.0.0.0 \
  --root /opt/quake2 \
  --q2ded-port "${Q2_DED_PORT:-27910}"
