kind=opt
url='https://nodejs.org/dist/v{version}/node-v{version}-linux-x64.tar.gz'
root='node-v{version}-linux-x64'
home='{nvm}/versions/node/v{version}'
links=
detect=node
discover=none
license=mit+third-party
strategy='Verified archive in NVM directory'

# Node versions live in the NVM directory, so NVM is installed first.
tool_before_install() {
    env -u TOOLSHED_OVERRIDE_TOOL_VERSION "$_installer_library_dir/install-tool.sh" nvm
}

tool_validate() {
    local home=$1 version=$2 output
    [[ -x $home/bin/node && -x $home/bin/npm ]] || return 1
    output=$("$home/bin/node" --version) || return 1
    [[ $output == "v$version" ]]
}
