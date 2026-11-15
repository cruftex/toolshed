# Shared release details and validation for this tool.
release_repo=kubernetes-sigs/controller-runtime
release_tag=v
release_asset=setup-envtest-linux-amd64
release_member=''
validate_tool_binary() {
    local binary=$1 staging
    stage_directory staging
    "$binary" list -i --bin-dir "$staging" >/dev/null || _installer_fail 'Cannot run setup-envtest.'
}
