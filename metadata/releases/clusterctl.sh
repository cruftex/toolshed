release_repo=kubernetes-sigs/cluster-api
release_tag=v
release_asset=clusterctl-linux-amd64
release_member=''
release_license_name=apache-2.0
validate_tool_binary() {
    local actual
    actual=$(CLUSTERCTL_DISABLE_VERSIONCHECK=true "$1" version -o short) || _installer_fail 'Cannot execute clusterctl.'
    [[ $actual == "v$2"* ]] || _installer_fail "Unexpected clusterctl version: $actual"
}
