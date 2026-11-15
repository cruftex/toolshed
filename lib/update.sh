#!/usr/bin/env bash
# Discovery shares installer primitives, while ignoring installer-only overrides.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/install.sh"
unset TOOLSHED_OVERRIDE_TOOL_VERSION
_toolshed_capture_peer=1
_discovery_timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

# Record the first successful verification, without inventing historical provenance.
record_provenance() {
    local name=$1 key=$2 source_url=$3 peer_file=$4 timestamp
    if [[ $name == claude ]]; then
        python3 "$_installer_library_dir/discovery_records.py" record "$_installer_library_dir/.." "$name" "$key" '' "$_discovery_timestamp"
    fi
    timestamp=$(python3 "$_installer_library_dir/discovery_records.py" timestamp "$_installer_library_dir/.." "$name" "$key")
    python3 "$_installer_library_dir/provenance.py" \
        "$_installer_library_dir/../metadata/provenance/$name.json" "$key" "$source_url" "$peer_file" "$timestamp"
}
github_release_info() {
    local repository=$1 tag_prefix=$2 output=$3
    _installer_download "https://api.github.com/repos/$repository/releases/latest" "$output.json"
    python3 - "$output.json" "$tag_prefix" > "$output" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    release = json.load(f)
tag, prefix = release['tag_name'], sys.argv[2]
if not tag.startswith(prefix) or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', tag[len(prefix):]) or release['draft'] or release['prerelease']:
    sys.exit('Invalid release metadata')
print(tag[len(prefix):])
PY
}
github_release_asset_digest() {
    python3 - "$1.json" "$2" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    assets = [a for a in json.load(f)['assets'] if a['name'] == sys.argv[2]]
if len(assets) != 1 or not re.fullmatch(r'sha256:[0-9a-f]{64}', assets[0].get('digest') or ''):
    sys.exit('Missing or invalid release digest for ' + sys.argv[2])
print(assets[0]['digest'][7:])
PY
}
check_recorded_checksums() {
    local name=$1 key=$2 archive=$3
    python3 "$_installer_library_dir/discovery_records.py" check "$_installer_library_dir/.." "$name" "$key" "$archive"
}
record_checksums() {
    local name=$1 key=$2 archive=$3
    check_recorded_checksums "$name" "$key" "$archive"
    python3 "$_installer_library_dir/discovery_records.py" record "$_installer_library_dir/.." "$name" "$key" "$archive" "$_discovery_timestamp"
}
# Store a license text deduplicated by SHA-256 and record it as the version's license artifact.
record_license() {
    local name=$1 version=$2 text=$3 license=$4 digest
    digest=$(python3 "$_installer_library_dir/license_store.py" store "$_installer_library_dir/.." "$text" "$license") ||
        _installer_fail "Cannot store license for $name."
    record_checksums "$name" "$version/license" "$digest"
}
# Fetch a project's license file from its repository at the release tag and record it.
record_github_license() {
    local name=$1 version=$2 repo=$3 tag=$4 file=$5 license=$6 staging
    stage_directory staging
    _installer_download "https://raw.githubusercontent.com/$repo/$tag/$file" "$staging/license.txt" ||
        _installer_fail "Cannot download the $name license."
    record_license "$name" "$version" "$staging/license.txt" "$license"
}
write_version_pin() {
    local name=$1 value=$2
    printf '%s\n' "$value" > "$_installer_library_dir/../pins/.$name.tmp"
    mv -fT -- "$_installer_library_dir/../pins/.$name.tmp" "$_installer_library_dir/../pins/$name"
}

