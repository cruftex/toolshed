#!/usr/bin/env bash
# Discovery records in metadata/artifacts/<table>.psv. Functions only; source after lib/tool.sh.
# Reads use awk; validating and writing the PSV stays in lib/artifact_metadata.py.

# Set record_table, record_version and record_artifact for NAME (a tool or component alias such as
# codex-code-mode-host) and KEY (VERSION/PLATFORM or VERSION/license).
record_location() {
    local name=$1 platform=${2#*/} owner=$1 component='' file pair archive
    [[ $2 == */* && $platform != */* ]] || _installer_fail "Invalid discovery key: $2"
    record_version=${2%%/*}
    for file in "$toolshed_root"/tools/*.sh; do
        for pair in $(descriptor_value "$file" components ''); do
            [[ ${pair#*=} != "$name" ]] || { owner=$(basename -- "$file" .sh); component=${pair%%=*}; }
        done
    done
    file="$toolshed_root/tools/$owner.sh"
    [[ -f $file ]] || _installer_fail "Unknown tool: $owner"
    record_table="$toolshed_root/metadata/artifacts/$(descriptor_value "$file" table "$owner").psv"
    if [[ $platform == license ]]; then
        record_artifact="$component/license"
        return
    fi
    platform=${platform/linux_/linux-}
    platform=${platform/darwin_/darwin-}
    platform=${platform/amd64/x64}
    platform=${platform/arm64/aarch64}
    archive=$(descriptor_value "$file" archive tar.gz)
    [[ $archive == binary ]] || archive="archive/$archive"
    record_artifact="$component/$platform/$archive"
}

# Print FIELD (3 = sha256, 4 = discovered_at) of the located record. Status 1: no record, 2: duplicates.
recorded_field() {
    [[ -f $record_table ]] || return 1
    awk -F'|' -v v="$record_version" -v a="$record_artifact" -v f="$1" \
        '$1 == v && $2 == a {print $f; n++} END {exit n > 1 ? 2 : !n}' "$record_table"
}

# Fail if NAME's KEY already has a different recorded SHA256.
check_recorded_checksums() {
    local recorded status=0
    record_location "$1" "$2"
    recorded=$(recorded_field 3) || status=$?
    (( status != 2 )) || _installer_fail "Duplicate artifact metadata: $1 $2"
    (( status != 0 )) || [[ $recorded == "$3" ]] || _installer_fail "Conflicting archive metadata: $1 $2"
}

# Record NAME's KEY with SHA256 (may be empty for Claude), keeping an existing discovery time.
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
