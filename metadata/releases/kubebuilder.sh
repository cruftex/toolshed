# Shared release details and validation for this tool.
release_repo=kubernetes-sigs/kubebuilder
release_tag=v
release_asset=kubebuilder_linux_amd64
release_member=''
validate_tool_binary() {
    validate_release_version "$1" "$2" version
}
