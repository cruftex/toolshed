# Shared release details and validation for this tool.
release_repo=mikefarah/yq
release_tag=v
release_asset=yq_linux_amd64
release_member=''
release_license_name=mit
validate_tool_binary() {
    validate_release_version "$1" "$2" --version
}