# Explicitly update one Maven release line, verifying bytes against Apache's published SHA-512.
update_maven_line() {
    local line=$1 pin=$2 staging version current url published actual digest key output
    [[ $(platform_string) == linux-x64 ]] || _installer_fail 'Maven update supports Linux x86_64 only.'
    _installer_require python3 sha256sum sha512sum tar
    stage_directory staging
    _installer_download https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/maven-metadata.xml "$staging/metadata.xml"
    version=$(python3 - "$staging/metadata.xml" "$line" <<'PY'
import re, sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
line = sys.argv[2]
versions = [v.text for v in root.findall('./versioning/versions/version') if v.text and re.fullmatch(re.escape(line) + r'\.(0|[1-9][0-9]*)', v.text)]
if not versions:
    sys.exit('No stable Maven release found for ' + line)
print(max(versions, key=lambda v: int(v.rsplit('.', 1)[1])))
PY
    ) || _installer_fail 'Cannot determine Maven release.'
    current=$(read_version_pin "$pin")
    [[ $current == "$line."* ]] || _installer_fail 'Invalid Maven release line in pin.'
    (( ${version##*.} >= ${current##*.} )) || _installer_fail 'Release metadata would downgrade the Maven pin.'
    url="https://archive.apache.org/dist/maven/maven-3/$version/binaries/apache-maven-$version-bin.tar.gz"
    _installer_download "$url.sha512" "$staging/checksum"
    published=$(cat "$staging/checksum")
    [[ $published =~ ^[0-9a-f]{128}$ ]] || _installer_fail 'Invalid Apache SHA-512.'
    _installer_download "$url" "$staging/archive"
    actual=$(sha512sum < "$staging/archive")
    [[ ${actual%% *} == "$published" ]] || _installer_fail 'Apache SHA-512 verification failed.'
    digest=$(sha256sum < "$staging/archive"); digest=${digest%% *}
    tar -xzf "$staging/archive" -C "$staging" || _installer_fail 'Cannot extract Maven archive.'
    [[ -x $staging/apache-maven-$version/bin/mvn ]] || _installer_fail 'Missing Maven executable.'
    output=$("$staging/apache-maven-$version/bin/mvn" --version) || _installer_fail 'Cannot run Maven.'
    [[ $output == "Apache Maven $version "* ]] || _installer_fail 'Unexpected Maven version.'
    key="$version/linux-x64"
    check_recorded_checksums "$pin" "$key" "$digest"
    local archive
    archive=$(cache_path "$url")
    download_verified "$url" "$digest" "$archive"
    record_checksums "$pin" "$key" "$digest"
    record_github_license "$pin" "$version" apache/maven "maven-$version" LICENSE apache-2.0
    record_provenance "$pin" "$key" "$url.sha512" "$staging/checksum.peer"
    printf '%s\n' "$version"
}

# Discover one GitHub release, verify and cache its asset, and record both digests.
discover_github_defined_release() {
    local name=$1 release_repo release_tag release_asset release_member
    source "$_installer_library_dir/../metadata/releases/$name.sh"
    discover_github_release_binary "$name" "$release_repo" "$release_tag" "$release_asset" "$release_member"
}

discover_github_release_binary() {
    local name=$1 repo=$2 tag_prefix=$3 asset_pattern=$4 member_pattern=$5
    local staging version asset member url archive checksum binary
    [[ $(platform_string) == linux-x64 ]] || _installer_fail "$name discovery supports Linux x86_64 only."
    _installer_require python3 sha256sum
    stage_directory staging
    github_release_info "$repo" "$tag_prefix" "$staging/release"
    version=$(cat "$staging/release")
    asset=${asset_pattern//\{version\}/$version}
    member=${member_pattern//\{version\}/$version}
    checksum=$(github_release_asset_digest "$staging/release" "$asset")
    url="https://github.com/$repo/releases/download/$tag_prefix$version/$asset"
    archive=$(cache_path "$url")
    download_verified "$url" "$checksum" "$archive"
    if [[ $member ]]; then
        _installer_require tar chmod
        tar -xOzf "$archive" "$member" > "$staging/binary" || _installer_fail "Cannot extract $name."
        [[ -s $staging/binary ]] || _installer_fail "Empty $name executable."
        chmod 755 "$staging/binary"
        binary=$staging/binary
    else
        stage_executable "$archive" binary
    fi
    validate_tool_binary "$binary" "$version"
    record_checksums "$name" "$version/linux-x64" "$checksum"
    record_github_license "$name" "$version" "$repo" "$tag_prefix$version" "${release_license_file:-LICENSE}" "${release_license_name:?Missing release_license_name}"
    record_provenance "$name" "$version/linux-x64" "https://api.github.com/repos/$repo/releases/latest" "$staging/release.json.peer"
    printf '%s\n' "$version"
}
