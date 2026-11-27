#!/usr/bin/env bash
# `shed available|installed|update|discover`: report and update the tools in the configured locations.
# Functions only; source after lib/install.sh and lib/tool.sh. Commands that touch installations need toolshed_init.

declare -gA installed=()

# Print TEXT without leading and trailing whitespace.
trim() {
    local text=$1
    text=${text#"${text%%[![:space:]]*}"}
    printf '%s' "${text%"${text##*[![:space:]]}"}"
}

# Print the first standalone version of SCHEME (default: the loaded tool's) in TEXT, not part of a longer dotted
# number, in its recorded form; or nothing. JEP 322 versions are printed without trailing zero parts (25 for 25.0.0).
version_in() {
    local scheme=${2:-} body pattern
    [[ $scheme ]] || scheme=$(tool_version_scheme)
    case $scheme in
        jdk-jep322) body='[0-9]+(\.[0-9]+){0,4}' ;;
        *) body=$(version_regex "$scheme") || return ;;
    esac
    pattern="(^|[^0-9.])($body)([^0-9.]|$)"
    [[ $1 =~ $pattern ]] || return 0
    if [[ $scheme == jdk-jep322 ]]; then jdk_recorded_version "${BASH_REMATCH[2]}"
    else printf '%s\n' "${BASH_REMATCH[2]}"; fi
}

# Print the highest of the versions on stdin (one per line), or nothing.
version_max() {
    sort -V | tail -n 1
}

# Succeed if version A is higher than version B.
version_greater() {
    [[ $1 != "$2" && $(printf '%s\n' "$1" "$2" | version_max) == "$1" ]]
}

# Print whether INSTALLED should be updated to KNOWN: yes, no, newer (installed is ahead) or unknown.
version_status() {
    if [[ $1 == '?' || -z $2 ]]; then echo unknown
    elif [[ $1 == "$2" ]]; then echo no
    elif version_greater "$2" "$1"; then echo yes
    else echo newer; fi
}

# Print the names of all tool descriptors, in C collation order.
tool_names() {
    local file
    for file in "$toolshed_root"/tools/*.sh; do
        file=${file##*/}
        printf '%s\n' "${file%.sh}"
    done | LC_ALL=C sort
}

# Print the pinned default version of tool NAME.
pinned_version() {
    trim "$(< "$toolshed_root/pins/$1")"
    echo
}

shed_table() {
    printf '%s\n' "$toolshed_root/metadata/artifacts/${tool[table]}.psv"
}

# Print the version that executable PATH reports when run with ARGS and the caller's `version_env` assignments:
# `?` when it fails or prints none, nothing when PATH is not an executable file.
executable_version() {
    local path=$1 output version=''
    local -a vars=()
    shift
    [[ -f $path && -x $path ]] || return 0
    read -ra vars <<< "${version_env:-}"
    if output=$(timeout 15 env "${vars[@]}" "$path" "$@" 2>&1 < /dev/null); then
        version=$(version_in "$output")
    fi
    printf '%s\n' "${version:-?}"
}

