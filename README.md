# Toolshed

Checksum-verified installers for a reproducible development environment. Claude
Code installs the latest release using a GPG-authenticated manifest. All other tools use pinned versions. Downloads are cached in `~/.cache/toolshed`, configured by
`DOWNLOAD_DIR` in `env`.

Repository and directory name: `toolshed`.

Run `./install/install-java25.sh` to install Oracle JDK 25.0.5 on Linux
x86_64 with glibc. The installer verifies the version-specific archive against
the SHA-256 in `metadata/java25.sh` before extraction, installs the JDK under
`$DEST_OPT_DIR/java25/25.0.5`, and links its executable tools into
`DEST_BIN_DIR`. It does not use SDKMAN, sudo, or modify shell profiles. Set
`DEST_BIN_DIR` on your PATH yourself. An incomplete existing Java installation
is left in place and must be repaired manually.

We install directly because the SDKMAN response for the Oracle Java 25.0.5
candidate did not include a checksum, and its download hook repackaged Oracle's
tarball as a ZIP. Direct installation lets Toolshed verify the original archive
against an embedded SHA-256 before extraction and avoids depending on SDKMAN's
API and download hooks during installation.

The [Oracle JDK 25.0.5 archive](https://download.oracle.com/java/25/archive/jdk-25.0.5_linux-x64_bin.tar.gz)
had locally calculated SHA-256
`8748e3837bbceabfa17548564b6d814d123bd820e947e30dff885202b6f24f2c`,
matching [Oracle's checksum](https://download.oracle.com/java/25/archive/jdk-25.0.5_linux-x64_bin.tar.gz.sha256).
A temporary-directory smoke test installed it twice, checked `java --version`,
and compiled and ran a Java program.
`./update/update-java25.sh` checks Oracle's current Java 25 release and published
checksum, verifies and tests its archive, records its digest, moves the pin,
and installs it. Updates trust Oracle's release metadata and checksum over HTTPS.

Activate the Node 24 and Java 25 collection in your current shell with
`source /path/to/toolshed/belts/n24j25.sh`. Belts activate installed tools;
they do not install them. Missing tools are skipped. Re-sourcing the belt
preserves unrelated PATH changes without accumulating its own entries.

Run `./install/install-codex.sh` to install Codex 0.169.0 and its matching
`codex-code-mode-host` on Linux x86_64 with glibc. Both executables are installed
in `DEST_BIN_DIR`; verified cached archives are reused when needed.

Bun and Vegeta use the same metadata layout: their pins are in `pins/`, and
paired archive and executable digests are in `metadata/`. Explicit updates use
`./update/update-bun.sh` or `./update/update-vegeta.sh`. They verify archives
against GitHub release digests and calculate executable digests before recording
them and running the installer. Vegeta's updater downloads all four supported
platform archives. These GitHub digests rely on release metadata over HTTPS.

The Codex pin is in `pins/codex`; the archive and executable digests for each
component are in `metadata/codex.sh` and `metadata/codex-code-mode-host.sh`.
Run `./update/update-codex.sh` to explicitly update Codex. It reads the latest
stable GitHub release, verifies both downloaded archives against GitHub's release
digests, records the calculated executable digests, moves the pin, and runs the
installer. This update trusts GitHub's release metadata over HTTPS; its digests
are not independently authenticated. The updater modifies this checkout and
installs to the configured destination. Normal installs do not look up releases.

Codex smoke test on 2026-11-13, Linux x86_64: the locally calculated archive
SHA-256 values matched GitHub's release digests:

| Release archive | Archive SHA-256 | Extracted executable SHA-256 |
| --- | --- | --- |
| [Codex 0.169.0](https://github.com/openai/codex/releases/download/rust-v0.169.0/codex-x86_64-unknown-linux-musl.tar.gz) | `9af4d751fce183faedea629437d5252dbf458eeb04130cf4f97be844621ea985` | `b452ca20f838a8855a88a41050ee4a694033fff4ea3ecdad5633e6e0e8d13f2b` |
| [Code mode host 0.169.0](https://github.com/openai/codex/releases/download/rust-v0.169.0/codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz) | `cbed6a8d25e8268792b757767fbc76d4c62e84bcf8ee4a63f97547f0de3aaceb` | `e9f2ef68671b2b6ac68902d19e8dafda3f5928e678ecf3f30c74b203a2c403ed` |

Installation and repeat installation in temporary directories succeeded;
`codex --version` reported `codex-cli 0.169.0` and the host's `--help` ran.

The Vegeta 12.13.0 release archives were downloaded and hashed on 2026-11-13;
all four archive hashes in `metadata/vegeta.sh` matched GitHub's release digests,
and the extracted binary hashes matched the metadata. Installation, repeat
installation and `vegeta --version` succeeded for Linux x86_64. Bun 1.4.4's
real archive installation and repeat installation passed in the test suite.
