#!/usr/bin/env bash
# Unit tests for lib/shed.sh (the `shed` commands) and the descriptor reader in lib/tool.sh.
set -euo pipefail
source <(knockout.sh fn-suite)
source "$TESTSUITE_DIR/../../lib/install.sh"
source "$TESTSUITE_DIR/../../lib/tool.sh"
source "$TESTSUITE_DIR/../../lib/records.sh"
source "$TESTSUITE_DIR/../../lib/shed.sh"
source "$TESTSUITE_DIR/lib/helpers.sh"
repository=$toolshed_root

# A repository from setup_repo plus pins and empty TOOLSHED_* directories under the case directory.
setup_shed() {
    setup_repo
    mkdir -p -- "$repo/pins" "$case_dir/bin" "$case_dir/opt" "$case_dir/nvm"
    printf '1.2.9\n' > "$repo/pins/demo"
    TOOLSHED_BIN_DIR="$case_dir/bin" TOOLSHED_OPT_DIR="$case_dir/opt" TOOLSHED_NVM_DIR="$case_dir/nvm"
}

# Write an executable script PATH with BODY.
script() {
    mkdir -p -- "${1%/*}"
    printf '#!/bin/sh\n%s\n' "$2" > "$1"
    chmod +x -- "$1"
}

t_version_in_finds_standalone_versions() {
    echo "# version_in takes the first x.y.z that is not part of a longer dotted number"
    assert_eq "$(version_in 'go version go1.27.4 linux/amd64')" 1.27.4 go
    assert_eq "$(version_in 'v24.1.0')" 24.1.0 node
    assert_eq "$(version_in 'build 1.2.3.4, release 5.6.7')" 5.6.7 dotted
    assert_eq "$(version_in 'none 1.2')" '' none
}

t_version_status_compares_numerically() {
    echo "# update status: yes, no, newer or unknown, comparing version parts as numbers"
    assert_eq "$(version_status 1.9.0 1.10.0)" yes older
    assert_eq "$(version_status 1.10.0 1.9.0)" newer newer
    assert_eq "$(version_status 2.0.0 2.0.0)" no same
    assert_eq "$(version_status '?' 2.0.0)" unknown unreadable
    assert_eq "$(version_status 2.0.0 '')" unknown unavailable
}

t_tool_settings_reads_without_sourcing() {
    echo "# tool_settings applies defaults and unquotes values, defining no hooks"
    setup_shed
    printf "kind=bin\nversion_args='version --client'\ntool_install() { :; }\n" > "$repo/tools/quoted.sh"
    tool_settings quoted
    assert_eq "${tool[version_args]}|${tool[table]}|${tool[detect]}|${tool[archive]}" 'version --client|quoted|run|tar.gz' settings
    ! has_hook tool_install || fail 'hook defined'
    ! (tool_settings Bad) 2>/dev/null || fail 'invalid name accepted'
}

t_load_tool_defines_hooks_and_drops_variables() {
    echo "# load_tool sources hooks but leaves no setting variables behind"
    setup_shed
    printf "kind=scripted\nversion_args='version --client'\ntool_install() { :; }\n" > "$repo/tools/hooked.sh"
    load_tool hooked
    has_hook tool_install || fail 'hook missing'
    [[ -z ${version_args+x} && -z ${kind+x} ]] || fail 'setting variables left behind'
    assert_eq "${tool[version_args]}" 'version --client' setting
}

t_complete_versions_need_every_component() {
    echo "# a version counts only with a digest for every component on the platform"
    setup_shed
    cat > "$repo/metadata/artifacts/multitable.psv" <<'PSV'
version|artifact|sha256|discovered_at
1.0.0|/linux-x64/archive/zip|aa|2026-01-01T00:00:00Z
1.0.0|host/linux-x64/archive/zip|bb|2026-01-02T00:00:00Z
2.0.0|/linux-x64/archive/zip|aa|2026-02-01T00:00:00Z
3.0.0|/linux-x64/archive/zip|aa|
3.0.0|host/linux-x64/archive/zip||2026-03-01T00:00:00Z
4.0.0|/darwin-x64/archive/zip|aa|2026-04-01T00:00:00Z
4.0.0|host/darwin-x64/archive/zip|bb|2026-04-01T00:00:00Z
PSV
    tool_settings multi
    assert_eq "$(complete_versions linux-x64)" '1.0.0 2026-01-02T00:00:00Z' linux
    assert_eq "$(complete_versions darwin-x64)" '4.0.0 2026-04-01T00:00:00Z' darwin
}

