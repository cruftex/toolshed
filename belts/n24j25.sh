#!/usr/bin/env bash
# Source this file to activate the Node 24 and Java 25 profiles.
_toolshed_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n ${_toolshed_belt_path_added:-} ]]; then
    IFS=: read -r -a _belt_path_parts <<< "$PATH"
    IFS=: read -r -a _belt_old_parts <<< "$_toolshed_belt_path_added"
    for _belt_old in "${_belt_old_parts[@]}"; do
        for _belt_i in "${!_belt_path_parts[@]}"; do
            if [[ ${_belt_path_parts[_belt_i]} == "$_belt_old" ]]; then
                unset '_belt_path_parts[_belt_i]'
                break
            fi
        done
    done
    PATH="$(IFS=:; echo "${_belt_path_parts[*]}")"
fi
_belt_before=":$PATH:"
source "$_toolshed_dir/profile.d/node24.sh"
source "$_toolshed_dir/profile.d/java25.sh"
_toolshed_belt_path_added=
IFS=: read -r -a _belt_path_parts <<< "$PATH"
for _belt_part in "${_belt_path_parts[@]}"; do
    if [[ -n $_belt_part && $_belt_before != *":$_belt_part:"* ]]; then
        _toolshed_belt_path_added="${_toolshed_belt_path_added:+$_toolshed_belt_path_added:}$_belt_part"
    fi
done
unset _toolshed_dir _belt_before _belt_path_parts _belt_old_parts _belt_old _belt_i _belt_part
