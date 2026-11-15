#!/usr/bin/env bash
_oracle_java25_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
_oracle_java25_home=$(source "$_oracle_java25_root/env"; version=$(cat "$_oracle_java25_root/pins/oracle-java25"); printf '%s/oracle-java25/%s' "$TOOLSHED_OPT_DIR" "$version")
if [[ -x "$_oracle_java25_home/bin/java" ]]; then
    export JAVA_HOME="$_oracle_java25_home"
    export PATH="$JAVA_HOME/bin:$PATH"
fi
unset _oracle_java25_root _oracle_java25_home
