#!/usr/bin/env bash
# Unit tests for lib/provenance.sh: TLS details, minimal-diff provenance records and canonical order.
set -euo pipefail
source <(knockout.sh fn-suite)
source "$TESTSUITE_DIR/../../lib/install.sh"
source "$TESTSUITE_DIR/../../lib/tool.sh"
source "$TESTSUITE_DIR/../../lib/records.sh"
source "$TESTSUITE_DIR/../../lib/provenance.sh"
source "$TESTSUITE_DIR/lib/helpers.sh"
fixture="$TESTSUITE_DIR/../fixtures/tls/certs.peer"
source_url=https://downloads.example.test/checksum

# Write a peer file with IP and URL, optionally followed by the fixture's certificates.
peer_file() {
    printf '%s\n%s\n' "$1" "$2" > "$case_dir/peer"
    [[ ${3:-} != certs ]] || tail -n +3 -- "$fixture" >> "$case_dir/peer"
}

provenance() {
    jq -c "$1" "$repo/metadata/provenance/demo.json"
}

t_tls_details_of_leaf_and_issuer() {
    echo "# the leaf certificate's signer, fingerprint and validity, and the issuer's fingerprint"
    assert_eq "$(provenance_tls "$fixture" | jq -c .)" \
        '{"subject":"CN=downloads.example.test","issuer":"CN=Toolshed Test CA,O=Toolshed Test,C=XX","serial":"1234abcd","not_before":"2026-11-19T02:04:06Z","not_after":"2095-05-01T02:04:06Z","sha256":"65ee1c15c5411d8d1468fd84fed215ad13df7b8d29b414c89765af2d9bc2f873","issuer_sha256":"21a639475a51d54695077e77f90737f285efa35d5c86b4881b74e9ef6f1e9ca8"}' tls
}

t_tls_absent_without_certificates() {
    echo "# a peer file without certificates yields no TLS details"
    setup_repo
    peer_file 192.0.2.1 "$source_url"
    assert_eq "$(provenance_tls "$case_dir/peer")" '' tls
}

t_tls_leaf_only_has_null_issuer_fingerprint() {
    echo "# a single certificate has no issuer fingerprint"
    setup_repo
    sed '/^Subject:C = XX/,$d' "$fixture" > "$case_dir/peer"
    assert_eq "$(provenance_tls "$case_dir/peer" | jq -c .issuer_sha256)" null issuer_sha256
}

t_new_entry_with_peer_and_tls() {
    echo "# a new entry has the recorded discovery time, peer details and TLS certificate"
    setup_repo
    peer_file 192.0.2.10 "$source_url/final" certs
    record_provenance demo 1.2.10/linux-x64 "$source_url" "$case_dir/peer"
    assert_eq "$(provenance '.["1.2.10/linux-x64"] | [.discovered_at, .checksum_url, .effective_url, .peer_ip, .tls.sha256, has("peer_observed_at")]')" \
        '["2026-11-18T00:00:00Z","https://downloads.example.test/checksum","https://downloads.example.test/checksum/final","192.0.2.10","65ee1c15c5411d8d1468fd84fed215ad13df7b8d29b414c89765af2d9bc2f873",false]' entry
}

t_newest_version_is_prepended_as_pure_addition() {
    echo "# discovering a newer version only adds lines at the top"
    setup_repo
    peer_file 192.0.2.10 "$source_url" certs
    record_provenance demo 1.2.9/linux-x64 "$source_url" "$case_dir/peer"
    cp -- "$repo/metadata/provenance/demo.json" "$case_dir/before.json"
    record_provenance demo 1.2.10/linux-x64 "$source_url" "$case_dir/peer"
    assert_eq "$(jq -r 'keys_unsorted | join(" ")' "$repo/metadata/provenance/demo.json")" '1.2.10/linux-x64 1.2.9/linux-x64' order
    ! diff -- "$case_dir/before.json" "$repo/metadata/provenance/demo.json" | grep -q '^<' || fail 'existing lines changed'
}

t_complete_entry_is_left_untouched() {
    echo "# rediscovering a recorded version changes nothing, even from another peer"
    setup_repo
    peer_file 192.0.2.10 "$source_url" certs
    record_provenance demo 1.2.10/linux-x64 "$source_url" "$case_dir/peer"
    cp -p -- "$repo/metadata/provenance/demo.json" "$case_dir/before.json"
    peer_file 192.0.2.99 "$source_url/other"
    _discovery_timestamp=2027-01-01T00:00:00Z
    record_provenance demo 1.2.10/linux-x64 "$source_url" "$case_dir/peer"
    cmp -s -- "$case_dir/before.json" "$repo/metadata/provenance/demo.json" || fail 'complete entry rewritten'
    [[ ! $repo/metadata/provenance/demo.json -nt $case_dir/before.json ]] || fail 'unchanged file replaced'
}

