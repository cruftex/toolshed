# Shared release details and validation for this tool.
release_repo=aquasecurity/trivy
release_tag=v
release_asset='trivy_{version}_Linux-64bit.tar.gz'
release_member=trivy
release_license_name=apache-2.0
validate_tool_binary() {
    validate_release_version "$1" "$2" version
}
