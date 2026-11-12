#!/usr/bin/env bash

_java25_home="${SDKMAN_DIR:-$HOME/.sdkman}/candidates/java/25.0.5.0-oracle"
if [[ -x "$_java25_home/bin/java" ]]; then
    export JAVA_HOME="$_java25_home"
    export PATH="$JAVA_HOME/bin:$PATH"
fi
unset _java25_home
