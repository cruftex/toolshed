#!/usr/bin/env bash

_node24_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$_node24_root/env"
export NVM_DIR="$TOOLSHED_NVM_DIR"

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    . "$NVM_DIR/nvm.sh" --no-use
    nvm use --silent "$(cat "$_node24_root/pins/node24")"
fi
unset _node24_root
