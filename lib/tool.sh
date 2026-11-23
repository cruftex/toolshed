#!/usr/bin/env bash
# Tool descriptors (tools/<tool>.sh) and the generic install flows. Source after lib/install.sh.

toolshed_root=$(cd -- "$_installer_library_dir/.." && pwd)
declare -gA tool=()
declare -ga tool_keys=()

# Read the top-level KEY=VALUE settings of descriptor FILE into associative array ARRAY, one level of quotes
# removed, without sourcing the file or starting a subshell.
descriptor_read() {
    local -n _descriptor=$2
    local _line _value
    while IFS= read -r _line; do
        [[ $_line =~ ^([a-z_][a-z0-9_]*)=(.*)$ ]] || continue
        _value=${BASH_REMATCH[2]}
        _value=${_value#[\'\"]}
        _descriptor[${BASH_REMATCH[1]}]=${_value%[\'\"]}
    done < "$1"
}

# Print KEY's value from descriptor FILE (the `tool` array stays intact), or DEFAULT.
descriptor_value() {
    local -A _values=()
    descriptor_read "$1" _values
    printf '%s\n' "${_values[$2]-$3}"
}

# Fill the `tool` array with NAME's settings and defaults without sourcing the descriptor (no hooks are defined);
# `tool_keys` lists the keys the descriptor sets.
tool_settings() {
    local name=$1 key
    local -A settings=()
    [[ $name =~ ^[a-z0-9][a-z0-9-]*$ ]] || _installer_fail "Invalid tool name: $name"
    [[ -f $toolshed_root/tools/$name.sh ]] || _installer_fail "Unknown tool: $name"
    descriptor_read "$toolshed_root/tools/$name.sh" settings
    tool=([name]=$name [executable]=$name [table]=$name [archive]=tar.gz [license_file]=LICENSE
          [platforms]=linux-x64 [version_args]=--version [version_match]='*{version}*' [detect]=run
          [version_scheme]=semver2)
    tool_keys=("${!settings[@]}")
    for key in "${tool_keys[@]}"; do
        tool[$key]=${settings[$key]}
    done
}

# Load NAME's settings into `tool` and source tools/NAME.sh for its hooks, dropping the variables its settings define.
load_tool() {
    local _tool_key
    tool_settings "$1"
    source "$toolshed_root/tools/$1.sh"
    for _tool_key in "${tool_keys[@]}"; do
        unset "$_tool_key"
    done
}

has_hook() {
    declare -F "$1" >/dev/null
}

# Expand {asset} {version} {platform} {repo} {tag} {table} {build} {opt} {nvm} in a descriptor template.
tool_expand() {
    local value=$1 version=$2 platform=${3:-} mapped pair
    local -a pairs=()
    mapped=$platform
    read -ra pairs <<< "${tool[platform_names]:-}"
    for pair in "${pairs[@]}"; do
        [[ ${pair%%=*} != "$platform" ]] || mapped=${pair#*=}
    done
    value=${value//\{asset\}/${tool[asset]:-}}
    value=${value//\{version\}/$version}
    value=${value//\{platform\}/$mapped}
    value=${value//\{repo\}/${tool[repo]:-}}
    value=${value//\{tag\}/${tool[tag]:-}}
    value=${value//\{table\}/${tool[table]}}
    value=${value//\{build\}/${build:-}}
    value=${value//\{opt\}/$TOOLSHED_OPT_DIR}
    value=${value//\{nvm\}/${TOOLSHED_NVM_DIR:-}}
    printf '%s' "$value"
}

# The artifact ID of VERSION on PLATFORM, optionally for a COMPONENT of the tool.
tool_artifact() {
    local platform=$1 component=${2:-}
    if [[ ${tool[archive]} == binary ]]; then printf '%s\n' "$component/$platform/binary"
    else printf '%s\n' "$component/$platform/archive/${tool[archive]}"; fi
}

# The download URL of VERSION on PLATFORM: the URL recorded in the artifact table, else the expanded `url` template.
# With url=recorded the table must provide it.
tool_url() {
    local version=$1 platform=$2 recorded default='https://github.com/{repo}/releases/download/{tag}{version}/{asset}'
    recorded=$(artifact_url "${tool[table]}" "$version" "$(tool_artifact "$platform")") || return 1
    if [[ $recorded ]]; then
        printf '%s' "$recorded"
    elif [[ ${tool[url]:-} == recorded ]]; then
        _installer_fail "No recorded URL for ${tool[name]} $version/$platform."
    else
        tool_expand "${tool[url]:-$default}" "$version" "$platform"
    fi
}

# The recorded artifact for VERSION on PLATFORM, optionally for a COMPONENT of the tool.
tool_checksum() {
    artifact_checksum "${tool[table]}" "$1" "$(tool_artifact "$2" "${3:-}")"
}

# Set the variable named ROOT_VARIABLE to the package root inside extracted DIRECTORY: the expanded `root`
# setting, or with root='*' the archive's single top-level directory.
tool_root() {
    local _directory=$1 _version=$2 _platform=$3
    local -n _tool_root=$4
    local -a _entries=()
    if [[ ${tool[root]:-} == '*' ]]; then
        mapfile -t _entries < <(find "$_directory" -mindepth 1 -maxdepth 1 -printf '%f\n')
        (( ${#_entries[@]} == 1 )) && [[ -d $_directory/${_entries[0]} && ! -L $_directory/${_entries[0]} ]] ||
            _installer_fail "Expected one top-level directory in the ${tool[name]} archive."
        _tool_root=${_entries[0]}
    else
        _tool_root=$(tool_expand "${tool[root]}" "$_version" "$_platform")
    fi
    [[ -d $_directory/$_tool_root ]] || _installer_fail "Missing $_tool_root in ${tool[name]} archive."
}

select_tool_version() {
    local version
    version=$(select_install_version "${tool[name]}" "$@") || exit 1
    [[ -z ${tool[version_prefix]:-} || $version == "${tool[version_prefix]}"* ]] ||
        _installer_fail "Invalid ${tool[name]} version: $version"
    printf '%s\n' "$version"
}

# Run the tool's validation hook, or check the output of its version command against version_match.
validate_tool() {
    local target=$1 version=$2 output pattern
    local -a args=() vars=()
    if has_hook tool_validate; then
        tool_validate "$target" "$version" || _installer_fail "${tool[name]} $version validation failed."
        return
    fi
    read -ra args <<< "${tool[version_args]}"
    read -ra vars <<< "${tool[version_env]:-}"
    output=$(env "${vars[@]}" "$target" "${args[@]}" 2>&1) || _installer_fail "Cannot run ${tool[name]}."
    pattern=$(tool_expand "${tool[version_match]}" "$version")
    # shellcheck disable=SC2053
    [[ $output == $pattern ]] || _installer_fail "Unexpected ${tool[name]} version: $output"
}

# Stage the executable from a verified download in OUTPUT_VARIABLE; call directly, not in a subshell.
stage_tool_executable() {
    local _tool_archive=$1 _tool_member=$2
    local -n _tool_output=$3
    case ${tool[archive]} in
        binary) stage_executable "$_tool_archive" _tool_output ;;
        zip) extract_zip_member "$_tool_archive" "$_tool_member" _tool_output ;;
        tar.gz) extract_tar_member "$_tool_archive" "$_tool_member" _tool_output ;;
        *) _installer_fail "Unsupported archive type: ${tool[archive]}" ;;
    esac
}

# Link entries TARGET[=NAME] into TOOLSHED_BIN_DIR; targets are relative to BASE, globs pick executables.
link_tool_entries() {
    local base=$1 entry target name path
    local -a entries=()
    read -ra entries <<< "${tool[links]:-}"
    for entry in "${entries[@]}"; do
        target=${entry%%=*}
        name=${target##*/}
        [[ $entry != *=* ]] || name=${entry#*=}
        if [[ $target == *'*'* ]]; then
            for path in "$base"/$target; do
                [[ -f $path && -x $path ]] && install_symlink "$path" "${path##*/}"
            done
        else
            install_symlink "${base:+$base/}$target" "$name"
        fi
    done
}

print_tool_license() {
    local digest
    digest=$(artifact_checksum "${tool[table]}" "$1" "${tool[component]:-}/license" 2>/dev/null) || return 0
    printf 'License: %s (metadata/license/%s.txt)\n' \
        "$(cat "$toolshed_root/metadata/license/$digest.name.txt")" "$digest"
}

install_tool() {
    local name=$1
    shift
    load_tool "$name"
    case ${tool[kind]:-} in
        bin) install_bin_tool "$@" ;;
        opt) install_opt_tool "$@" ;;
        scripted) tool_install "$@" ;;
        *) _installer_fail "Invalid kind for tool $name." ;;
    esac
}

# Install one verified executable into TOOLSHED_BIN_DIR, skipping it when the installed bytes match.
install_bin_tool() {
    local name=${tool[name]} version platform key url archive binary
    declare -gA archive_sha256=() binary_sha256=()
    version=$(select_tool_version "$@")
    platform=$(platform_string)
    key="$version/$platform"
    archive_sha256[$key]=$(tool_checksum "$version" "$platform") || _installer_fail "No pinned $name checksum for $key."
    url=$(tool_url "$version" "$platform")
    if [[ ${tool[archive]} == binary ]]; then
        binary_sha256[$key]=${archive_sha256[$key]}
        if ! binary_is_installed "${tool[executable]}" "${binary_sha256[$key]}"; then
            warn_if_modified "${tool[executable]}" "${binary_sha256[$key]}"
            archive=$(cache_path "$url")
            download_verified "$url" "${archive_sha256[$key]}" "$archive"
            stage_tool_executable "$archive" '' binary
            verify_sha256 "$binary" "${binary_sha256[$key]}"
            validate_tool "$binary" "$version"
            install_binary "$binary" "${tool[executable]}"
        fi
    else
        archive=$(cache_path "$url")
        download_verified "$url" "${archive_sha256[$key]}" "$archive"
        stage_tool_executable "$archive" "$(tool_expand "${tool[member]}" "$version" "$platform")" binary
        binary_sha256[$key]=$(sha256sum < "$binary")
        binary_sha256[$key]=${binary_sha256[$key]%% *}
        if ! binary_is_installed "${tool[executable]}" "${binary_sha256[$key]}"; then
            warn_if_modified "${tool[executable]}" "${binary_sha256[$key]}"
            validate_tool "$binary" "$version"
            install_binary "$binary" "${tool[executable]}"
        fi
    fi
    link_tool_entries ''
    printf '%s %s is installed in %s\n' "$name" "$version" "$TOOLSHED_BIN_DIR"
    print_tool_license "$version"
    ! has_hook tool_after_install || tool_after_install "$version"
}

# Install a multi-file package into its versioned home; an existing home is validated, never replaced.
install_opt_tool() {
    local name=${tool[name]} version platform checksum url archive staging home root default='{opt}/{table}/{version}'
    version=$(select_tool_version "$@")
    platform=$(platform_string)
    checksum=$(tool_checksum "$version" "$platform") || _installer_fail "No pinned $name checksum for $version/$platform."
    ! has_hook tool_vars || tool_vars "$version"
    home=$(tool_expand "${tool[home]:-$default}" "$version" "$platform")
    ! has_hook tool_before_install || tool_before_install "$version"
    if [[ -e $home || -L $home ]]; then
        validate_tool "$home" "$version"
    else
        url=$(tool_url "$version" "$platform")
        archive=$(cache_path "$url")
        download_verified "$url" "$checksum" "$archive"
        _installer_require tar mkdir mv
        mkdir -p -- "${home%/*}"
        stage_directory staging "${home%/*}"
        tar -xzf "$archive" -C "$staging" || _installer_fail "Cannot extract $name archive."
        tool_root "$staging" "$version" "$platform" root
        ! has_hook tool_prepare || tool_prepare "$staging/$root"
        validate_tool "$staging/$root" "$version"
        [[ ! -e $home && ! -L $home ]] || _installer_fail "Destination appeared during staging: $home"
        mv -T -- "$staging/$root" "$home"
    fi
    link_tool_entries "$home"
    printf '%s %s is installed in %s\n' "$name" "$version" "$home"
    print_tool_license "$version"
    ! has_hook tool_after_install || tool_after_install "$version"
}
