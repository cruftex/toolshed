#!/usr/bin/env bash
# Unit tests for the download URL and package root of a loaded descriptor (lib/tool.sh).
set -euo pipefail
source <(knockout.sh fn-suite)
source "$TESTSUITE_DIR/../../lib/install.sh"
source "$TESTSUITE_DIR/../../lib/tool.sh"
source "$TESTSUITE_DIR/lib/helpers.sh"

# setup_repo, then load demo's settings with the extra descriptor LINES, and record a URL for 2.0.0.
setup_tool() {
    setup_repo
    TOOLSHED_OPT_DIR="$case_dir/opt"
    printf '%s\n' "$@" >> "$repo/tools/demo.sh"
    printf 'version|artifact|sha256|discovered_at|url\n' > "$repo/metadata/artifacts/demo.psv"
    printf '1.2.9|/linux-x64/archive/tar.gz|%s||\n' "$(printf '1%.0s' {1..64})" >> "$repo/metadata/artifacts/demo.psv"
    printf '2.0.0|/linux-x64/archive/tar.gz|%s||https://example.com/demo-2.0.0%%2B7.tar.gz\n' "$(printf '2%.0s' {1..64})" \
        >> "$repo/metadata/artifacts/demo.psv"
    tool_settings demo
}

t_recorded_url_wins_over_template() {
    echo "# a URL recorded for the version and platform is used; other versions expand the template"
    setup_tool "url='https://example.com/{version}/demo-{platform}.tar.gz'"
    assert_eq "$(tool_url 2.0.0 linux-x64)" 'https://example.com/demo-2.0.0%2B7.tar.gz' recorded
    assert_eq "$(tool_url 1.2.9 linux-x64)" 'https://example.com/1.2.9/demo-linux-x64.tar.gz' template
    assert_eq "$(tool_url 3.0.0 linux-x64)" 'https://example.com/3.0.0/demo-linux-x64.tar.gz' unrecorded
}

t_url_recorded_requires_a_row() {
    echo "# url=recorded fails without a recorded URL instead of guessing one"
    setup_tool url=recorded
    assert_eq "$(tool_url 2.0.0 linux-x64)" 'https://example.com/demo-2.0.0%2B7.tar.gz' recorded
    local error
    error=$( (tool_url 1.2.9 linux-x64) 2>&1) && fail 'empty URL accepted'
    [[ $error == *'No recorded URL for demo 1.2.9/linux-x64'* ]] || fail "unexpected error: $error"
    ! (tool_url 2.0.0 darwin-aarch64) 2>/dev/null || fail 'other platform accepted'
}

t_root_star_finds_the_single_top_level_directory() {
    echo "# root='*' is the one top-level directory of the extracted archive"
    setup_tool "root='*'"
    local root
    mkdir -p -- "$case_dir/x/jdk 8u514-b01/bin"
    tool_root "$case_dir/x" 8.0.514 linux-x64 root
    assert_eq "$root" 'jdk 8u514-b01' root
}

t_root_star_rejects_other_layouts() {
    echo "# root='*' fails for an empty archive, two entries, a single file or a symbolic link"
    setup_tool "root='*'"
    local root
    mkdir -p -- "$case_dir/empty" "$case_dir/two/a" "$case_dir/two/b" "$case_dir/file" "$case_dir/link" "$case_dir/dot/a"
    touch -- "$case_dir/file/a" "$case_dir/dot/.hidden"
    ln -s -- /tmp "$case_dir/link/a"
    for layout in empty two file link dot; do
        ! (tool_root "$case_dir/$layout" 1.0.0 linux-x64 root) 2>/dev/null || fail "$layout layout accepted"
    done
}

t_root_template_is_expanded_and_checked() {
    echo "# a root template is expanded and must exist"
    setup_tool "root='demo-{version}'"
    local root
    mkdir -p -- "$case_dir/x/demo-1.2.9"
    tool_root "$case_dir/x" 1.2.9 linux-x64 root
    assert_eq "$root" demo-1.2.9 root
    ! (tool_root "$case_dir/x" 1.3.0 linux-x64 root) 2>/dev/null || fail 'missing root accepted'
}

testsuite_main "$@"
