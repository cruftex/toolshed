#!/usr/bin/env bash
# Unit tests for the version schemes in lib/install.sh.
set -euo pipefail
source <(knockout.sh fn-suite)
source "$TESTSUITE_DIR/../../lib/install.sh"
source "$TESTSUITE_DIR/lib/helpers.sh"

t_semver2_accepts_three_parts_only() {
    echo "# semver2: the SemVer 2.0.0 version core MAJOR.MINOR.PATCH, without pre-release or build parts"
    local version
    for version in 1.2.3 0.0.0 25.0.5 1.27.10; do
        version_valid "$version" semver2 || fail "$version rejected"
    done
    for version in 25 1.2 1.2.3.4 1.2.3-rc1 1.2.3+4 v1.2.3 '' ' 1.2.3' 1..3; do
        ! version_valid "$version" semver2 || fail "$version accepted"
    done
}

t_jdk_jep322_accepts_three_to_five_parts() {
    echo "# jdk-jep322: recorded JEP 322 versions have three to five numeric parts"
    local version
    for version in 25.0.0 25.0.5 25.0.5.1 25.0.5.1.2; do
        version_valid "$version" jdk-jep322 || fail "$version rejected"
    done
    for version in 25 25.0 25.0.5.1.2.3 25.0.5+8 25.0.5-ea 25.0.5.; do
        ! version_valid "$version" jdk-jep322 || fail "$version accepted"
    done
}

t_scheme_defaults_to_the_loaded_tool() {
    echo "# without an explicit scheme, the loaded tool's version_scheme applies (semver2 when none is loaded)"
    assert_eq "$(tool_version_scheme)" semver2 'no tool'
    ! version_valid 25.0.5.1 || fail 'four parts accepted without a tool'
    declare -gA tool=([version_scheme]=jdk-jep322)
    assert_eq "$(tool_version_scheme)" jdk-jep322 'loaded tool'
    version_valid 25.0.5.1 || fail 'four parts rejected for a jdk-jep322 tool'
    tool=()
    assert_eq "$(tool_version_scheme)" semver2 'tool without setting'
}

t_unknown_scheme_fails() {
    echo "# an unknown scheme is an error, not an invalid version"
    local error
    error=$( (version_valid 1.2.3 calver) 2>&1) && fail 'unknown scheme accepted'
    [[ $error == *'Unknown version scheme: calver'* ]] || fail "unexpected error: $error"
    ! (version_regex calver) 2>/dev/null || fail 'unknown scheme has a regex'
    error=$( (version_valid 1.2.3 semver) 2>&1) && fail 'old scheme name semver accepted'
    [[ $error == *'Unknown version scheme: semver'* ]] || fail "unexpected error: $error"
    declare -gA tool=([version_scheme]=semver)
    ! (read_version_pin java25) 2>/dev/null || fail 'descriptor with old scheme name accepted'
}

t_jdk_display_and_recorded_forms() {
    echo "# JEP 322 prints versions without trailing zero parts; records pad them to three parts"
    assert_eq "$(jdk_display_version 25.0.0)" 25 GA
    assert_eq "$(jdk_display_version 25.0.5)" 25.0.5 update
    assert_eq "$(jdk_display_version 25.0.5.1)" 25.0.5.1 patch
    assert_eq "$(jdk_display_version 25.0.5.0)" 25.0.5 'zero patch'
    assert_eq "$(jdk_display_version 25.0.10)" 25.0.10 'zero inside a part'
    assert_eq "$(jdk_recorded_version 25)" 25.0.0 'GA recorded'
    assert_eq "$(jdk_recorded_version 25.1)" 25.1.0 'interim recorded'
    assert_eq "$(jdk_recorded_version 25.0.5.1)" 25.0.5.1 'patch recorded'
}

t_java_is_installed_compares_the_printed_form() {
    echo "# java_is_installed checks a recorded version against what the JDK prints"
    local jdk
    case_dir=$(mktemp -d "${TMPDIR:-/tmp}/toolshed test.XXXXXXXX")
    trap 'rm -rf -- "$case_dir"' EXIT
    jdk="$case_dir/j d k"
    mkdir -p -- "$jdk/bin"
    printf '#!/bin/sh\necho "openjdk 25 2025-09-16 LTS"\n' > "$jdk/bin/java"
    printf '#!/bin/sh\necho "javac 25"\n' > "$jdk/bin/javac"
    chmod +x -- "$jdk/bin/java" "$jdk/bin/javac"
    java_is_installed "$jdk" 25.0.0 || fail 'GA rejected'
    ! java_is_installed "$jdk" 25.0.5 || fail 'other version accepted'
    printf '#!/bin/sh\necho "openjdk 25.0.5.1 2026-11-18 LTS"\n' > "$jdk/bin/java"
    printf '#!/bin/sh\necho "javac 25.0.5.1"\n' > "$jdk/bin/javac"
    java_is_installed "$jdk" 25.0.5.1 || fail 'patch release rejected'
    ! java_is_installed "$jdk" 25.0.5 || fail 'patch release accepted as its update'
}

testsuite_main "$@"
