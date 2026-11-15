kind=bin
repo=kubernetes-sigs/controller-runtime
tag=v
asset=setup-envtest-linux-amd64
archive=binary
detect=digest
license=apache-2.0

# setup-envtest has no version command; listing installed assets proves it runs.
tool_validate() {
    local binary=$1 staging
    stage_directory staging
    "$binary" list -i --bin-dir "$staging" >/dev/null
}
