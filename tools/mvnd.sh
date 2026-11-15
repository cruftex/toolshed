kind=opt
url='https://archive.apache.org/dist/maven/mvnd/{version}/maven-mvnd-{version}-linux-amd64.tar.gz'
root='maven-mvnd-{version}-linux-amd64'
links=bin/mvnd
detect=link
discover=none
license=apache-2.0

# Check the version with a private daemon storage, and stop the daemon that the check starts.
tool_validate() {
    local home=$1 version=$2 storage output
    [[ -x $home/bin/mvnd ]] || return 1
    stage_directory storage
    output=$("$home/bin/mvnd" "-Dmvnd.daemonStorage=$storage" --version) || return 1
    "$home/bin/mvnd" "-Dmvnd.daemonStorage=$storage" --stop >/dev/null || _installer_fail 'Cannot stop test daemon.'
    [[ $output == *"Apache Maven Daemon (mvnd) $version"* ]]
}
