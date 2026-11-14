#!/usr/bin/env bash
set -euo pipefail

failed=0
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
for script in discover/discover-*.sh; do
    echo "Running $script"
    if ! version=$("$script") || [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Discovery failed or returned an invalid version: $script" >&2
        git restore --staged --worktree -- metadata
        git clean -fd -- metadata
        failed=1
        continue
    fi
    echo "Discovered $version"
    git add -- metadata
    if ! git diff --cached --quiet; then
        tool=${script#discover/discover-}
        tool=${tool%.sh}
        git commit -m "Update: $tool $version"
    fi
done

git push origin HEAD:main
exit "$failed"
