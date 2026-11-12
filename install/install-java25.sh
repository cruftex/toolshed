#!/usr/bin/env bash
# Candidate downloads and hooks use SDKMAN's verification policy; see AGENTS.md.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/install.sh"

version=25.0.5.0-oracle
java_version=25.0.5
require_platform Linux x86_64
"$_installer_library_dir/../install/install-sdkman.sh"
jdk_home="$SDKMAN_DIR/candidates/java/$version"
if ! java_is_installed "$jdk_home" "$java_version"; then
    [[ ! -e $jdk_home && ! -L $jdk_home ]] ||
        _installer_fail "Incomplete or unexpected Java installation: $jdk_home (remove it manually before retrying)."
    _installer_require curl zip unzip tar find sed
    sdkman_command install java "$version"
    java_is_installed "$jdk_home" "$java_version" || _installer_fail "Java $java_version validation failed."
fi
printf 'Java %s is installed. Select it with: sdk use java %s\n' "$java_version" "$version"
