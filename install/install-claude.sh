#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-2.1.322}"
BASE_URL="https://downloads.claude.ai/claude-code-releases"
INSTALL_DIR="$HOME/.local/share/claude/versions"
LINK="$HOME/.local/bin/claude"

# Detect architecture.
case "$(uname -s)/$(uname -m)" in
    Linux/x86_64)  PLATFORM="linux-x64" ;;
    Linux/aarch64) PLATFORM="linux-arm64" ;;
    *)
        echo "Error: Unsupported platform." >&2
        exit 1
        ;;
esac

TARGET="$INSTALL_DIR/$VERSION"

# Download only if this version isn't installed.
if [[ ! -x "$TARGET" ]]; then
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT

    URL="$BASE_URL/$VERSION"

    # Download signed manifest and public key.
    curl -fsSL "$URL/manifest.json" -o "$TMP/manifest.json"
    curl -fsSL "$URL/manifest.json.sig" -o "$TMP/manifest.json.sig"
    curl -fsSL \
        https://downloads.claude.ai/keys/claude-code.asc \
        -o "$TMP/key.asc"

    # Verify signing key.
    FINGERPRINT="$(
        gpg --show-keys --with-colons "$TMP/key.asc" |
        awk -F: '$1 == "fpr" {print $10; exit}'
    )"

    EXPECTED="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

    if [[ "$FINGERPRINT" != "$EXPECTED" ]]; then
        echo "Error: Invalid Anthropic signing key." >&2
        exit 1
    fi

    # Verify manifest signature.
    mkdir -m 700 "$TMP/gnupg"

    gpg --homedir "$TMP/gnupg" --batch --quiet \
        --import "$TMP/key.asc"

    gpg --homedir "$TMP/gnupg" --batch \
        --verify "$TMP/manifest.json.sig" "$TMP/manifest.json"

    # Extract platform checksum.
    CHECKSUM="$(
        python3 - "$TMP/manifest.json" "$PLATFORM" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    manifest = json.load(f)

print(manifest["platforms"][sys.argv[2]]["checksum"])
PY
    )"

    # Download executable.
    curl -fSL "$URL/$PLATFORM/claude" -o "$TMP/claude"

    # Verify checksum.
    echo "$CHECKSUM  $TMP/claude" | sha256sum -c -

    # Install versioned executable.
    mkdir -p "$INSTALL_DIR"
    install -m 755 "$TMP/claude" "$TARGET"
fi

# Expose executable in ~/.local/bin.
mkdir -p "$(dirname "$LINK")"

if [[ -e "$LINK" && ! -L "$LINK" ]]; then
    echo "Error: $LINK exists and is not a symlink." >&2
    exit 1
fi

ln -sfn "$TARGET" "$LINK"

# Disable Claude Code's built-in updater.
# Preserve all other settings if the file already exists.
SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$SETTINGS")"

python3 - "$SETTINGS" <<'PY'
import json
import os
import stat
import sys
import tempfile

path = sys.argv[1]

if os.path.exists(path):
    with open(path) as f:
        settings = json.load(f)
    mode = stat.S_IMODE(os.stat(path).st_mode)
else:
    settings = {}
    mode = 0o600

settings.setdefault("env", {})["DISABLE_UPDATES"] = "1"

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
try:
    os.fchmod(fd, mode)
    with os.fdopen(fd, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY

echo "Claude Code $("$LINK" --version) installed successfully."
echo "Built-in updates disabled."
