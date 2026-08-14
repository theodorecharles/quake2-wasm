#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
jobs="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
native_cc="${NATIVE_CC:-cc}"
source_date_epoch="${SOURCE_DATE_EPOCH:-$(git -C "${repo_dir}" log -1 --format=%ct)}"

if ! command -v "${native_cc}" >/dev/null 2>&1; then
  echo "Native compiler not found: ${native_cc}" >&2
  exit 1
fi

cd "${repo_dir}"
make clean
make -j"${jobs}" CC="${native_cc}" SDLCFLAGS= SDLLDFLAGS= \
  SOURCE_DATE_EPOCH="${source_date_epoch}" server game

node scripts/write-manifest.mjs bundle release/server-manifest.json quake2-server \
  "$(${native_cc} --version | sed -n '1p')" "${source_date_epoch}" false \
  release/q2ded release/baseq2/game.so

echo "Dedicated server ready: ${repo_dir}/release/server-manifest.json"
