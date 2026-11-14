#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
printf '%-12s %-16s %s\n' 'TOOL' 'DEFAULT' 'RECORDED VERSIONS'
for pin in "$root"/pins/*; do
    [[ -f $pin ]] || continue
    name=${pin##*/}
    default=$(cat -- "$pin")
    metadata=$name
    case $name in maven39|maven310) metadata=maven ;; esac
    versions=$default
    if [[ $name == claude && -f $root/metadata/claude-versions ]]; then
        versions=$(printf '%s\n' "$default" "$(cat "$root/metadata/claude-versions")" | sort -u | paste -sd ',' -)
    fi
    if [[ -f $root/metadata/$metadata.sh ]]; then
        versions=$(
            declare -A checksums=() archive_sha256=()
            source "$root/metadata/$metadata.sh"
            printf '%s\n' "$default"
            for key in "${!checksums[@]}"; do
                [[ $key == archive/* ]] || continue
                value=${key#archive/}
                printf '%s\n' "${value%%/*}"
            done
            for key in "${!archive_sha256[@]}"; do printf '%s\n' "${key%%/*}"; done
        )
        case $name in
            maven39) versions=$(printf '%s\n' "$versions" | awk '/^3\.9\.[0-9]+$/') ;;
            maven310) versions=$(printf '%s\n' "$versions" | awk '/^3\.10\.[0-9]+$/') ;;
        esac
        versions=$(printf '%s\n' "$versions" | sort -u | paste -sd ',' -)
    fi
    printf '%-12s %-16s %s\n' "$name" "$default" "$versions"
done
