#!/usr/bin/env bash
# Discovery shares installer primitives. Sourcing only defines functions; entry points call `discovery_init`.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/install.sh"
source "$_installer_library_dir/tool.sh"
source "$_installer_library_dir/records.sh"
source "$_installer_library_dir/provenance.sh"

# Like toolshed_init, but ignore installer-only overrides and capture each download's peer and certificates.
discovery_init() {
    toolshed_init
    unset TOOLSHED_OVERRIDE_TOOL_VERSION
    _toolshed_capture_peer=1
    _discovery_timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
}

github_release_info() {
    local repository=$1 tag_prefix=$2 output=$3 version
    _installer_download "https://api.github.com/repos/$repository/releases/latest" "$output.json"
    version=$(jq -er --arg p "$tag_prefix" 'select((.draft or .prerelease) | not) | .tag_name
        | select(startswith($p)) | ltrimstr($p)' "$output.json") || version=
    [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || _installer_fail 'Invalid release metadata'
    printf '%s\n' "$version" > "$output"
}
github_release_asset_digest() {
    local digest
    digest=$(jq -r --arg n "$2" '[.assets[] | select(.name == $n)] | if length == 1 then .[0].digest // "" else "" end' "$1.json")
    [[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || _installer_fail "Missing or invalid release digest for $2"
    printf '%s\n' "${digest#sha256:}"
}
# Store a license text once as metadata/license/<sha256>.txt, its short name in <sha256>.name.txt; set the
# variable named by the third argument to the digest.
store_license() {
    local _text=$1 _name=$2 _directory="$toolshed_root/metadata/license" _digest _stored _temporary
    local -n _store_digest=$3
    [[ $_name =~ ^[a-z0-9][a-z0-9.+-]*$ ]] || _installer_fail "Invalid license name: $_name"
    [[ -n $(tr -d '[:space:]' < "$_text") ]] || _installer_fail 'Empty license text'
    _digest=$(sha256sum < "$_text")
    _digest=${_digest%% *}
    if [[ -e $_directory/$_digest.name.txt ]]; then
        _stored=$(< "$_directory/$_digest.name.txt")
        [[ $_stored == "$_name" ]] || _installer_fail "License $_digest already stored as $_stored"
    fi
    [[ ! -e $_directory/$_digest.txt ]] || _installer_check_sha256 "$_directory/$_digest.txt" "$_digest" ||
        _installer_fail "Stored license is corrupt: $_digest.txt"
    mkdir -p -- "$_directory"
    stage_directory _temporary "$_directory"
    if [[ ! -e $_directory/$_digest.txt ]]; then
        cp -- "$_text" "$_temporary/text" && mv -f -- "$_temporary/text" "$_directory/$_digest.txt"
    fi
    if [[ ! -e $_directory/$_digest.name.txt ]]; then
        printf '%s\n' "$_name" > "$_temporary/name" && mv -f -- "$_temporary/name" "$_directory/$_digest.name.txt"
    fi
    _store_digest=$_digest
}
# Store a license text deduplicated by SHA-256 and record it as the version's license artifact.
record_license() {
    local name=$1 version=$2 text=$3 license=$4 digest
    store_license "$text" "$license" digest
    record_checksums "$name" "$version/license" "$digest"
}
# Record the license of the loaded tool: a tool_license hook, or the repository's license file at the tag.
record_tool_license() {
    local name=$1 version=$2 archive=${3:-} staging tag default='{tag}{version}'
    stage_directory staging
    if has_hook tool_license; then
        tool_license "$version" "$staging/license.txt" "$archive"
    else
        tag=$(tool_expand "${tool[license_tag]:-$default}" "$version")
        _installer_download "https://raw.githubusercontent.com/${tool[repo]}/$tag/${tool[license_file]}" "$staging/license.txt" ||
            _installer_fail "Cannot download the $name license."
    fi
    record_license "$name" "$version" "$staging/license.txt" "${tool[license]:?Missing license for $name}"
}

# Set `checksum` for URL from the tool's checksum source; a URL source also becomes the provenance.
publisher_checksum() {
    local url=$1 staging=$2 source=${tool[checksum]:-github} line extra
    case $source in
        github)
            checksum=$(github_release_asset_digest "$staging/release" "${url##*/}") ;;
        suffix:*)
            _installer_download "$url${source#suffix:}" "$staging/checksum"
            checksum=$(cat "$staging/checksum") ;;
        sha256sum:*)
            _installer_download "$url${source#sha256sum:}" "$staging/checksum"
            read -r checksum line extra < "$staging/checksum"
            [[ $line == "${url##*/}" && -z ${extra:-} ]] || _installer_fail "Invalid ${tool[name]} publisher checksum." ;;
        *) _installer_fail "Unsupported checksum source: $source" ;;
    esac
    [[ $checksum =~ ^[0-9a-f]{64}$ ]] || _installer_fail "Invalid ${tool[name]} publisher checksum."
    if [[ $source != github ]]; then
        provenance_url="$url${source#*:}"
        provenance_peer="$staging/checksum.peer"
    fi
}