t_target_version_respects_delay_and_pin() {
    echo "# the newest complete version, held back until discovered DELAY days ago unless pinned"
    setup_shed
    tool_settings demo
    assert_eq "$(target_version)" 1.3.0 newest
    printf '1.2.10|/linux-x64/archive/tar.gz|2222222222222222222222222222222222222222222222222222222222222222|%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$case_dir/row"
    sed -i '3d' "$repo/metadata/artifacts/demo.psv"
    cat "$case_dir/row" >> "$repo/metadata/artifacts/demo.psv"
    assert_eq "$(target_version 8)" 1.2.9 delayed
    printf '1.2.10\n' > "$repo/pins/demo"
    assert_eq "$(target_version 8)" 1.2.10 pinned
    rm -- "$repo/metadata/artifacts/demo.psv"
    assert_eq "$(target_version)" '' 'no records'
}

t_target_version_for_claude_uses_release_list() {
    echo "# Claude's versions come from metadata/claude-versions and its pin"
    setup_shed
    printf 'kind=scripted\n' > "$repo/tools/claude.sh"
    printf '2.1.9\n' > "$repo/pins/claude"
    printf '2.1.10\nbad\n2.1.8\n' > "$repo/metadata/claude-versions"
    tool_settings claude
    assert_eq "$(target_version)" 2.1.10 latest
    assert_eq "$(target_version 8)" 2.1.9 delayed
}

t_recorded_versions_lists_all_platforms() {
    echo "# shed available lists the pin and every recorded non-license version, ascending"
    setup_shed
    printf '1.2.8\n' > "$repo/pins/demo"
    printf '2.0.0|/license|aa|\n2.1.0|/darwin-x64/archive/tar.gz|aa|\n' >> "$repo/metadata/artifacts/demo.psv"
    tool_settings demo
    assert_eq "$(recorded_versions | paste -sd, -)" 1.2.8,1.2.9,1.2.10,1.3.0,2.1.0 versions
    tool[version_prefix]=1.2.
    assert_eq "$(recorded_versions | paste -sd, -)" 1.2.8,1.2.9,1.2.10 prefix
}

t_detect_run() {
    echo "# run: the version printed by the executable, ? on failure, nothing when absent"
    setup_shed
    printf "kind=bin\nversion_args='version --short'\nversion_env=DEMO_FLAG=on\n" > "$repo/tools/demo.sh"
    tool_settings demo
    assert_eq "$(detect_version)" '' absent
    script "$case_dir/bin/demo" '[ "$1 $2 $DEMO_FLAG" = "version --short on" ] && echo "demo v1.2.3 (abc)"'
    assert_eq "$(detect_version)" 1.2.3 version
    script "$case_dir/bin/demo" 'echo no version'
    assert_eq "$(detect_version)" '?' unreadable
    script "$case_dir/bin/demo" 'echo 1.2.3; exit 1'
    assert_eq "$(detect_version)" '?' failing
}

t_detect_digest() {
    echo "# digest: the recorded version whose binary digest matches the installed bytes"
    setup_shed
    printf 'kind=bin\ndetect=digest\narchive=binary\n' > "$repo/tools/demo.sh"
    script "$case_dir/bin/demo" 'exit 0'
    local digest
    digest=$(sha256sum < "$case_dir/bin/demo")
    printf '1.4.0|/linux-x64/binary|%s|\n' "${digest%% *}" >> "$repo/metadata/artifacts/demo.psv"
    tool_settings demo
    assert_eq "$(detect_version)" 1.4.0 match
    printf 'changed\n' >> "$case_dir/bin/demo"
    assert_eq "$(detect_version)" '?' modified
}

t_detect_link_and_dirs() {
    echo "# link: the linked package version; dirs: the newest version directory"
    setup_shed
    printf 'kind=opt\ndetect=link\n' > "$repo/tools/demo.sh"
    script "$case_dir/opt/demo/1.0.6/bin/demo" 'exit 0'
    ln -s -- "$case_dir/opt/demo/1.0.6/bin/demo" "$case_dir/bin/demo"
    tool_settings demo
    assert_eq "$(detect_version)" 1.0.6 link
    script "$case_dir/elsewhere/demo" 'exit 0'
    ln -sfn -- "$case_dir/elsewhere/demo" "$case_dir/bin/demo"
    assert_eq "$(detect_version)" '?' foreign
    tool[detect]=dirs
    mkdir -p -- "$case_dir/opt/demo/1.0.10" "$case_dir/opt/demo/latest"
    assert_eq "$(detect_version)" 1.0.10 dirs
    rm -rf -- "$case_dir/opt/demo"
    assert_eq "$(detect_version)" '' none
}

