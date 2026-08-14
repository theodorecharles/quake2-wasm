#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${IMAGE_REPO:-theodorecharles/quake2-wasm}:${IMAGE_TAG:-dev}"

stage_dir="$(mktemp -d)"
trap 'rm -rf "$stage_dir"' EXIT

web_artifacts=(
  index.html index.js index.data index.wasm game_baseq2.wasm ref_soft.wasm
  ref_gles3.wasm bundle-manifest.json
)
have_web=1
for name in "${web_artifacts[@]}"; do
  test -s "$repo_root/release/$name" || have_web=0
done
if [[ "$have_web" == 0 ]]; then
  JOBS="${JOBS:-4}" "$repo_root/scripts/build-web.sh"
fi
mkdir -p "$stage_dir/release"
for name in "${web_artifacts[@]}"; do
  cp -f "$repo_root/release/$name" "$stage_dir/release/$name"
done

if [[ ! -s "$repo_root/release/q2ded" || ! -s "$repo_root/release/baseq2/game.so" ]]; then
  JOBS="${JOBS:-4}" "$repo_root/scripts/build-server.sh"
fi
cp -f "$stage_dir/release/"* "$repo_root/release/"

for artifact in \
  release/index.html \
  release/index.js \
  release/index.wasm \
  release/game_baseq2.wasm \
  release/ref_soft.wasm \
  release/ref_gles3.wasm \
  release/q2ded \
  release/baseq2/game.so; do
  test -s "$repo_root/$artifact" || {
    echo "Missing $artifact; run scripts/build-web.sh and scripts/build-server.sh first." >&2
    exit 1
  }
done

docker build --platform linux/amd64 \
  --build-arg "VCS_REF=$(git -C "$repo_root" rev-parse HEAD)" \
  --tag "$image" "$repo_root"
echo "Built $image"
