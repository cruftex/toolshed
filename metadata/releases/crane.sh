# Shared release details and validation for this tool.
release_repo=google/go-containerregistry
release_tag=v
release_asset=go-containerregistry_Linux_x86_64.tar.gz
release_member=crane
release_license_name=apache-2.0
validate_tool_binary() {
    validate_release_version "$1" "$2" version
}
