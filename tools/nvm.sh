kind=scripted
archive=tar.gz
detect=nvm
discover=none
license=mit
strategy='Verified Git archive in NVM directory'

tool_install() {
    local version platform checksum actual archive legacy staging staged_version
    local -A git_commit=()
    version=$(select_tool_version "$@")
    platform=$(platform_string)
    source "$toolshed_root/metadata/nvm.sh"
    checksum=$(tool_checksum "$version" "$platform") || _installer_fail "No pinned NVM archive for $version/$platform."
    [[ ${git_commit[$version]:-} ]] || _installer_fail "No pinned NVM archive for $version/$platform."
    actual=
    if [[ -e $TOOLSHED_NVM_DIR || -L $TOOLSHED_NVM_DIR ]]; then
        [[ -d $TOOLSHED_NVM_DIR && ! -L $TOOLSHED_NVM_DIR && -f $TOOLSHED_NVM_DIR/nvm.sh ]] || _installer_fail "Incomplete or unsupported NVM installation: $TOOLSHED_NVM_DIR"
        actual=$(NVM_DIR="$TOOLSHED_NVM_DIR" bash -c 'source "$NVM_DIR/nvm.sh" --no-use; nvm --version') || _installer_fail 'Cannot read installed NVM version.'
    fi
    if [[ $actual != "$version" ]]; then
        archive="$TOOLSHED_DOWNLOAD_DIR/$platform/nvm/$version/nvm-$version.tar.gz"
        legacy="$TOOLSHED_DOWNLOAD_DIR/nvm/$version/nvm-$version.tar.gz"
        if [[ ! -e $archive && ! -L $archive ]]; then
            migrate_verified_cache "$legacy" "$archive" "$checksum" || true
        fi
        [[ -f $archive ]] || _installer_fail "NVM archive missing: $archive (run ./prepare-nvm-git.sh)"
        verify_sha256 "$archive" "$checksum"
        mkdir -p -- "$(dirname -- "$TOOLSHED_NVM_DIR")"
        stage_directory staging "$(dirname -- "$TOOLSHED_NVM_DIR")"
        tar -xzf "$archive" -C "$staging" || _installer_fail 'Cannot extract NVM archive.'
        staged_version=$(NVM_DIR="$staging/nvm-$version" bash -c 'source "$NVM_DIR/nvm.sh" --no-use; nvm --version')
        [[ $staged_version == "$version" ]] || _installer_fail 'Unexpected NVM version.'
        if [[ -n $actual ]]; then
            _installer_require python3
            python3 "$_installer_library_dir/replace-nvm.py" "$staging/nvm-$version" "$TOOLSHED_NVM_DIR" "$TOOLSHED_NVM_GIT_DIR"
        else
            [[ ! -e $TOOLSHED_NVM_DIR && ! -L $TOOLSHED_NVM_DIR ]] || _installer_fail 'NVM destination appeared during staging.'
            mv -T -- "$staging/nvm-$version" "$TOOLSHED_NVM_DIR"
        fi
    fi
    printf 'NVM %s is installed in %s\n' "$version" "$TOOLSHED_NVM_DIR"
}
