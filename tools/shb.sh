kind=bin
repo=hatoo/shb
tag=v
asset='shb-{platform}'
archive=binary
platforms='linux-x64 linux-aarch64'
platform_names='linux-x64=linux-amd64 linux-aarch64=linux-arm64'
detect=digest
license=mit

# shb has no version command; its help output proves it runs (needs no io_uring).
tool_validate() {
    "$1" --help >/dev/null
}
