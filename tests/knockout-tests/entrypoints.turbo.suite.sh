#!/usr/bin/env bash
# Run top-level entry points as whole scripts, so a missing toolshed_init (env, cleanup traps) fails a test.
set -euo pipefail
source <(knockout.sh fn-suite)
source "$TESTSUITE_DIR/lib/helpers.sh"
repository=$(cd -- "$TESTSUITE_DIR/../.." && pwd)

t_prepare_nvm_git_loads_env_and_cleans_up_on_failure() {
    echo "# prepare-nvm-git.sh reads env (via HOME) and removes its staged clone when git fails"
    local output status=0
    case_dir=$(mktemp -d "${TMPDIR:-/tmp}/toolshed test.XXXXXXXX")
    trap 'rm -rf -- "$case_dir"' EXIT
    mkdir -p -- "$case_dir/home" "$case_dir/stub"
    printf '#!/bin/sh\necho "stub git: $*" >&2\nexit 1\n' > "$case_dir/stub/git"
    chmod +x -- "$case_dir/stub/git"
    cd -- "$case_dir"
    output=$(HOME="$case_dir/home" PATH="$case_dir/stub:$PATH" "$repository/prepare-nvm-git.sh" 2>&1) || status=$?
    (( status != 0 )) || fail 'stub git clone did not fail the script'
    [[ $output != *'unbound variable'* ]] || fail "env not loaded: $output"
    [[ $output == *'stub git: clone --mirror'* ]] || fail "did not reach the clone: $output"
    [[ -d $case_dir/home/.cache/toolshed/downloads ]] || fail 'download cache from env not created'
    [[ ! -e $case_dir/home/.cache/toolshed/nvm-git ]] || fail 'failed clone promoted to NVM Git cache'
    local leftovers
    leftovers=$(find "$case_dir/home/.cache/toolshed" -maxdepth 1 -name 'dev-environment.*')
    [[ -z $leftovers ]] || fail "staging directory left behind: $leftovers"
}

testsuite_main "$@"
