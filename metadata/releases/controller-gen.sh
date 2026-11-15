# Shared release details and validation for this tool.
release_repo=kubernetes-sigs/controller-tools
release_tag=v
release_asset=controller-gen-linux-amd64
release_member=''
release_license_name=apache-2.0
validate_tool_binary() {
    validate_release_version "$1" "$2" --version
}
