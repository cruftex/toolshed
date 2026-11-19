#!/usr/bin/env bash
# Discovery records in metadata/artifacts/<table>.psv. Functions only; source after lib/tool.sh.
# Reads use awk; validating and writing the PSV stays in lib/artifact_metadata.py.

# Set record_table, record_version and record_artifact for NAME (a tool or component alias such as
# codex-code-mode-host) and KEY (VERSION/PLATFORM or VERSION/license).
record_location() {
    local name=$1 platform=${2#*/} owner=$1 component='' found file archive
    local -A settings=()
    [[ $2 == */* && $platform != */* ]] || _installer_fail "Invalid discovery key: $2"
    record_version=${2%%/*}
    # One pass over all descriptors: the first `components=` pair COMPONENT=ALIAS naming NAME gives its owner.
    found=$(awk -v name="$name" '/^components=/ {
            value = substr($0, 12); gsub(/[\047"]/, "", value)
            n = split(value, pairs, " ")
            for (i = 1; i <= n; i++) if (substr(pairs[i], index(pairs[i], "=") + 1) == name) {
                file = FILENAME; sub(/.*\//, "", file); sub(/\.sh$/, "", file)
                print file, substr(pairs[i], 1, index(pairs[i], "=") - 1); exit
            } }' "$toolshed_root"/tools/*.sh)
    [[ -z $found ]] || read -r owner component <<< "$found"
    file="$toolshed_root/tools/$owner.sh"
    [[ -f $file ]] || _installer_fail "Unknown tool: $owner"
    descriptor_read "$file" settings
    record_table="$toolshed_root/metadata/artifacts/${settings[table]-$owner}.psv"
    if [[ $platform == license ]]; then
        record_artifact="$component/license"
        return
    fi
    platform=${platform/linux_/linux-}
    platform=${platform/darwin_/darwin-}
    platform=${platform/amd64/x64}
    platform=${platform/arm64/aarch64}
    archive=${settings[archive]-tar.gz}
    [[ $archive == binary ]] || archive="archive/$archive"
    record_artifact="$component/$platform/$archive"
}

# Print FIELD (3 = sha256, 4 = discovered_at) of the located record. Status 1: no record, 2: duplicates.
recorded_field() {
    [[ -f $record_table ]] || return 1
    awk -F'|' -v v="$record_version" -v a="$record_artifact" -v f="$1" \
        '$1 == v && $2 == a {print $f; n++} END {exit n > 1 ? 2 : !n}' "$record_table"
}

# Fail if NAME's KEY already has a different recorded SHA256 (an empty recorded digest is not yet known).
check_recorded_checksums() {
    local recorded status=0
    record_location "$1" "$2"
    recorded=$(recorded_field 3) || status=$?
    (( status != 2 )) || _installer_fail "Duplicate artifact metadata: $1 $2"
    (( status != 0 )) || [[ -z $recorded || $recorded == "$3" ]] || _installer_fail "Conflicting archive metadata: $1 $2"
}

# Record NAME's KEY with SHA256, keeping an existing discovery time.
record_checksums() {
    check_recorded_checksums "$1" "$2" "$3"
    python3 "$_installer_library_dir/artifact_metadata.py" record \
        "$record_table" "$record_version" "$record_artifact" "$3" "$_discovery_timestamp"
}

# Print the authoritative discovery time of NAME's KEY.
recorded_timestamp() {
    local timestamp
    record_location "$1" "$2"
    timestamp=$(recorded_field 4) && [[ $timestamp ]] || _installer_fail "Missing discovery timestamp: $1 $2"
    printf '%s\n' "$timestamp"
}
