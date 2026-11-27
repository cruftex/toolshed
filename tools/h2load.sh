kind=opt
repo=nghttp2/nghttp2
tag=v
url='https://github.com/nghttp2/nghttp2/releases/download/v{version}/nghttp2-{version}.tar.gz'
root='nghttp2-{version}'
links=bin/h2load
license=mit
license_file=COPYING
strategy='Verified source built into opt'

# nghttp2 publishes source only. Build just h2load from the verified archive, without optional features, so the
# result does not depend on which optional libraries the host has. nghttp2 1.71 needs C++23 (<print>, GCC 14).
h2load_compiler() {
    local candidate
    for candidate in ${CXX:-} g++-15 g++-14 c++; do
        command -v "$candidate" >/dev/null 2>&1 || continue
        if printf '#include <print>\nint main() { std::println("ok"); }\n' |
            "$candidate" -std=c++23 -x c++ -fsyntax-only - 2>/dev/null; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    _installer_fail 'h2load needs a C++23 compiler with <print> (for example: sudo apt install g++-14).'
}

tool_prepare() {
    local root=$1 log=$1/../h2load-build.log cxx jobs kept
    _installer_require make cc pkg-config
    cxx=$(h2load_compiler) || exit 1
    jobs=$(nproc 2>/dev/null || echo 2)
    printf 'Building h2load with %s\n' "$cxx" >&2
    if ! ( cd -- "$root" &&
            ./configure CXX="$cxx" --enable-app --disable-shared --disable-hpack-tools --disable-examples \
                --disable-failmalloc --without-libxml2 --without-jansson --without-libevent-openssl \
                --without-wolfssl --without-jemalloc --without-systemd --without-libngtcp2 --without-libnghttp3 \
                --without-libbpf &&
            make -j"$jobs" -C lib && make -j"$jobs" -C third-party && make -j"$jobs" -C src h2load
        ) > "$log" 2>&1; then
        tail -n 30 -- "$log" >&2
        _installer_fail 'Cannot build h2load (needs libev-dev libc-ares-dev libssl-dev zlib1g-dev).'
    fi
    # Keep only the executable, its manual page and the license.
    kept="$root/../h2load-kept"
    mkdir -p -- "$kept/bin" "$kept/share/man/man1"
    mv -- "$root/src/h2load" "$kept/bin/h2load"
    mv -- "$root/doc/h2load.1" "$kept/share/man/man1/h2load.1"
    mv -- "$root/COPYING" "$kept/COPYING"
    find "$root" -mindepth 1 -delete
    mv -- "$kept"/* "$root/"
    rmdir -- "$kept"
}

tool_validate() {
    local output
    [[ -f $1/bin/h2load && -x $1/bin/h2load ]] || return 1
    output=$("$1/bin/h2load" --version 2>&1) || return 1
    [[ $output == "h2load nghttp2/$2" ]]
}
