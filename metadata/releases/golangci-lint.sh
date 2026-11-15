# Shared release details and validation for this tool.
release_repo=golangci/golangci-lint
release_tag=v
release_asset='golangci-lint-{version}-linux-amd64.tar.gz'
release_member='golangci-lint-{version}-linux-amd64/golangci-lint'
validate_tool_binary() {
    validate_release_version "$1" "$2" version
}
