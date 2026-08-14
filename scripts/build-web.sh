#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
emsdk_env="${EMSDK_ENV:-/home/ted/emsdk/emsdk_env.sh}"
expected_version="$(tr -d '[:space:]' < "${repo_dir}/scripts/emscripten-version.txt")"
jobs="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
with_gl1="${WITH_GL1:-no}"
with_local_data="${WITH_LOCAL_RETAIL_DATA:-0}"
source_date_epoch="${SOURCE_DATE_EPOCH:-$(git -C "${repo_dir}" log -1 --format=%ct)}"

if [[ ! -f "${emsdk_env}" ]]; then
  echo "Emscripten environment not found: ${emsdk_env}" >&2
  exit 1
fi

source "${emsdk_env}" >/dev/null
actual_version="$(emcc --version | sed -n '1s/.*) \([0-9][0-9.]*\) (.*/\1/p')"
if [[ "${actual_version}" != "${expected_version}" ]]; then
  echo "Emscripten ${expected_version} is required; found ${actual_version:-unknown}." >&2
  exit 1
fi

make_args=(
  "SOURCE_DATE_EPOCH=${source_date_epoch}"
  "WITH_GL1=${with_gl1}"
)

contains_retail_data=false
if [[ "${with_local_data}" == "1" ]]; then
  local_data_dir="${QUAKE2_DATA_DIR:-${repo_dir}/data/baseq2}"
  if [[ ! -f "${local_data_dir}/pak0.pak" ]]; then
    echo "Local retail data is missing. Run scripts/setup-data.sh first." >&2
    exit 1
  fi
  echo "WARNING: creating an ignored local bundle containing retail data; never publish release/index.data." >&2
  make_args+=("WASM_LOCAL_DATA_DIR=${local_data_dir}")
  contains_retail_data=true
fi

if [[ "${with_gl1}" == "yes" && ! -f "${GL4ES_PATH:-}/lib/libGL.a" ]]; then
  echo "WITH_GL1=yes requires GL4ES_PATH to point to a PIC-enabled GL4ES build." >&2
  exit 1
fi

cd "${repo_dir}"
make clean
emmake make -j"${jobs}" "${make_args[@]}" all

artifacts=(
  release/index.html
  release/index.js
  release/index.data
  release/index.wasm
  release/game_baseq2.wasm
  release/ref_soft.wasm
  release/ref_gles3.wasm
)
if [[ "${with_gl1}" == "yes" ]]; then artifacts+=(release/ref_gl1.wasm); fi

node scripts/write-manifest.mjs bundle release/bundle-manifest.json quake2-web \
  "emscripten-${actual_version}" "${source_date_epoch}" "${contains_retail_data}" "${artifacts[@]}"

echo "Web bundle ready: ${repo_dir}/release/bundle-manifest.json"
