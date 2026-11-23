#!/usr/bin/env bash
_java8_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
_java8_home=$(source "$_java8_root/env"; version=$(cat "$_java8_root/pins/java8"); printf '%s/java8/%s' "$TOOLSHED_OPT_DIR" "$version")
if [[ -x "$_java8_home/bin/java" ]]; then
    export JAVA_HOME="$_java8_home"
    export PATH="$JAVA_HOME/bin:$PATH"
fi
unset _java8_root _java8_home
