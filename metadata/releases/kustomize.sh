# Shared release details and validation for this tool.
release_repo=kubernetes-sigs/kustomize
release_tag=kustomize/v
release_asset='kustomize_v{version}_linux_amd64.tar.gz'
release_member=kustomize
validate_tool_binary() {
    validate_release_version "$1" "$2" version
}
