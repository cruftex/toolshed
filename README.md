# Toolshed

Checksum-verified installers for a reproducible development environment. Claude
Code installs the latest release using a GPG-authenticated manifest; other tools
use pinned versions. Downloads are cached in `~/.cache/toolshed`, configured by
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
