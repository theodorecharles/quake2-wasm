#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${1:-/home/ted/.steam/debian-installation/steamapps/common/Quake 2/baseq2}"
output_dir="${2:-$repo_dir/build-web/release/assets}"
asset_dir="$output_dir/baseq2"
manifest_tmp="$output_dir/.manifest.json.tmp"

mkdir -p "$asset_dir"

entries=()
declare -A expected_size=(
  [pak0.pak]=183997730
  [pak1.pak]=12992754
  [pak2.pak]=45055
)
declare -A expected_md5=(
  [pak0.pak]=1ec55a724dc3109fd50dde71ab581d70
  [pak1.pak]=42663ea709b7cd3eb9b634b36cfecb1a
  [pak2.pak]=c8217cc5557b672a87fc210c2347d98d
)

for name in pak0.pak pak1.pak pak2.pak; do
  source_file="$source_dir/$name"
  if [[ ! -f "$source_file" ]]; then
    echo "Required owner-supplied file is missing: $source_file" >&2
    exit 1
  fi

  header="$(LC_ALL=C head -c 4 "$source_file")"
  if [[ "$header" != "PACK" ]]; then
    echo "$source_file does not have a Quake PAK header" >&2
    exit 1
  fi

  size="$(stat -c '%s' "$source_file")"
  md5="$(md5sum "$source_file" | cut -d ' ' -f 1)"
  if [[ "$size" != "${expected_size[$name]}" || "$md5" != "${expected_md5[$name]}" ]]; then
    echo "$source_file is not the supported retail/patch PAK (size or MD5 mismatch)" >&2
    exit 1
  fi
  digest="$(sha256sum "$source_file" | cut -d ' ' -f 1)"
  ln -sfn "$source_file" "$asset_dir/$name"
  entries+=("    {\"path\":\"baseq2/$name\",\"size\":$size,\"sha256\":\"$digest\"}")
done

{
  printf '{\n  "schema": 1,\n  "game": "quake2",\n  "files": [\n'
  for ((i = 0; i < ${#entries[@]}; ++i)); do
    comma=""
    [[ $i -lt $((${#entries[@]} - 1)) ]] && comma=","
    printf '%s%s\n' "${entries[$i]}" "$comma"
  done
  printf '  ]\n}\n'
} > "$manifest_tmp"
mv "$manifest_tmp" "$output_dir/manifest.json"

echo "Prepared ${#entries[@]} owner-supplied PAK files under $output_dir"
