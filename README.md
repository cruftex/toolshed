# Toolshed

Checksum-verified installers for a reproducible development environment. Claude
Code installs the latest release using a GPG-authenticated manifest. All other tools use pinned versions. Downloads are cached in `~/.cache/toolshed`, configured by
`DOWNLOAD_DIR` in `env`.

Repository and directory name: `toolshed`.

Run `./install/install-java25.sh` to install Oracle JDK 25.0.5 through SDKMAN
(`25.0.5.0-oracle`, checked against SDKMAN's catalog on 2026-11-12). It reuses an
existing SDKMAN installation or bootstraps SDKMAN 5.24.0 with native commands 0.8.0.
Both installers currently support Linux x86_64 with glibc. Configure `SDKMAN_DIR`
in `env` if the default `~/.sdkman` is unsuitable.

Java installation preserves your SDKMAN default. To select it in your current shell:

```bash
source "$HOME/.sdkman/bin/sdkman-init.sh" # use your configured SDKMAN_DIR if different
sdk use java 25.0.5.0-oracle
```

Use `sdk default java 25.0.5.0-oracle` yourself if you want it as the default for
future shells. The installers do not edit shell profiles or use sudo. Incomplete
existing SDKMAN or Java installations produce an error and require manual repair.

SDKMAN bootstrap archives use embedded SHA-256 pins and verified caches under
`DOWNLOAD_DIR`. Java uses SDKMAN's own cache, download hooks, and verification
policy, as documented in the repository's SDKMAN exception. SDKMAN may omit
checksum verification when its download metadata supplies no checksum; this
occurred for the Oracle candidate in the real smoke test.

Verified downloads (Linux x86_64, 2026-11-12):

| Release archive | Locally calculated SHA-256 (matches publisher) |
| --- | --- |
| [SDKMAN 5.24.0](https://github.com/sdkman/sdkman-cli/releases/download/5.24.0/sdkman-cli-5.24.0.zip) | `b765ef213c7b3dd731815e42f398b6e2eef1053b38d32ecc09a9f6d51c8ee948` |
| [SDKMAN native 0.8.0](https://github.com/sdkman/sdkman-cli-native/releases/download/v0.8.0/sdkman-cli-native-0.8.0-x86_64-unknown-linux-gnu.zip) | `91cc56bce077fb605172d6bb3182ab2a1b1711d64f12a8bbb1910dc11d561397` |
| [Oracle JDK 25.0.5](https://download.oracle.com/java/25/archive/jdk-25.0.5_linux-x64_bin.tar.gz) | `8748e3837bbceabfa17548564b6d814d123bd820e947e30dff885202b6f24f2c` |

Real smoke test passed entirely under `/tmp`: SDKMAN reports core 5.24.0 and native
0.8.0; Java and Javac report 25.0.5; compiling and running a small program succeeds;
repeat installations succeed without creating a Java default. These checks did
not alter the user's existing SDKMAN installation.

Activate the Node 24 and Java 25 collection in your current shell with
`source /path/to/toolshed/belts/n24j25.sh`. Belts activate installed tools;
they do not install them. Missing tools are skipped. Re-sourcing the belt
preserves unrelated PATH changes without accumulating its own entries.

Run `./install/install-codex.sh` to install Codex 0.169.0 and its matching
`codex-code-mode-host` on Linux x86_64 with glibc. Both executables are installed
in `DEST_BIN_DIR`; verified cached archives are reused when needed.

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
