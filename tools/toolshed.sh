kind=scripted
discover=none
detect=none
strategy='Toolshed command in bin'

tool_install() {
    local target="$toolshed_root/bin/shed"
    (( $# == 0 )) || _installer_fail 'Unexpected installer arguments.'
    [[ -x $target ]] || _installer_fail "Missing executable: $target"
    if [[ -e $TOOLSHED_BIN_DIR/shed || -L $TOOLSHED_BIN_DIR/shed ]]; then
        [[ -L $TOOLSHED_BIN_DIR/shed && $(readlink -- "$TOOLSHED_BIN_DIR/shed") == "$target" ]] ||
            _installer_fail "Destination already exists: $TOOLSHED_BIN_DIR/shed"
    fi
    install_symlink "$target" shed
    printf 'Toolshed command is installed in %s\n' "$TOOLSHED_BIN_DIR"
}
