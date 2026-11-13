#!/usr/bin/env bash
_java25_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
_java25_home=$(source "$_java25_root/env"; version=$(cat "$_java25_root/pins/java25"); printf '%s/java25/%s' "$DEST_OPT_DIR" "$version")
if [[ -x "$_java25_home/bin/java" ]]; then
    export JAVA_HOME="$_java25_home"
    export PATH="$JAVA_HOME/bin:$PATH"
fi
unset _java25_root _java25_home
