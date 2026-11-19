#!/usr/bin/env bash
set -euo pipefail

failed=0
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
for tool in $(bin/shed discoverable); do
    echo "Discovering $tool"
    if ! version=$(lib/discover-tool.sh "$tool") || [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Discovery failed or returned an invalid version: $tool" >&2
        git restore --staged --worktree -- metadata
        git clean -fd -- metadata
        failed=1
        continue
    fi
    echo "Discovered $version"
    git add -- metadata
    if ! git diff --cached --quiet; then
        git commit -m "Update: $tool $version"
    fi
done

git push origin HEAD:main
exit "$failed"
