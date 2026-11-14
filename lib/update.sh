#!/usr/bin/env bash
# Shared helpers for explicit release updates. The caller sources install.sh.
release_info() {
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
release_asset_digest() {
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
    local name=$1 key=$2 archive=$3 binary=$4
    local -A checksums=()
    source "$_installer_library_dir/../metadata/$name.sh"
    [[ ! ${checksums[archive/$key]+present} || ${checksums[archive/$key]} == "$archive" ]] || _installer_fail "Conflicting archive metadata: $name $key"
    [[ ! ${checksums[binary/$key]+present} || ${checksums[binary/$key]} == "$binary" ]] || _installer_fail "Conflicting binary metadata: $name $key"
}
record_checksums() {
    local name=$1 key=$2 archive=$3 binary=$4
    check_recorded_checksums "$name" "$key" "$archive" "$binary"
    local -A checksums=()
    source "$_installer_library_dir/../metadata/$name.sh"
    [[ ${checksums[archive/$key]+present} ]] || printf '\nchecksums[archive/%s]=%s\n' "$key" "$archive" >> "$_installer_library_dir/../metadata/$name.sh"
    [[ ${checksums[binary/$key]+present} ]] || printf '\nchecksums[binary/%s]=%s\n' "$key" "$binary" >> "$_installer_library_dir/../metadata/$name.sh"
    return 0
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
    local -A archive_sha256=()
    source "$_installer_library_dir/../metadata/maven.sh"
    key="$version/linux-x64"
    [[ ! ${archive_sha256[$key]+present} || ${archive_sha256[$key]} == "$digest" ]] || _installer_fail "Conflicting Maven checksum: $key"
    if [[ ! ${archive_sha256[$key]+present} ]]; then
        printf '\narchive_sha256[%s]=%s\n' "$key" "$digest" >> "$_installer_library_dir/../metadata/maven.sh"
    fi
    local archive
    archive=$(cache_path "$url")
    download_verified "$url" "$digest" "$archive"
    write_version_pin "$pin" "$version"
    "$_installer_library_dir/../install/install-$pin.sh"
}
