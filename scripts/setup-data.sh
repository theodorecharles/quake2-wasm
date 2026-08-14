#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${QUAKE2_DATA_DIR:-${repo_dir}/data/baseq2}"

find_baseq2() {
  local candidate
  if [[ -n "${QUAKE2_PATH:-}" ]]; then
    for candidate in "${QUAKE2_PATH}" "${QUAKE2_PATH}/baseq2"; do
      if [[ -f "${candidate}/pak0.pak" ]]; then printf '%s\n' "${candidate}"; return 0; fi
    done
  fi

  local candidates=(
    "${HOME}/.steam/debian-installation/steamapps/common/Quake 2/baseq2"
    "${HOME}/.steam/steam/steamapps/common/Quake 2/baseq2"
    "${HOME}/.local/share/Steam/steamapps/common/Quake 2/baseq2"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}/pak0.pak" ]]; then printf '%s\n' "${candidate}"; return 0; fi
  done
  return 1
}

if ! source_baseq2="$(find_baseq2)"; then
  echo "Quake II retail data was not found." >&2
  echo "Set QUAKE2_PATH to the install root (or baseq2 directory) containing owner-provided baseq2/pak0.pak." >&2
  echo "No data was downloaded or modified." >&2
  exit 1
fi

mkdir -p "${destination}"
manifest_files=()
for pak_name in pak0.pak pak1.pak pak2.pak; do
  source_file="${source_baseq2}/${pak_name}"
  target_file="${destination}/${pak_name}"
  [[ -f "${source_file}" ]] || continue

  if [[ -e "${target_file}" || -L "${target_file}" ]]; then
    if [[ ! -L "${target_file}" || "$(readlink -f "${target_file}")" != "$(readlink -f "${source_file}")" ]]; then
      echo "Refusing to replace existing data path: ${target_file}" >&2
      exit 1
    fi
  else
    ln -s "${source_file}" "${target_file}"
  fi
  manifest_files+=("${target_file}")
done

node "${repo_dir}/scripts/write-manifest.mjs" data \
  "${destination}/asset-manifest.json" "${destination}" "${manifest_files[@]}"

echo "Validated owner-provided Quake II data:"
printf '  %s\n' "${manifest_files[@]}"
echo "Local manifest: ${destination}/asset-manifest.json"
