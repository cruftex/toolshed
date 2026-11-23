#!/usr/bin/env bash
# Unit tests for the JDK checks in lib/install.sh.
set -euo pipefail
source <(knockout.sh fn-suite)
source "$TESTSUITE_DIR/../../lib/install.sh"
source "$TESTSUITE_DIR/lib/helpers.sh"

# Run in a test's subshell: a fresh fake JDK in "$jdk" (a path with spaces) whose java and javac run the shell
# commands JAVA and JAVAC; the case directory is removed when the test exits.
setup_jdk() {
    if [[ -z ${case_dir:-} ]]; then
        case_dir=$(mktemp -d "${TMPDIR:-/tmp}/toolshed test.XXXXXXXX")
        trap 'rm -rf -- "$case_dir"' EXIT
    fi
    jdk="$case_dir/j d k"
    rm -rf -- "$jdk"
    mkdir -p -- "$jdk/bin"
    printf '#!/bin/sh\n[ "$1" = -version ] || exit 2\n%s\n' "$1" > "$jdk/bin/java"
    printf '#!/bin/sh\n%s\n' "$2" > "$jdk/bin/javac"
    chmod +x -- "$jdk/bin/java" "$jdk/bin/javac"
}

t_java8_accepts_matching_update() {
    echo "# 8.0.UPDATE matches 1.8.0_UPDATE reported on stderr"
    setup_jdk "printf '%s\n' 'openjdk version \"1.8.0_514\"' 'OpenJDK Runtime Environment (Temurin)(build 1.8.0_514-b01)' >&2" \
        "echo 'javac 1.8.0_514' >&2"
    java8_is_installed "$jdk" 8.0.514 || fail 'matching JDK rejected'
}

t_java8_ignores_jvm_option_variables() {
    echo "# JAVA_TOOL_OPTIONS and friends cannot add lines to the checked output"
    setup_jdk "[ -z \"\$JAVA_TOOL_OPTIONS\$_JAVA_OPTIONS\" ] || echo 'Picked up options' >&2; echo 'openjdk version \"1.8.0_514\"' >&2" \
        "[ -z \"\$JAVA_TOOL_OPTIONS\" ] || echo 'Picked up options' >&2; echo 'javac 1.8.0_514' >&2"
    JAVA_TOOL_OPTIONS=-Xmx1g _JAVA_OPTIONS=-Xms1m java8_is_installed "$jdk" 8.0.514 || fail 'options broke the check'
}

t_java8_rejects_other_versions() {
    echo "# other updates, prefixes of the update and other version schemes fail"
    setup_jdk "echo 'openjdk version \"1.8.0_5140\"' >&2" "echo 'javac 1.8.0_514' >&2"
    ! java8_is_installed "$jdk" 8.0.514 || fail 'longer update accepted'
    setup_jdk "echo 'openjdk version \"1.8.0_514\"' >&2" "echo 'javac 1.8.0_512' >&2"
    ! java8_is_installed "$jdk" 8.0.514 || fail 'mismatched javac accepted'
    ! java8_is_installed "$jdk" 25.0.5 || fail 'Java 25 version accepted'
    ! java8_is_installed "$jdk" 8u514 || fail 'Adoptium update name accepted'
}

t_java8_rejects_incomplete_or_failing_jdk() {
    echo "# a missing javac, a non-executable java or a failing java fails"
    setup_jdk "echo 'openjdk version \"1.8.0_514\"' >&2" "echo 'javac 1.8.0_514' >&2"
    chmod -x -- "$jdk/bin/java"
    ! java8_is_installed "$jdk" 8.0.514 || fail 'non-executable java accepted'
    setup_jdk "echo 'openjdk version \"1.8.0_514\"' >&2; exit 1" "echo 'javac 1.8.0_514' >&2"
    ! java8_is_installed "$jdk" 8.0.514 || fail 'failing java accepted'
    setup_jdk "echo 'openjdk version \"1.8.0_514\"' >&2" "echo 'javac 1.8.0_514' >&2"
    rm -- "$jdk/bin/javac"
    ! java8_is_installed "$jdk" 8.0.514 || fail 'missing javac accepted'
}

testsuite_main "$@"