# Extract a verified discovery download and validate it like the installer would.
validate_discovered() {
    local archive=$1 version=$2 platform=$3 staging=$4 binary root
    if [[ ${tool[kind]} == opt ]]; then
        tar -xzf "$archive" -C "$staging" || _installer_fail "Cannot extract ${tool[name]} archive."
        root=$(tool_expand "${tool[root]}" "$version" "$platform")
        ! has_hook tool_prepare || tool_prepare "$staging/$root"
        validate_tool "$staging/$root" "$version"
    else
        stage_tool_executable "$archive" "$(tool_expand "${tool[member]:-}" "$version" "$platform")" binary
        validate_tool "$binary" "$version"
    fi
}

# Find the latest release, verify and cache its downloads, and record checksums, license and provenance.
discover_tool() {
    local name=$1 host platform url archive host_archive='' staging version checksum provenance_url provenance_peer
    local -a platforms=()
    load_tool "$name"
    [[ ${tool[discover]:-} != none ]] || _installer_fail "$name has no discovery."
    if has_hook tool_discover; then
        tool_discover
        return
    fi
    host=$(platform_string)
    read -ra platforms <<< "${tool[platforms]}"
    [[ " ${platforms[*]} " == *" $host "* ]] || _installer_fail "$name discovery supports ${platforms[*]} only."
    _installer_require python3 jq sha256sum tar
    stage_directory staging
    declare -gA discovered=()
    if has_hook tool_latest; then
        tool_latest "$staging"
    else
        github_release_info "${tool[repo]}" "${tool[tag]}" "$staging/release"
        version=$(cat "$staging/release")
        provenance_url="https://api.github.com/repos/${tool[repo]}/releases/latest"
        provenance_peer="$staging/release.json.peer"
    fi
    ! has_hook tool_vars || tool_vars "$version"
    for platform in "${platforms[@]}"; do
        url=$(tool_url "$version" "$platform")
        if [[ ${discovered[$platform]:-} ]]; then checksum=${discovered[$platform]}
        else publisher_checksum "$url" "$staging"; fi
        check_recorded_checksums "$name" "$version/$platform" "$checksum"
        archive=$(cache_path "$url" "$platform")
        download_verified "$url" "$checksum" "$archive"
        discovered[$platform]=$checksum
        if [[ $platform == "$host" ]]; then
            validate_discovered "$archive" "$version" "$platform" "$staging"
            host_archive=$archive
        fi
    done
    for platform in "${platforms[@]}"; do
        record_checksums "$name" "$version/$platform" "${discovered[$platform]}"
    done
    record_tool_license "$name" "$version" "$host_archive"
    ! has_hook tool_after_discovery || tool_after_discovery "$version"
    for platform in "${platforms[@]}"; do
        record_provenance "$name" "$version/$platform" "$provenance_url" "$provenance_peer"
    done
    printf '%s\n' "$version"
}

# tool_latest for a Maven release line: Apache's metadata, verified against its published SHA-512.
maven_latest() {
    local line=$1 staging=$2 current url published actual
    _installer_require sha512sum
    _installer_download https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/maven-metadata.xml "$staging/metadata.xml"
    version=$(grep -oE "<version>${line//./\\.}\.(0|[1-9][0-9]*)</version>" "$staging/metadata.xml" |
        sed -E 's#</?version>##g' | sort -t. -k3,3n | tail -n 1)
    [[ $version ]] || _installer_fail "No stable Maven release found for $line."
    current=$(read_version_pin "${tool[name]}")
    [[ $current == "$line."* ]] || _installer_fail 'Invalid Maven release line in pin.'
    (( ${version##*.} >= ${current##*.} )) || _installer_fail 'Release metadata would downgrade the Maven pin.'
    url=$(tool_url "$version" linux-x64)
    _installer_download "$url.sha512" "$staging/checksum"
    published=$(cat "$staging/checksum")
    [[ $published =~ ^[0-9a-f]{128}$ ]] || _installer_fail 'Invalid Apache SHA-512.'
    _installer_download "$url" "$staging/archive"
    actual=$(sha512sum < "$staging/archive")
    [[ ${actual%% *} == "$published" ]] || _installer_fail 'Apache SHA-512 verification failed.'
    actual=$(sha256sum < "$staging/archive")
    discovered[linux-x64]=${actual%% *}
    provenance_url="$url.sha512"
    provenance_peer="$staging/checksum.peer"
}
