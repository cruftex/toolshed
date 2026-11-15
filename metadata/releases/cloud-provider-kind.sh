# Shared release details and validation for this tool.
release_repo=kubernetes-sigs/cloud-provider-kind
release_tag=v
release_asset='cloud-provider-kind_{version}_linux_amd64.tar.gz'
release_member=cloud-provider-kind
validate_tool_binary() {
    validate_release_version "$1" "$2" version
}