t_missing_peer_details_are_completed() {
    echo "# missing peer details are filled in once, with the observation time and TLS details"
    setup_repo
    printf '{"1.2.10/linux-x64":{"checksum_url":"%s","discovered_at":"2026-11-18T00:00:00Z","effective_url":null,"peer_ip":null}}' \
        "$source_url" > "$repo/metadata/provenance/demo.json"
    peer_file 192.0.2.5 "$source_url/final" certs
    record_provenance demo 1.2.10/linux-x64 "$source_url" "$case_dir/peer"
    assert_eq "$(provenance '.["1.2.10/linux-x64"] | [.peer_ip, .effective_url, .peer_observed_at, .tls.issuer]')" \
        '["192.0.2.5","https://downloads.example.test/checksum/final","2026-11-19T10:00:00Z","CN=Toolshed Test CA,O=Toolshed Test,C=XX"]' entry
}

t_other_checksum_source_is_not_overwritten() {
    echo "# peer details observed for a different checksum URL are not attributed to the entry"
    setup_repo
    printf '{"1.2.10/linux-x64":{"checksum_url":"https://other.test/x","discovered_at":"2026-11-18T00:00:00Z","effective_url":null,"peer_ip":null}}' \
        > "$repo/metadata/provenance/demo.json"
    peer_file 192.0.2.5 "$source_url" certs
    record_provenance demo 1.2.10/linux-x64 "$source_url" "$case_dir/peer"
    assert_eq "$(provenance '.["1.2.10/linux-x64"] | [.checksum_url, .peer_ip, has("tls")]')" '["https://other.test/x",null,false]' entry
}

t_authoritative_timestamp_replaces_discovered_at() {
    echo "# the artifact table's discovery time wins over a provenance time"
    setup_repo
    printf '{"1.2.10/linux-x64":{"checksum_url":"%s","discovered_at":"2026-12-01T00:00:00Z","effective_url":"%s","peer_ip":"192.0.2.5"}}' \
        "$source_url" "$source_url" > "$repo/metadata/provenance/demo.json"
    peer_file 192.0.2.5 "$source_url"
    record_provenance demo 1.2.10/linux-x64 "$source_url" "$case_dir/peer"
    assert_eq "$(provenance '.["1.2.10/linux-x64"] | [.discovered_at, has("peer_observed_at")]')" '["2026-11-18T00:00:00Z",false]' entry
}

t_invalid_peer_and_missing_peer_file_are_null() {
    echo "# an unparsable peer IP or a missing peer file records nulls"
    setup_repo
    peer_file 'not an ip' ''
    record_provenance demo 1.2.10/linux-x64 "$source_url" "$case_dir/peer"
    record_provenance demo 1.2.9/linux-x64 "$source_url" "$case_dir/missing"
    assert_eq "$(provenance '[.[] | [.peer_ip, .effective_url, has("tls")]]')" '[[null,null,false],[null,null,false]]' entries
}

t_missing_discovery_timestamp_fails() {
    echo "# provenance needs the artifact's recorded discovery time"
    setup_repo
    peer_file 192.0.2.5 "$source_url"
    ! (record_provenance demo 1.3.0/linux-x64 "$source_url" "$case_dir/peer") 2>/dev/null || fail 'missing timestamp accepted'
    [[ ! -e $repo/metadata/provenance/demo.json ]] || fail 'file written'
}

t_canonical_order_is_numeric_newest_first() {
    echo "# versions sort numerically, newest first, then by platform; keys sort inside entries"
    assert_eq "$(jq -n '{"2.1.9/linux-x64":{"b":1,"a":2},"2.1.10/linux-x64":{},"2.1.10/darwin-x64":{},"10.0.0/linux-x64":{}}' |
        provenance_canonical | jq -c '[keys_unsorted, (.[] | keys_unsorted)]')" \
        '[["10.0.0/linux-x64","2.1.10/darwin-x64","2.1.10/linux-x64","2.1.9/linux-x64"],[],[],[],["a","b"]]' order
}

t_canonical_order_handles_four_part_versions() {
    echo "# a patch release (25.0.5.1) is newer than its update (25.0.5) and older than the next update"
    assert_eq "$(jq -n '{"25.0.5/linux-x64":{},"25.0.5.1/linux-x64":{},"25.0.6/linux-x64":{},"25.0.0/linux-x64":{}}' |
        provenance_canonical | jq -c keys_unsorted)" \
        '["25.0.6/linux-x64","25.0.5.1/linux-x64","25.0.5/linux-x64","25.0.0/linux-x64"]' order
}

t_repository_provenance_is_canonical() {
    echo "# every checked-in provenance file is in canonical order"
    local file
    for file in "$TESTSUITE_DIR"/../../metadata/provenance/*.json; do
        cmp -s -- "$file" <(provenance_canonical < "$file") || fail "not canonical: ${file##*/}"
    done
}

testsuite_main "$@"