t_detect_nvm_and_node() {
    echo "# nvm: the sourced nvm's version; node: the newest Node.js release of the line"
    setup_shed
    printf 'kind=scripted\ndetect=nvm\n' > "$repo/tools/nvm.sh"
    printf 'kind=scripted\ndetect=node\n' > "$repo/tools/node24.sh"
    tool_settings nvm
    assert_eq "$(detect_version)" '' absent
    printf 'nvm() { echo 0.41.0; }\n' > "$case_dir/nvm/nvm.sh"
    assert_eq "$(detect_version)" 0.41.0 nvm
    tool_settings node24
    assert_eq "$(detect_version)" '' 'no node'
    script "$case_dir/nvm/versions/node/v24.9.0/bin/node" '[ "$1" = --version ] && echo v24.9.0'
    script "$case_dir/nvm/versions/node/v24.10.1/bin/node" '[ "$1" = --version ] && echo v24.10.1'
    script "$case_dir/nvm/versions/node/v22.1.0/bin/node" 'echo v22.1.0'
    assert_eq "$(detect_version)" 24.10.1 node
    assert_eq "$(node_versions | sort -V | paste -sd, -)" 24.9.0,24.10.1 versions
}

t_move_pin_keeps_permissions() {
    echo "# move_pin replaces the pin atomically and keeps its mode"
    setup_shed
    chmod 640 -- "$repo/pins/demo"
    move_pin demo 1.2.10
    assert_eq "$(< "$repo/pins/demo")|$(stat -c %a -- "$repo/pins/demo")" '1.2.10|640' pin
    assert_eq "$(find "$repo/pins" -name '.*' | wc -l)" 0 'temporary files'
}

t_available_and_readme_table() {
    echo "# shed available and the README table list pinned tools"
    setup_shed
    assert_eq "$(shed_available)" "TOOL         DEFAULT          RECORDED VERSIONS
demo         1.2.9            1.2.9,1.2.10,1.3.0" available
    assert_eq "$(readme_tools_table | tail -n 1)" '| [demo](tools/demo.sh) | 1.3.0 | Verified executable in bin |' readme
}

t_repository_descriptors_are_complete() {
    echo "# every descriptor parses and carries the settings its kind needs"
    local file name text
    for file in "$repository"/tools/*.sh; do
        name=${file##*/}
        name=${name%.sh}
        toolshed_root=$repository tool_settings "$name"
        text=$(< "$file")
        bash -n "$file" || fail "$name: syntax"
        case ${tool[kind]:-} in
            bin) [[ ${tool[url]:-}${tool[asset]:-} ]] || fail "$name: bin tools need url or asset"
                 [[ ${tool[archive]} == binary || ${tool[member]:-} ]] || fail "$name: archived executables need a member" ;;
            opt) [[ ${tool[url]:-} && ${tool[root]:-} && $text == *'tool_validate()'* ]] || fail "$name: opt needs url, root, tool_validate" ;;
            scripted) [[ $text == *'tool_install()'* ]] || fail "$name: scripted needs tool_install" ;;
            *) fail "$name: invalid kind ${tool[kind]:-}" ;;
        esac
        [[ ${tool[archive]} =~ ^(binary|tar\.gz|zip)$ ]] || fail "$name: archive ${tool[archive]}"
        if [[ ${tool[discover]:-} != none && ${tool[kind]} != scripted ]]; then
            [[ ${tool[license]:-} ]] || fail "$name: discoverable tools record a license"
            [[ ${tool[repo]:-} || $text == *'tool_license()'* ]] || fail "$name: no license source"
        fi
    done
}

t_repository_pins_are_recorded() {
    echo "# every pin has a descriptor and is a recorded version"
    local pin
    toolshed_root=$repository
    for pin in "$repository"/pins/*; do
        tool_settings "${pin##*/}"
        recorded_versions | grep -qxF -- "$(pinned_version "${pin##*/}")" || fail "${pin##*/}: pin not recorded"
    done
}

t_repository_component_alias() {
    echo "# codex-code-mode-host is the host component of codex"
    toolshed_root=$repository
    record_location codex-code-mode-host 1.0.0/linux-x64
    assert_eq "${record_table##*/}|$record_artifact" 'codex.psv|host/linux-x64/archive/tar.gz' alias
}

testsuite_main "$@"
