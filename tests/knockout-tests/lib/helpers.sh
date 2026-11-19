#!/usr/bin/env bash
# Shared fixtures for the Bash turbo suites; sourced once per suite, defines functions only.

# Fail the current test with a message on stderr.
fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

# Compare ACTUAL with EXPECTED, naming WHAT on failure.
assert_eq() {
    [[ $1 == "$2" ]] || fail "$3: expected [$2], got [$1]"
}

# Run in a test's subshell: a fresh repository with demo descriptors and artifact records in $repo,
# which becomes `toolshed_root`; everything is removed when the test exits.
setup_repo() {
    case_dir=$(mktemp -d "${TMPDIR:-/tmp}/toolshed test.XXXXXXXX")
    trap 'rm -rf -- "$case_dir"; _installer_cleanup' EXIT
    repo="$case_dir/repository with spaces"
    toolshed_root=$repo
    _discovery_timestamp=2026-11-19T10:00:00Z
    mkdir -p -- "$repo/tools" "$repo/metadata/artifacts" "$repo/metadata/provenance"
    printf 'kind=bin\nrepo=example/demo\n' > "$repo/tools/demo.sh"
    printf "kind=bin\ncomponents='host=multi-host'\narchive=zip\ntable=multitable\n" > "$repo/tools/multi.sh"
    cat > "$repo/metadata/artifacts/demo.psv" <<'PSV'
version|artifact|sha256|discovered_at
1.2.9|/linux-x64/archive/tar.gz|1111111111111111111111111111111111111111111111111111111111111111|2026-11-01T00:00:00Z
1.2.10|/linux-x64/archive/tar.gz|2222222222222222222222222222222222222222222222222222222222222222|2026-11-18T00:00:00Z
1.3.0|/linux-x64/archive/tar.gz|3333333333333333333333333333333333333333333333333333333333333333|
PSV
}
