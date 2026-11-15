#!/usr/bin/env bash
# Shared helpers for Bash installers. Source this file with `set -euo pipefail`.

_installer_library_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$_installer_library_dir/../env"
: "${TOOLSHED_DOWNLOAD_DIR:?}" "${TOOLSHED_BIN_DIR:?}" "${TOOLSHED_OPT_DIR:?}"

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

# Read repository-owned pins and paired archive/executable metadata.
read_version_pin() {
    local value
    value=$(cat "$_installer_library_dir/../pins/$1")
    [[ $value =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || _installer_fail "Invalid version pin: $1"
    printf '%s\n' "$value"
}

# An explicit environment selection does not change the repository pin.
select_install_version() {
    local tool=$1
    shift
    (( $# == 0 )) || _installer_fail 'Unexpected installer arguments.'
    if [[ ${TOOLSHED_OVERRIDE_TOOL_VERSION+x} ]]; then
        [[ $TOOLSHED_OVERRIDE_TOOL_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || _installer_fail 'Invalid TOOLSHED_OVERRIDE_TOOL_VERSION.'
        printf '%s\n' "$TOOLSHED_OVERRIDE_TOOL_VERSION"
    else
        read_version_pin "$tool"
    fi
}

artifact_checksum() {
    local tool=$1 version=$2 artifact=$3
    python3 "$_installer_library_dir/artifact_metadata.py" checksum \
        "$_installer_library_dir/../metadata/artifacts/$tool.psv" "$version" "$artifact"
}

load_archive_checksum() {
    local tool=$1 version=$2 platform=$3 digest
    digest=$(artifact_checksum "$tool" "$version" "/$platform/archive/tar.gz") || return 1
    declare -gA archive_sha256=()
    archive_sha256[$version/$platform]=$digest
}

# Check bytes and executable permission without executing an untrusted local file.
binary_is_installed() {
    _installer_require sha256sum
    [[ -f $TOOLSHED_BIN_DIR/$1 && -x $TOOLSHED_BIN_DIR/$1 ]] &&
        _installer_check_sha256 "$TOOLSHED_BIN_DIR/$1" "$2"
}

warn_if_modified() {
    local name=$1 expected=$2 path="$TOOLSHED_BIN_DIR/$1"
    if [[ -f $path ]] && ! _installer_check_sha256 "$path" "$expected"; then
        printf 'WARNING: installed %s differs from the verified executable.\n' "$name" >&2
    fi
}

# Preserve the HTTPS host and path as cache directories, rejecting ambiguous paths.
cache_path() {
    local path=${1#https://} target=${2:-}
    [[ $1 == https://* && $path =~ ^[a-zA-Z0-9._~%-]+(/[a-zA-Z0-9._~%-]+)+$ && /$path/ != */../* && /$path/ != */./* ]] ||
        _installer_fail "Unsupported cache URL: $1"
    [[ $target ]] || target=$(platform_string)
    [[ $target =~ ^(linux|darwin)-(x64|aarch64)$ ]] || _installer_fail "Unsupported cache platform: $target"
    printf '%s/%s/%s\n' "$TOOLSHED_DOWNLOAD_DIR" "$target" "$path"
}

# DESTINATION is the version-specific cache path. Never trust an unchecked cache.
migrate_verified_cache() {
    local legacy=$1 destination=$2 expected=$3 temporary
    [[ -e $legacy || -L $legacy ]] || return 1
    [[ -f $legacy ]] || _installer_fail "Not a regular file: $legacy"
    verify_sha256 "$legacy" "$expected"
    mkdir -p -- "$(dirname -- "$destination")" || _installer_fail 'Cannot create cache directory.'
    stage_directory temporary "$(dirname -- "$destination")" || _installer_fail 'Cannot stage cached archive.'
    cp -- "$legacy" "$temporary/archive" || _installer_fail 'Cannot copy cached archive.'
    verify_sha256 "$temporary/archive" "$expected"
    [[ ! -e $destination && ! -L $destination ]] || _installer_fail "Cache destination appeared during staging: $destination"
    mv -T -- "$temporary/archive" "$destination" || _installer_fail 'Cannot promote cached archive.'
}

download_verified() {
    local url=$1 expected=$2 destination=$3 temporary legacy
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
    legacy="$TOOLSHED_DOWNLOAD_DIR/${url#https://}"
    if [[ $legacy != "$destination" && ( -e $legacy || -L $legacy ) ]]; then
        [[ -f $legacy ]] || _installer_fail "Not a regular file: $legacy"
        verify_sha256 "$legacy" "$expected"
        cp -- "$legacy" "$temporary/archive"
    else
        _installer_download "$url" "$temporary/archive" ||
            _installer_fail "Download failed: $url"
    fi
    verify_sha256 "$temporary/archive" "$expected"
    mv -fT -- "$temporary/archive" "$destination"
}

_installer_download() {
    _installer_require curl
    if [[ ${_toolshed_capture_peer:-} == 1 ]]; then
        local peer
        peer=$(curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
            --connect-timeout 15 --max-time 600 --write-out '%{remote_ip}\n%{url_effective}\n' "$1" --output "$2") || return
        printf '%s\n' "$peer" > "$2.peer"
    else
        curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
            --connect-timeout 15 --max-time 600 "$1" --output "$2"
    fi
}

# Call directly so the library can clean up the staging directory.
stage_directory() {
    local _stage_path
    local -n _stage_output=$1
    _installer_require mktemp rm
    _stage_path=$(mktemp -d "${2:-${TMPDIR:-/tmp}}/dev-environment.XXXXXXXX")
    _installer_temp_dirs+=("$_stage_path")
    _stage_output=$_stage_path
}

verify_gpg_signature() {
    local data=$1 signature=$2 key=$3 fingerprint=$4 directory actual
    _installer_require gpg awk
    stage_directory directory
    actual=$(gpg --no-options --no-autostart --homedir "$directory" --batch --with-colons --show-keys "$key" |
        awk -F: '$1 == "fpr" {print $10; exit}') || _installer_fail 'Cannot read signing key.'
    [[ -n $fingerprint && $actual == "$fingerprint" ]] || _installer_fail 'Invalid signing key fingerprint.'
    gpg --no-options --no-autostart --homedir "$directory" --batch --quiet --import "$key"
    gpg --no-options --no-autostart --homedir "$directory" --batch --status-fd 1 \
        --verify "$signature" "$data" >"$directory/status" ||
        _installer_fail 'Manifest signature verification failed.'
    # A downloaded key file could contain extra keys. Require the pinned signer.
    awk -v expected="$fingerprint" '
        $1 == "[GNUPG:]" && $2 == "VALIDSIG" && ($3 == expected || $NF == expected) { valid = 1 }
        END { exit !valid }
    ' "$directory/status" || _installer_fail 'Manifest was not signed by the expected key.'
}

# Resolve the moving release pointer without treating it as trusted metadata.
resolve_latest_version() {
    local _latest_directory _latest_value
    local -n _latest_output=$2
    stage_directory _latest_directory
    _installer_download "$1" "$_latest_directory/latest"
    _latest_value=$(cat -- "$_latest_directory/latest")
    [[ $_latest_value =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || _installer_fail 'Invalid latest release version.'
    _latest_output=$_latest_value
}

# Cache only authenticated metadata, and reverify it whenever it is reused.
download_signed_manifest() {
    local url=$1 key_url=$2 fingerprint=$3 destination=$4 directory legacy
    _installer_require mkdir dirname mv
    if [[ -e $destination || -L $destination ]]; then
        verify_gpg_signature "$destination/manifest.json" "$destination/manifest.json.sig" \
            "$destination/key.asc" "$fingerprint"
        return
    fi
    mkdir -p -- "$(dirname -- "$destination")"
    stage_directory directory "$(dirname -- "$destination")"
    legacy="$(dirname -- "$TOOLSHED_DOWNLOAD_DIR/${url#https://}")/manifest"
    if [[ $legacy != "$destination" && -d $legacy ]]; then
        verify_gpg_signature "$legacy/manifest.json" "$legacy/manifest.json.sig" "$legacy/key.asc" "$fingerprint"
        cp -a -- "$legacy/." "$directory/"
    else
        _installer_download "$url" "$directory/manifest.json"
        _installer_download "$url.sig" "$directory/manifest.json.sig"
        _installer_download "$key_url" "$directory/key.asc"
    fi
    verify_gpg_signature "$directory/manifest.json" "$directory/manifest.json.sig" "$directory/key.asc" "$fingerprint"
    mv -T -- "$directory" "$destination"
}

# Read a checksum only after authenticating the manifest with its pinned key.
manifest_checksum() {
    _installer_require python3
    python3 - "$1" "$2" "$3" <<'PYTHON'
import json
import re
import sys

with open(sys.argv[1]) as f:
    manifest = json.load(f)
if manifest["version"] != sys.argv[2]:
    sys.exit("Error: Signed manifest version does not match the requested release.")
checksum = manifest["platforms"][sys.argv[3]]["checksum"]
if not re.fullmatch(r"[0-9a-f]{64}", checksum):
    sys.exit("Error: Invalid SHA-256 in signed manifest.")
print(checksum)
PYTHON
}

stage_executable() {
    local _stage_source=$1 _stage_directory
    local -n _stage_binary=$2
    _installer_require install
    stage_directory _stage_directory
    install -m 755 -- "$_stage_source" "$_stage_directory/binary"
    _stage_binary=$_stage_directory/binary
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

# Extract one tar member into a staged executable; return its path in OUTPUT_VARIABLE. Call directly.
extract_tar_member() {
    local _tar_archive=$1 _tar_member=$2 _tar_directory
    local -n _tar_output=$3
    _installer_require tar chmod
    stage_directory _tar_directory
    tar -xOzf "$_tar_archive" "$_tar_member" > "$_tar_directory/binary" ||
        _installer_fail "Cannot extract $_tar_member from $_tar_archive"
    [[ -s $_tar_directory/binary ]] || _installer_fail 'Extracted executable is empty.'
    chmod 755 -- "$_tar_directory/binary"
    _tar_output=$_tar_directory/binary
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
    mkdir -p -- "$TOOLSHED_BIN_DIR"
    [[ ! -d $TOOLSHED_BIN_DIR/$name ]] || _installer_fail "Destination is a directory: $TOOLSHED_BIN_DIR/$name"
    temporary=$(mktemp -d "$TOOLSHED_BIN_DIR/.install.XXXXXXXX")
    _installer_temp_dirs+=("$temporary")
    install -m 755 -- "$source" "$temporary/binary"
    mv -fT -- "$temporary/binary" "$TOOLSHED_BIN_DIR/$name"
}

install_symlink() {
    local target=$1 name=$2 temporary
    _installer_require readlink
    if [[ -L $TOOLSHED_BIN_DIR/$name && $(readlink -- "$TOOLSHED_BIN_DIR/$name") == "$target" ]]; then
        return
    fi
    _installer_require mkdir mktemp ln mv rm
    [[ -n $name && $name != */* && $name != . && $name != .. ]] || _installer_fail 'Invalid symlink name.'
    mkdir -p -- "$TOOLSHED_BIN_DIR"
    [[ ! -d $TOOLSHED_BIN_DIR/$name ]] || _installer_fail "Destination is a directory: $TOOLSHED_BIN_DIR/$name"
    temporary=$(mktemp -d "$TOOLSHED_BIN_DIR/.link.XXXXXXXX")
    _installer_temp_dirs+=("$temporary")
    ln -s -- "$target" "$temporary/link"
    mv -fT -- "$temporary/link" "$TOOLSHED_BIN_DIR/$name"
}

# Preserve other JSON settings and permissions; replace the file atomically.
set_json_env() {
    _installer_require python3 mkdir dirname
    mkdir -p -- "$(dirname -- "$1")"
    python3 - "$1" "$2" "$3" <<'PY'
import json
import os
import stat
import sys
import tempfile

path, key, value = sys.argv[1:]
if os.path.exists(path):
    with open(path) as f:
        settings = json.load(f)
    mode = stat.S_IMODE(os.stat(path).st_mode)
else:
    settings = {}
    mode = 0o600
settings.setdefault("env", {})[key] = value

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
try:
    os.fchmod(fd, mode)
    with os.fdopen(fd, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY
}

java_is_installed() {
    local jdk_home=$1 expected=$2 output
    [[ -x $jdk_home/bin/java && -x $jdk_home/bin/javac ]] || return 1
    output=$("$jdk_home/bin/java" --version) || return 1
    [[ $output == "java $expected "* || $output == "openjdk $expected "* ]] || return 1
    output=$("$jdk_home/bin/javac" -version) || return 1
    [[ $output == "javac $expected" ]]
}

maven_is_installed() {
    local home=$1 expected=$2 output
    [[ -x $home/bin/mvn ]] || return 1
    output=$("$home/bin/mvn" --version) || return 1
    [[ $output == *"Apache Maven $expected"* ]]
}
