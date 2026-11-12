#!/usr/bin/env bash
# Shared helpers for Bash installers. Source this file with `set -euo pipefail`.

_installer_library_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$_installer_library_dir/../env"
: "${DOWNLOAD_DIR:?}" "${DEST_BIN_DIR:?}" "${DEST_OPT_DIR:?}"

declare -a _installer_temp_dirs=()

_installer_cleanup() {
    local directory
    for directory in "${_installer_temp_dirs[@]}"; do
        rm -rf -- "$directory"
    done
}
trap _installer_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

_installer_fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

_installer_require() {
    local utility
    for utility in "$@"; do
        command -v "$utility" >/dev/null 2>&1 || _installer_fail "Required utility not found: $utility"
    done
}

platform_string() {
    "$_installer_library_dir/platform.sh"
}

require_platform() {
    _installer_require uname
    [[ $(uname -s) == "$1" && $(uname -m) == "$2" ]] ||
        _installer_fail "This installer requires $1 $2."
    if [[ $1 == Linux ]]; then
        _installer_require getconf
        getconf GNU_LIBC_VERSION >/dev/null 2>&1 || _installer_fail 'This installer requires glibc.'
    fi
}

_installer_check_sha256() {
    local actual
    actual=$(sha256sum < "$1") || return 1
    [[ ${actual%% *} == "$2" ]]
}

verify_sha256() {
    _installer_require sha256sum
    [[ $2 =~ ^[0-9a-f]{64}$ ]] || _installer_fail 'Expected a lowercase SHA-256 digest.'
    _installer_check_sha256 "$1" "$2" || _installer_fail "SHA-256 verification failed: $1"
}

# Check bytes and executable permission without executing an untrusted local file.
binary_is_installed() {
    _installer_require sha256sum
    [[ -f $DEST_BIN_DIR/$1 && -x $DEST_BIN_DIR/$1 ]] &&
        _installer_check_sha256 "$DEST_BIN_DIR/$1" "$2"
}

# DESTINATION is the version-specific cache path. Never trust an unchecked cache.
download_verified() {
    local url=$1 expected=$2 destination=$3 temporary
    _installer_require sha256sum
    [[ $expected =~ ^[0-9a-f]{64}$ ]] || _installer_fail 'Expected a lowercase SHA-256 digest.'
    if [[ -e $destination || -L $destination ]]; then
        [[ -f $destination ]] || _installer_fail "Not a regular file: $destination"
        verify_sha256 "$destination" "$expected"
        return
    fi

    _installer_require curl mkdir dirname mktemp mv rm
    mkdir -p -- "$(dirname -- "$destination")"
    temporary=$(mktemp -d "$(dirname -- "$destination")/.download.XXXXXXXX")
    _installer_temp_dirs+=("$temporary")
    curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 180 "$url" --output "$temporary/archive" ||
        _installer_fail "Download failed: $url"
    verify_sha256 "$temporary/archive" "$expected"
    mv -fT -- "$temporary/archive" "$destination"
}

# Extract only the requested member; return its staged path in OUTPUT_VARIABLE.
# Call directly, not in a subshell, so cleanup tracks the staging directory.
extract_zip_member() {
    local _extract_archive=$1 _extract_member=$2 _extract_directory
    local -n _extract_output=$3
    _installer_require unzip mktemp chmod rm
    _extract_directory=$(mktemp -d "${TMPDIR:-/tmp}/dev-environment.XXXXXXXX")
    _installer_temp_dirs+=("$_extract_directory")
    unzip -p "$_extract_archive" "$_extract_member" >"$_extract_directory/binary" ||
        _installer_fail "Cannot extract $_extract_member from $_extract_archive"
    [[ -s $_extract_directory/binary ]] || _installer_fail 'Extracted executable is empty.'
    chmod 755 -- "$_extract_directory/binary"
    _extract_output=$_extract_directory/binary
}

verify_version() {
    local actual
    actual=$("$1" --version) || _installer_fail "Cannot execute staged binary: $1"
    [[ $actual == "$2" ]] || _installer_fail "Expected version $2, got $actual."
}

install_binary() {
    local source=$1 name=$2 temporary
    _installer_require mkdir mktemp install mv rm
    [[ -n $name && $name != */* && $name != . && $name != .. ]] || _installer_fail 'Invalid executable name.'
    mkdir -p -- "$DEST_BIN_DIR"
    [[ ! -d $DEST_BIN_DIR/$name ]] || _installer_fail "Destination is a directory: $DEST_BIN_DIR/$name"
    temporary=$(mktemp -d "$DEST_BIN_DIR/.install.XXXXXXXX")
    _installer_temp_dirs+=("$temporary")
    install -m 755 -- "$source" "$temporary/binary"
    mv -fT -- "$temporary/binary" "$DEST_BIN_DIR/$name"
}

install_symlink() {
    local target=$1 name=$2 temporary
    _installer_require readlink
    if [[ -L $DEST_BIN_DIR/$name && $(readlink -- "$DEST_BIN_DIR/$name") == "$target" ]]; then
        return
    fi
    _installer_require mkdir mktemp ln mv rm
    [[ -n $name && $name != */* && $name != . && $name != .. ]] || _installer_fail 'Invalid symlink name.'
    mkdir -p -- "$DEST_BIN_DIR"
    [[ ! -d $DEST_BIN_DIR/$name ]] || _installer_fail "Destination is a directory: $DEST_BIN_DIR/$name"
    temporary=$(mktemp -d "$DEST_BIN_DIR/.link.XXXXXXXX")
    _installer_temp_dirs+=("$temporary")
    ln -s -- "$target" "$temporary/link"
    mv -fT -- "$temporary/link" "$DEST_BIN_DIR/$name"
}
