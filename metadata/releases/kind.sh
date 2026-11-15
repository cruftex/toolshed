release_repo=kubernetes-sigs/kind
release_tag=v
release_asset=kind-linux-amd64
release_member=''
validate_tool_binary() {
    local actual
    actual=$("$1" version) || _installer_fail 'Cannot execute kind.'
    [[ $actual == "kind v$2 "* ]] || _installer_fail "Unexpected kind version: $actual"
}
