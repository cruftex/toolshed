# Toolshed

Toolshed provides installers and shell profiles for a development environment.
The default directories are configured in `env`: downloads use
`~/.cache/toolshed/downloads`, executables and entry points use `~/.local/bin`, and
multi-file packages use `~/opt`. Put `TOOLSHED_BIN_DIR` on your `PATH` yourself;
installers do not edit shell profiles or invoke sudo.

## Principles

- **Predictable versions.** Installers use the versions recorded in this
  repository. Tools change version when you explicitly run an update script.
- **Verified downloads.** Toolshed checks downloads, including cached files,
  before use. A failed verification leaves existing executables in place.
- **Claude Code updates explicitly.** Its installer verifies the pinned release
  using Anthropic's signed manifest and disables Claude's built-in updater.
  Run `./update/update-claude.sh` to select and install the latest release.
- **You control your shell.** Installers do not use sudo or edit shell profiles.
  Source a profile or belt when you want to activate tools in the current shell.
- **Platform support is explicit.** An installer only supports platforms for
  which the repository provides verified downloads.

## Configuration

The settings in `env` also include `TOOLSHED_NVM_DIR` and
`TOOLSHED_CLAUDE_SETTINGS`. When migrating an existing configuration, rename
`DOWNLOAD_DIR`, `DEST_BIN_DIR`, and `DEST_OPT_DIR` to
`TOOLSHED_DOWNLOAD_DIR`, `TOOLSHED_BIN_DIR`, and `TOOLSHED_OPT_DIR`.
These values are assigned by `env`; exported variables do not override them.

## Tool overview

`~/.local/bin` below means the configured `TOOLSHED_BIN_DIR`. Installation is a
separate step from making that directory available on your `PATH`.

| Tool | Installer | Availability after installation |
| --- | --- | --- |
| Bun 1.4.4 | `install/install-bun.sh` | `bun` and `bunx` in `~/.local/bin` |
| Vegeta 12.13.0 | `install/install-vegeta.sh` | `vegeta` in `~/.local/bin` |
| Codex 0.169.0 | `install/install-codex.sh` | `codex` and `codex-code-mode-host` in `~/.local/bin` |
| Claude Code 2.1.322 | `install/install-claude.sh` | `claude` in `~/.local/bin` |
| Oracle Java 25.0.5 | `install/install-java25.sh` | Java executables in `~/.local/bin`; source `profile.d/java25.sh` to set `JAVA_HOME` and prepend Java to `PATH` |
| Maven 3.9.16 | `install/install-maven39.sh` | `mvn39` and selected `mvn` in `~/.local/bin` |
| Maven 3.10.0 | `install/install-maven310.sh` | `mvn310` and selected `mvn` in `~/.local/bin` |
| Maven Daemon 1.0.6 | `install/install-mvnd.sh` | `mvnd` in `~/.local/bin` |
| NVM v0.41.0 | `install/install-nvm.sh` | Source `~/.nvm/nvm.sh` to use the `nvm` shell function |
| Node 24.22.3 | `install/install-node24.sh` | Source `profile.d/node24.sh` to load NVM and select Node 24 |

Source `belts/n24j25.sh` to activate the Node 24 and Java 25 profiles together.
The belt skips missing tools. See the installer and metadata for supported
platforms; Java, Maven, Maven Daemon, Bun and Codex currently pin Linux x86_64
with glibc. Claude also supports Linux arm64 with glibc; Vegeta pins Linux and
macOS on x86_64 and arm64.

## Installation details

Run `./install/install-java25.sh` to install Oracle JDK 25.0.5 on Linux
x86_64 with glibc. The installer verifies the version-specific archive against
the SHA-256 in `metadata/java25.sh` before extraction, installs the JDK under
`$TOOLSHED_OPT_DIR/java25/25.0.5`, and links its executable tools into
`TOOLSHED_BIN_DIR`. It does not use SDKMAN, sudo, or modify shell profiles. Set
`TOOLSHED_BIN_DIR` on your PATH yourself. An incomplete existing Java installation
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
in `TOOLSHED_BIN_DIR`; verified cached archives are reused when needed.

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

Run `./install/install-maven39.sh` for Apache Maven 3.9.16,
`./install/install-maven310.sh` for Maven 3.10.0, and
`./install/install-mvnd.sh` for Apache Maven Daemon 1.0.6 on Linux x86_64
with glibc. Java must be available. The distributions are installed under
`$TOOLSHED_OPT_DIR/maven/<version>` and `$TOOLSHED_OPT_DIR/mvnd/1.0.6`, with `mvn`, `mvn39`, `mvn310`, and
`mvnd` links in `TOOLSHED_BIN_DIR`. Existing incomplete installations are left in
place for manual repair. Maven Daemon keeps a JVM warm between builds; it ships
its own Maven 3.9.16, independent of the separately installed Maven 3.10.0.
It does not automatically enable the Maven Build Cache Extension. The most recently
run Maven installer selects the `mvn` link; `mvn39` and `mvn310` remain
independently available when both versions are installed.
`install/install-maven.sh` remains an alias for the 3.10 installer.

Run `./update/update-maven39.sh` or `./update/update-maven310.sh` to explicitly
update a release line to its latest stable patch. Each updater reads Maven
Central release metadata, downloads the Apache archive, compares its SHA-512
with Apache’s published checksum, checks its version, records its SHA-256 and
updates the pin before installing. This trusts both sources over HTTPS. Normal
installers use only the recorded pins and never discover releases.

On 2026-11-14 both archives were downloaded and their locally calculated SHA-512
matched Apache's published checksums. Their SHA-256 values are:

| Archive | SHA-256 |
| --- | --- |
| [Maven 3.9.16](https://archive.apache.org/dist/maven/maven-3/3.9.16/binaries/apache-maven-3.9.16-bin.tar.gz) | `80ffca22aed9e8b9713a232f3394fd81d7f20322df75efdb2b047dbd3e3a23bb` |
| [Maven 3.10.0](https://archive.apache.org/dist/maven/maven-3/3.10.0/binaries/apache-maven-3.10.0-bin.tar.gz) | `a46cc51bc74fa23fd267c7a0b9132b146dcf526da60d31aa5174e565632e9e0e` |
| [Maven Daemon 1.0.6](https://archive.apache.org/dist/maven/mvnd/1.0.6/maven-mvnd-1.0.6-linux-amd64.tar.gz) | `88fd474fd3f21b33ec1e6a75950f6abbe493d63a5e2b429475f5230b3ee6cb24` |

All three installers and repeat installations succeeded in temporary paths containing
spaces; the linked commands reported their pinned versions. Maven Daemon's
version check was also run through its installed link with an isolated registry.

NVM 0.41.0 uses the [versioned source archive](https://github.com/nvm-sh/nvm/archive/refs/tags/v0.41.0.tar.gz)
with locally calculated SHA-256 `532560c9ecc6ef484279fcc1c600e9346537bc7913b891ffd0ec0caca5072694`.
Node 24.22.3 uses the [Linux x64 archive](https://nodejs.org/dist/v24.22.3/node-v24.22.3-linux-x64.tar.gz)
with SHA-256 `061ec3e3062115705b56b51fa9cc330ab50d34b6969387d4e4b1a50c6809acc2`,
matching Node.js's published checksum. On 2026-11-14, both were installed twice
in a temporary path containing spaces; Node evaluated `1+1` and npm reported
11.19.1. These installers currently support Linux x86_64 with glibc.
