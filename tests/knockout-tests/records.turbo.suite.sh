#!/usr/bin/env bash
# Unit tests for lib/records.sh: locating, checking and recording discovered artifacts.
set -euo pipefail
source <(knockout.sh fn-suite)
source "$TESTSUITE_DIR/../../lib/install.sh"
source "$TESTSUITE_DIR/../../lib/tool.sh"
source "$TESTSUITE_DIR/../../lib/records.sh"
source "$TESTSUITE_DIR/lib/helpers.sh"

t_descriptor_value_unquotes_and_defaults() {
    echo "# descriptor_value reads single-word settings without sourcing"
    setup_repo
    assert_eq "$(descriptor_value "$repo/tools/multi.sh" components '')" host=multi-host components
    assert_eq "$(descriptor_value "$repo/tools/demo.sh" table demo)" demo default
}

t_location_of_tool_platform() {
    echo "# a tool's platform key maps to its own table and archive kind"
    setup_repo
    record_location demo 1.2.10/linux-x64
    assert_eq "$record_table" "$repo/metadata/artifacts/demo.psv" table
    assert_eq "$record_version" 1.2.10 version
    assert_eq "$record_artifact" /linux-x64/archive/tar.gz artifact
}

t_location_of_component_alias() {
    echo "# a component alias maps to its owner's table, archive kind and component prefix"
    setup_repo
    record_location multi-host 2.0.0/linux_amd64
    assert_eq "$record_table" "$repo/metadata/artifacts/multitable.psv" table
    assert_eq "$record_artifact" host/linux-x64/archive/zip artifact
    record_location multi-host 2.0.0/darwin_arm64
    assert_eq "$record_artifact" host/darwin-aarch64/archive/zip artifact
}

t_location_of_license() {
    echo "# license keys record <component>/license"
    setup_repo
    record_location demo 1.2.10/license
    assert_eq "$record_artifact" /license tool
    record_location multi-host 2.0.0/license
    assert_eq "$record_artifact" host/license component
}

t_location_rejects_unknown_tool_and_bad_key() {
    echo "# unknown tools and malformed keys fail"
    setup_repo
    ! (record_location nope 1.0.0/linux-x64) 2>/dev/null || fail 'unknown tool accepted'
    ! (record_location demo 1.0.0/linux-x64/x) 2>/dev/null || fail 'malformed key accepted'
}

t_check_accepts_matching_and_new_checksums() {
    echo "# matching or unrecorded checksums pass the check"
    setup_repo
    check_recorded_checksums demo 1.2.10/linux-x64 2222222222222222222222222222222222222222222222222222222222222222
    check_recorded_checksums demo 9.9.9/linux-x64 4444444444444444444444444444444444444444444444444444444444444444
    check_recorded_checksums multi-host 2.0.0/linux-x64 4444444444444444444444444444444444444444444444444444444444444444
}

t_check_rejects_conflicts_and_duplicates() {
    echo "# a different recorded checksum, or ambiguous records, fail"
    setup_repo
    local error
    error=$( (check_recorded_checksums demo 1.2.10/linux-x64 5555555555555555555555555555555555555555555555555555555555555555) 2>&1) &&
        fail 'conflict accepted'
    [[ $error == *'Conflicting archive metadata: demo 1.2.10/linux-x64'* ]] || fail "unexpected error: $error"
    sed -n 3p "$repo/metadata/artifacts/demo.psv" >> "$repo/metadata/artifacts/demo.psv"
    error=$( (check_recorded_checksums demo 1.2.10/linux-x64 2222222222222222222222222222222222222222222222222222222222222222) 2>&1) &&
        fail 'duplicate accepted'
    [[ $error == *'Duplicate artifact metadata'* ]] || fail "unexpected error: $error"
}

t_timestamp_is_read_or_missing_fails() {
    echo "# the recorded discovery time is authoritative; missing ones fail"
    setup_repo
    assert_eq "$(recorded_timestamp demo 1.2.9/linux-x64)" 2026-11-01T00:00:00Z timestamp
    ! (recorded_timestamp demo 1.3.0/linux-x64) 2>/dev/null || fail 'empty timestamp accepted'
    ! (recorded_timestamp demo 7.0.0/linux-x64) 2>/dev/null || fail 'missing record accepted'
}

t_record_round_trip() {
    echo "# record_checksums writes through artifact_metadata.py and keeps the first discovery time"
    setup_repo
    record_checksums multi-host 2.0.0/linux-x64 6666666666666666666666666666666666666666666666666666666666666666
    _discovery_timestamp=2027-01-01T00:00:00Z
    record_checksums multi-host 2.0.0/linux-x64 6666666666666666666666666666666666666666666666666666666666666666
    assert_eq "$(< "$repo/metadata/artifacts/multitable.psv")" \
        "version|artifact|sha256|discovered_at
2.0.0|host/linux-x64/archive/zip|6666666666666666666666666666666666666666666666666666666666666666|2026-11-19T10:00:00Z" table
    assert_eq "$(recorded_timestamp multi-host 2.0.0/linux-x64)" 2026-11-19T10:00:00Z timestamp
    ! (record_checksums multi-host 2.0.0/linux-x64 7777777777777777777777777777777777777777777777777777777777777777) 2>/dev/null ||
        fail 'conflicting record accepted'
}

testsuite_main "$@"
