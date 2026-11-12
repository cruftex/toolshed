#!/usr/bin/env bash
# Bun-style GitHub release asset suffix (for example, linux-x64).
set -euo pipefail

case $(uname -s) in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    *) printf 'Unsupported operating system\n' >&2; exit 1 ;;
esac
case $(uname -m) in
    x86_64|amd64) arch=x64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *) printf 'Unsupported architecture\n' >&2; exit 1 ;;
esac
if [[ $os == linux ]] && ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
    printf 'Linux glibc is required\n' >&2
    exit 1
fi
printf '%s-%s\n' "$os" "$arch"
