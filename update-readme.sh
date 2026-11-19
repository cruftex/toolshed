#!/usr/bin/env bash
# Refresh the recorded tools table in README.md (between the tools-table markers) without network access.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/install.sh"
source "$_installer_library_dir/tool.sh"
source "$_installer_library_dir/shed.sh"
trap _installer_cleanup EXIT
readme="$toolshed_root/README.md" start='<!-- tools-table:start -->' end='<!-- tools-table:end -->'
[[ $(grep -cxF -- "$start" "$readme") == 1 && $(grep -cxF -- "$end" "$readme") == 1 &&
   $(grep -nxF -- "$start" "$readme" | cut -d: -f1) -lt $(grep -nxF -- "$end" "$readme" | cut -d: -f1) ]] ||
    _installer_fail 'README must contain one ordered pair of tools table markers'
stage_directory staging "$toolshed_root"
readme_tools_table > "$staging/table"
awk -v start="$start" -v end="$end" -v table="$staging/table" '
    $0 == end { skip = 0 }
    !skip { print }
    $0 == start { while ((getline line < table) > 0) print line; skip = 1 }' "$readme" > "$staging/README.md"
chmod --reference="$readme" -- "$staging/README.md"
mv -f -- "$staging/README.md" "$readme"