# Print the version of every installed Node.js release of the loaded node tool (`?` when unreadable).
node_versions() {
    local path prefix="v${tool[name]#node}" version_env=''
    for path in "${TOOLSHED_NVM_DIR:-.}/versions/node/$prefix".*; do
        [[ ${path##*/} =~ ^${prefix}\.[0-9]+\.[0-9]+$ ]] || continue
        executable_version "$path/bin/node" --version
    done
}

# Print the installed version of the loaded tool: nothing when absent, `?` when it cannot be determined.
detect_version() {
    local executable="$TOOLSHED_BIN_DIR/${tool[executable]}" version='' path home output version_env=${tool[version_env]:-}
    local -a args=() versions=()
    case ${tool[detect]} in
        run)
            read -ra args <<< "${tool[version_args]}"
            executable_version "$executable" "${args[@]}" ;;
        digest) # No version flag: identify the verified bytes by their recorded digest.
            [[ -f $executable && -x $executable ]] || return 0
            path=$(shed_table)
            if [[ -f $path ]] && output=$(sha256sum < "$executable"); then
                version=$(awk -F'|' -v d="${output%% *}" '$2 == "/linux-x64/binary" && $3 == d {print $1}' "$path" |
                    version_max)
            fi
            printf '%s\n' "${version:-?}" ;;
        link) # The version is the linked package directory: <opt>/<table>/<version>/<dir>/<executable>.
            [[ -f $executable && -x $executable ]] || return 0
            path=$(readlink -f -- "$executable")
            home=$(readlink -m -- "$TOOLSHED_OPT_DIR/${tool[table]}")
            version=${path#"$home"/}
            version=${version%%/*}
            if [[ $path == "$home"/* && ${path#"$home"/} =~ ^[^/]+/[^/]+/[^/]+$ ]] && version_valid "$version"; then
                printf '%s\n' "$version"
            else
                echo '?'
            fi ;;
        dirs) # The newest version-named directory in <opt>/<table>.
            for path in "$TOOLSHED_OPT_DIR/${tool[table]}"/*; do
                ! version_valid "${path##*/}" || versions+=("${path##*/}")
            done
            (( ${#versions[@]} == 0 )) || printf '%s\n' "${versions[@]}" | version_max ;;
        nvm)
            path="${TOOLSHED_NVM_DIR:-.}/nvm.sh"
            [[ -f $path ]] || return 0
            if output=$(NVM_DIR=${TOOLSHED_NVM_DIR:-.} timeout 15 bash -c 'source "$1" --no-use; nvm --version' _ "$path" \
                    2>&1 < /dev/null); then
                version=$(version_in "$output")
            fi
            printf '%s\n' "${version:-?}" ;;
        node)
            mapfile -t versions < <(node_versions)
            (( ${#versions[@]} )) || return 0
            version=$(printf '%s\n' "${versions[@]}" | awk '$0 != "?"' | version_max)
            printf '%s\n' "${version:-?}" ;;
    esac
}

# Detect every installed tool into the `installed` array (name → version or `?`).
detect_installed() {
    local name version
    installed=()
    while IFS= read -r name; do
        tool_settings "$name"
        version=$(detect_version)
        [[ -z $version ]] || installed[$name]=$version
    done < <(tool_names)
}

# Print "VERSION NEWEST_DISCOVERED_AT" for each version of the loaded tool that has a digest for every component
# on PLATFORM; the time is empty when a row has none.
complete_versions() {
    local table
    table=$(shed_table)
    [[ -f $table ]] || return 0
    awk -F'|' -v platform="$1" -v prefix="${tool[version_prefix]:-}" -v components="${tool[components]:-}" '
        BEGIN { required[""]; n = split(components, pairs, " ")
                for (i = 1; i <= n; i++) { split(pairs[i], pair, "="); required[pair[1]] } }
        NR > 1 && $3 != "" && index($1, prefix) == 1 {
            split($2, parts, "/")
            if (parts[2] != platform) next
            have[$1, parts[1]]; versions[$1]
            if ($4 == "") missing[$1]; else if ($4 > newest[$1]) newest[$1] = $4
        }
        END { for (v in versions) { complete = 1
                  for (c in required) if (!((v, c) in have)) complete = 0
                  if (complete) print v, (v in missing ? "" : newest[v]) } }' "$table"
}

# Print the version the loaded tool should be at: the newest complete recorded version.
# With DELAY_DAYS > 0, versions other than the pin must have been discovered at least that long ago.
target_version() {
    local delay=${1:-0} pin platform version stamp cutoff
    local -A stamps=()
    local -a candidates=() eligible=()
    pin=$(pinned_version "${tool[name]}")
    if platform=$(platform_string 2> /dev/null); then
        while read -r version stamp; do stamps[$version]=$stamp; done < <(complete_versions "$platform")
    fi
    candidates=("${!stamps[@]}")
    if (( delay > 0 )); then
        cutoff=$(date -u -d "-$delay days" +%Y-%m-%dT%H:%M:%SZ)
        for version in "${candidates[@]}"; do
            stamp=${stamps[$version]:-}
            if [[ $version == "$pin" ]] || [[ $stamp && ! $stamp > $cutoff ]]; then eligible+=("$version"); fi
        done
        candidates=("${eligible[@]}")
    fi
    (( ${#candidates[@]} == 0 )) || printf '%s\n' "${candidates[@]}" | version_max
}

# Atomically replace the pin of tool NAME with VERSION, keeping its permissions.
move_pin() {
    local path="$toolshed_root/pins/$1" temporary
    temporary=$(mktemp "${path%/*}/.$1.XXXXXXXX") || return
    _installer_temp_dirs+=("$temporary")
    printf '%s\n' "$2" > "$temporary" && chmod --reference="$path" -- "$temporary" && mv -f -- "$temporary" "$path"
}

# Print the pin and every recorded version of the loaded tool, ascending.
recorded_versions() {
    local table version
    table=$(shed_table)
    {
        pinned_version "${tool[name]}"
        if [[ -f $table ]]; then awk -F'|' 'NR > 1 && $2 !~ /\/license$/ {print $1}' "$table"; fi
    } | while IFS= read -r version; do
        [[ $version != "${tool[version_prefix]:-}"* ]] || ! version_valid "$version" || printf '%s\n' "$version"
    done | sort -uV
}

shed_available() {
    local name version
    printf '%-12s %-16s %-16s %s\n' TOOL DEFAULT INSTALLED 'RECORDED VERSIONS'
    while IFS= read -r name; do
        tool_settings "$name"
        version=$(detect_version)
        printf '%-12s %-16s %-16s %s\n' "$name" "$(pinned_version "$name")" "${version:--}" "$(recorded_versions | wc -l)"
    done < <(for name in "$toolshed_root"/pins/*; do [[ ! -f $name ]] || printf '%s\n' "${name##*/}"; done | LC_ALL=C sort)
}

shed_discoverable() {
    local name
    while IFS= read -r name; do
        tool_settings "$name"
        [[ ${tool[discover]:-} == none ]] || printf '%s\n' "$name"
    done < <(tool_names)
}

shed_installed() {
    local name known shown
    detect_installed
    printf '%-12s %-16s %-16s %s\n' TOOL INSTALLED KNOWN UPDATE
    while IFS= read -r name; do
        tool_settings "$name"
        known=$(target_version)
        shown=${installed[$name]}
        if [[ ${tool[detect]} == node ]]; then
            shown=$(node_versions | awk '$0 != "?"' | sort -rV; node_versions | awk '$0 == "?"')
            shown=${shown//$'\n'/,}
        fi
        printf '%-12s %-16s %-16s %s\n' "$name" "$shown" "${known:-unavailable}" "$(version_status "${installed[$name]}" "$known")"
    done < <(printf '%s\n' "${!installed[@]}" | LC_ALL=C sort | awk 'NF')
    (( ${#installed[@]} )) || echo 'No installed tools found in configured locations.'
}

# `shed update DELAY_DAYS` installs the newest eligible recorded version of each installed tool and moves its pin;
# `shed discover` looks for new releases of each installed tool. NVM goes first; failures make the result 1.
shed_run() {
    local command=$1 delay=${2:-0} name version known found errors staging status failures=0
    detect_installed
    (( ${#installed[@]} )) || echo 'No installed tools found in configured locations.'
    stage_directory staging
    while IFS= read -r name <&3; do
        version=${installed[$name]}
        if [[ $version == '?' ]]; then
            echo "$name: version unknown; skipped" >&2
            failures=1
            continue
        fi
        tool_settings "$name"
        if [[ $command == update ]]; then
            known=$(target_version "$delay")
            if [[ -z $known ]]; then
                echo "$name: no compatible recorded version; skipped" >&2
                failures=1
                continue
            fi
            case $(version_status "$version" "$known") in
                newer) echo "$name: $version is newer than recorded $known; unchanged"; continue ;;
                no) if [[ $(pinned_version "$name") == "$known" ]]; then echo "$name: $version is current"; continue; fi ;;
            esac
            if [[ $name == node24 && ${installed[nvm]:-} != "$(tool_settings nvm; target_version "$delay")" ]]; then
                echo 'node24: configured NVM version must be repaired or upgraded first; skipped' >&2
                failures=1
                continue
            fi
            echo "$name: installing $known..."
            status=0
            found=$(TOOLSHED_OVERRIDE_TOOL_VERSION=$known "$toolshed_root/lib/install-tool.sh" "$name" 2> "$staging/errors") ||
                status=$?
        else
            if [[ ${tool[discover]:-} == none ]]; then
                echo "$name: no internet updater available; skipped"
                continue
            fi
            echo "$name: checking for releases..."
            status=0
            found=$(env -u TOOLSHED_OVERRIDE_TOOL_VERSION "$toolshed_root/lib/discover-tool.sh" "$name" 2> "$staging/errors") ||
                status=$?
        fi
        errors=$(trim "$(< "$staging/errors")")
        if (( status )); then
            echo "$name: failed" >&2
            [[ -z $errors ]] || printf '%s\n' "$errors" >&2
            failures=1
            continue
        fi
        [[ -z $errors ]] || printf '%s\n' "$errors" >&2
        if [[ $command == update ]]; then
            if ! move_pin "$name" "$known"; then
                echo "$name: installed $known, but could not update pin" >&2
                failures=1
                continue
            fi
            installed[$name]=$known
            echo "$name: installed $known; pin updated"
        else
            found=$(trim "$found")
            if ! version_valid "$found"; then
                echo "$name: updater returned an invalid version" >&2
                failures=1
            elif version_greater "$found" "$version"; then
                echo "$name: $found available and cached (installed $version)"
            else
                echo "$name: no newer release (installed $version, latest $found)"
            fi
        fi
    done 3< <(if [[ ${installed[nvm]+x} ]]; then echo nvm; fi
             printf '%s\n' "${!installed[@]}" | awk 'NF && $0 != "nvm"' | LC_ALL=C sort)
    return "$failures"
}

# Print the loaded tool's install strategy: its `strategy` setting, or the default for its kind.
tool_strategy() {
    if [[ ${tool[strategy]:-} ]]; then
        printf '%s\n' "${tool[strategy]}"
        return
    fi
    case ${tool[kind]:-} in
        bin) echo 'Verified executable in bin' ;;
        opt) echo 'Verified package in opt; entry points in bin' ;;
        *) echo ;;
    esac
}

# Print the README's Markdown table of pinned tools: latest recorded version and install strategy.
readme_tools_table() {
    local path name strategy
    echo '| Tool | Latest recorded version | Install strategy |'
    echo '| --- | --- | --- |'
    for path in "$toolshed_root"/pins/*; do
        name=${path##*/}
        [[ -f $path ]] || continue
        tool_settings "$name"
        strategy=$(tool_strategy)
        if [[ -f $toolshed_root/profile.d/$name.sh ]]; then
            strategy+="; source [\`profile.d/$name.sh\`](profile.d/$name.sh)"
        fi
        printf '| [%s](tools/%s.sh) | %s | %s |\n' "$name" "$name" "$(recorded_versions | tail -n 1)" "$strategy"
    done
}
