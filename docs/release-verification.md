# Release verification records

## Installation details

### Eclipse Temurin Java 25 (`java25`)

License: GPLv2 with the Classpath Exception, from the archive's `legal/java.base/LICENSE`, stored as
`metadata/license/4b9abebc….txt` (name in `4b9abebc….name.txt`).

`shed install java25` installs Eclipse Temurin 25.0.5+8 (Linux x86_64, glibc) under
`$TOOLSHED_OPT_DIR/java25/25.0.5` and links its tools into `TOOLSHED_BIN_DIR`. The
[archive](https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.5%2B8/OpenJDK25U-jdk_x64_linux_hotspot_25.0.5_8.tar.gz)
had locally calculated SHA-256 `68982529869257d0ee6b824ec5aa270ff8b118bb438670da0b97ebdab178d7fb`,
matching Adoptium's published checksum. Smoke test 2026-11-15: installed twice from a verified cache;
the second run skipped the matching installation. The build number is pinned in `metadata/java25-builds`.
`shed discover java25` reads Adoptium's latest-release API and records the digest without moving the pin.

### Oracle JDK 25 (`oracle-java25`)

License: Oracle No-Fee Terms and Conditions (NFTC), stored as `metadata/license/df43f6a3….txt` (name in `df43f6a3….name.txt`)
(plain-text extraction of Oracle's page, last updated 12 September 2021, fetched 2026-11-15). The installer prints it.

Run `shed install oracle-java25` to install Oracle JDK 25.0.5 on Linux
x86_64 with glibc. The installer verifies the version-specific archive against
the SHA-256 in `metadata/artifacts/oracle-java25.psv` before extraction and installs the JDK under
`$TOOLSHED_OPT_DIR/oracle-java25/25.0.5`. It does not link into `TOOLSHED_BIN_DIR`; source `profile.d/oracle-java25.sh`. It does not use SDKMAN, sudo, or modify shell profiles. Set
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
`shed discover oracle-java25` checks Oracle's current Java 25 release and published
checksum, verifies and tests its archive, records its digest without moving the pin or installing it. Updates trust Oracle's release metadata and checksum over HTTPS.

Activate the Node 24 and Java 25 collection in your current shell with
`source /path/to/toolshed/belts/n24j25.sh`. Belts activate installed tools;
they do not install them. Missing tools are skipped. Re-sourcing the belt
preserves unrelated PATH changes without accumulating its own entries.

Run `shed install codex` to install Codex 0.169.0 and its matching
`codex-code-mode-host` on Linux x86_64 with glibc. Both executables are installed
in `TOOLSHED_BIN_DIR`; verified cached archives are reused when needed.

Bun and Vegeta use the same metadata layout: their pins are in `pins/`, and
source archive digests are in `metadata/artifacts/`. Explicit updates use
`shed discover bun` or `shed discover vegeta`. They verify archives
against GitHub release digests and record source checksums without running the
installer. Vegeta's updater downloads all four supported
platform archives. These GitHub digests rely on release metadata over HTTPS.

The Codex pin is in `pins/codex`; the source archive digests for both
components are in `metadata/artifacts/codex.psv`.
Run `shed discover codex` to explicitly update Codex. It reads the latest
stable GitHub release, verifies both downloaded archives against GitHub's release
digests and records the source checksums without changing the pin
or installing the release. This update trusts GitHub's release metadata over HTTPS; its digests
are not independently authenticated. The updater records metadata in this checkout. Normal installs do not look up releases.

On 2026-11-15, the pinned Codex, kubectl, Helm, Go, Java 25, Node, Maven
3.9 and 3.10, and mvnd downloads listed below were downloaded again; each
SHA-256 matched the artifact table, and each publisher checksum matched where
available. The pinned NVM Git tag and commit were fetched again and its generated
archive matched the pinned SHA-256. Fresh and repeat installs passed in isolated
temporary paths. Codex, kubectl, and Helm also repaired modified executables and
emitted warnings. Maven Daemon required an unsandboxed local daemon smoke test.
Claude Code 2.1.325's freshly downloaded signed manifest was checked against
the pinned fingerprint; Linux x64 and ARM64 binaries matched its checksums. The
x64 installer passed fresh, repeat, and modified-binary warning and repair tests.
The [Linux x64 binary](https://downloads.claude.ai/claude-code-releases/2.1.325/linux-x64/claude)
has SHA-256 `0dc4f4a9a165fc60746d7ae8489712e5fc352f1e7ad4eb22e7141bd0812eb0cf`;
the [Linux ARM64 binary](https://downloads.claude.ai/claude-code-releases/2.1.325/linux-arm64/claude)
has SHA-256 `7b6e484b1989a5a14a4b354709ccc8672518a3ec5b9ccd7981fc6254327fde67`.
The ARM64 binary was checksum-verified but not executed on the x64 host.

Codex smoke test on 2026-11-13, Linux x86_64: the locally calculated archive
SHA-256 values matched GitHub's release digests:

| Release archive | Archive SHA-256 | Extracted executable SHA-256 |
| --- | --- | --- |
| [Codex 0.169.0](https://github.com/openai/codex/releases/download/rust-v0.169.0/codex-x86_64-unknown-linux-musl.tar.gz) | `9af4d751fce183faedea629437d5252dbf458eeb04130cf4f97be844621ea985` | `b452ca20f838a8855a88a41050ee4a694033fff4ea3ecdad5633e6e0e8d13f2b` |
| [Code mode host 0.169.0](https://github.com/openai/codex/releases/download/rust-v0.169.0/codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz) | `cbed6a8d25e8268792b757767fbc76d4c62e84bcf8ee4a63f97547f0de3aaceb` | `e9f2ef68671b2b6ac68902d19e8dafda3f5928e678ecf3f30c74b203a2c403ed` |

Installation and repeat installation in temporary directories succeeded;
`codex --version` reported `codex-cli 0.169.0` and the host's `--help` ran.

The Vegeta 12.13.0 release archives were downloaded and hashed on 2026-11-13;
all four archive hashes in `metadata/artifacts/vegeta.psv` matched GitHub's release digests,
and the extracted binary hashes matched the metadata. Installation, repeat
installation and `vegeta --version` succeeded for Linux x86_64. Bun 1.4.4's
real archive installation and repeat installation passed in the test suite.
On 2026-11-15, the Bun 1.4.4 ZIP and all four Vegeta 12.13.0 platform archives
were downloaded again. Each source SHA-256 matched its artifact table and GitHub
release asset digest. On Linux x86_64, fresh installation, repeat installation,
modified-executable repair, and preservation on a missing-cache download failure
passed for both tools. Archive-based repeat installs now require the verified
archive, including when the installed executable already matches.

| Download | Source SHA-256 |
| --- | --- |
| [Bun 1.4.4 Linux x64](https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-linux-x64.zip) | `bf8ccbfb2b0b80159e0f9a6d15c55317add8077534dbc6130a3edb52fccb395c` |
| [Vegeta 12.13.0 Linux x64](https://github.com/tsenart/vegeta/releases/download/v12.13.0/vegeta_12.13.0_linux_amd64.tar.gz) | `e8759ce45c14e18374bdccd3ba6068197bc3a9f9b7e484db3837f701b9d12e61` |
| [Vegeta 12.13.0 Linux ARM64](https://github.com/tsenart/vegeta/releases/download/v12.13.0/vegeta_12.13.0_linux_arm64.tar.gz) | `950381173a5575e25e8e086f36fc03bf65d61a2433329b48e41e1cb5e4133bba` |
| [Vegeta 12.13.0 macOS x64](https://github.com/tsenart/vegeta/releases/download/v12.13.0/vegeta_12.13.0_darwin_amd64.tar.gz) | `4e912c83ce07db4e1e394e1cbb657f2396dff2f7ed90f03869a184cc17d0f994` |
| [Vegeta 12.13.0 macOS ARM64](https://github.com/tsenart/vegeta/releases/download/v12.13.0/vegeta_12.13.0_darwin_arm64.tar.gz) | `fc408e242c4f4839e6fe536dbf1130bb02f430134827f6d831bf367a0929a799` |

Run `shed install maven39` for Apache Maven 3.9.16,
`shed install maven310` for Maven 3.10.0, and
`shed install mvnd` for Apache Maven Daemon 1.0.6 on Linux x86_64
with glibc. Java must be available. The distributions are installed under
`$TOOLSHED_OPT_DIR/maven/<version>` and `$TOOLSHED_OPT_DIR/mvnd/1.0.6`, with `mvn`, `mvn39`, `mvn310`, and
`mvnd` links in `TOOLSHED_BIN_DIR`. Existing incomplete installations are left in
place for manual repair. Maven Daemon keeps a JVM warm between builds; it ships
its own Maven 3.9.16, independent of the separately installed Maven 3.10.0.
It does not automatically enable the Maven Build Cache Extension. The most recently
run Maven installer selects the `mvn` link; `mvn39` and `mvn310` remain
independently available when both versions are installed.

Run `shed discover maven39` or `shed discover maven310` to explicitly
update a release line to its latest stable patch. Each updater reads Maven
Central release metadata, downloads the Apache archive, compares its SHA-512
with Apache’s published checksum, checks its version, records its SHA-256 and
leaves the pin and installation unchanged. This trusts both sources over HTTPS. Normal
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

NVM 0.41.0 is prepared from Git tag object
`43d410caa64ba7928cef750e31fccbf5790c210c` and commit
`4e8758a801eea9479b32a904f31093e410ddaba4` at
https://github.com/nvm-sh/nvm.git. The versioned `git archive` bundle, without
Git metadata, has SHA-256
`6601b5bbd0af01a2faf17267e73e02b0e44f3b4fcdb85cf8f4602c6a0791909b`.
Its extracted files were compared with the previously verified GitHub release
archive. A temporary-directory upgrade and repeat installation succeeded on
Linux x86_64, preserving an existing Node directory and backing up legacy Git
metadata.
On 2026-11-15, the cached NVM 0.41.0 Git archive was rehashed against the
recorded SHA-256 and used to smoke-test a fresh install, platform-cache migration,
and repeat installation in a temporary path containing spaces; `nvm --version`
reported 0.41.0. This check reused the existing archive without downloading it.

Kubernetes tools were downloaded and tested on Linux x86_64 with glibc:

| Tool | Versioned download | Download SHA-256 | Executable SHA-256 |
| --- | --- | --- | --- |
| kubectl 1.34.1 | [kubectl](https://dl.k8s.io/release/v1.34.1/bin/linux/amd64/kubectl) | `7721f265e18709862655affba5343e85e1980639395d5754473dafaadcaa69e3` | `7721f265e18709862655affba5343e85e1980639395d5754473dafaadcaa69e3` |
| Helm 3.19.0 | [Linux archive](https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz) | `a7f81ce08007091b86d8bd696eb4d86b8d0f2e1b9f6c714be62f82f96a594496` | `e4722a77de9df824214aaf19d43687c49f7cbcf3b107905acea002173777d486` |

Both download digests matched the publishers' versioned SHA-256 files. The
installers succeeded in temporary paths containing spaces, including repeated
installation and installation with the cache removed; both commands reported
their pinned versions. kubectl also reported bundled Kustomize 5.7.1.

kind 0.30.0 and clusterctl 1.11.1 were downloaded for Linux x86_64 with glibc.
The executable SHA-256 values, which also serve as download digests, are:

- [kind 0.30.0](https://github.com/kubernetes-sigs/kind/releases/download/v0.30.0/kind-linux-amd64): `517ab7fc89ddeed5fa65abf71530d90648d9638ef0c4cde22c2c11f8097b8889` (matched the publisher checksum).
- [clusterctl 1.11.1](https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.11.1/clusterctl-linux-amd64): `94ddb3bf1a3fbf296ffcda19a55173be7d37baed495c27006578e868033ea10d` (matched the GitHub release asset digest).

Both executables reported their pinned versions; their installers were smoke-tested
from the verified cache and repeated in temporary paths containing spaces.
On 2026-11-15, both assets were downloaded again and matched the recorded hashes
and GitHub release asset digests. The refactored installers passed installation,
reinstallation from cache, and a repeat with the cache removed.

The following Linux x86_64 release assets were downloaded, hashed locally and
matched against the publishers’ GitHub release asset digests. Installers were
smoke-tested in temporary paths containing spaces, then repeated without a cache.
For setup-envtest the smoke test used `list -i` because it has no version command.
On 2026-11-15, all ten assets in this table were downloaded again and their
archive hashes matched both the recorded pins and the GitHub release asset
digests; their extracted executable hashes also matched the recorded pins. The
refactored installers succeeded in temporary paths containing spaces, reinstalled
from the verified cache after removing the executable, and skipped replacement
on a further run after the cache was removed. Each installation validated the
executable using its tool-specific version check (or `list -i` for setup-envtest).
The same cached assets were retested after moving their release definitions into
per-tool files; the hash and installation checks passed again.
After switching these installers to source-artifact metadata, the same verified
downloads were tested again: installation, reinstallation from cache, and repair
of a modified executable all passed. Archive-based repeat installs now verify
and extract their cached archive to compare executable bytes.

| Tool | Versioned asset | Download SHA-256 | Executable SHA-256 |
| --- | --- | --- | --- |
| cloud-provider-kind 0.12.0 | [download](https://github.com/kubernetes-sigs/cloud-provider-kind/releases/download/v0.12.0/cloud-provider-kind_0.12.0_linux_amd64.tar.gz) | `5716aca8f01a85172c12f3b6329c70f151bec02c91b6f600c9f230845ee138e6` | `e29a3a9970e5da68aeb630ec365ac0da69094d5b6c5dca4409bc5783cf4d6482` |
| kubebuilder 4.16.0 | [download](https://github.com/kubernetes-sigs/kubebuilder/releases/download/v4.16.0/kubebuilder_linux_amd64) | `539984e58832044f2326b1bb940c1eaf784f1849e65d06d3a4a4a8b5dfac7ca7` | `539984e58832044f2326b1bb940c1eaf784f1849e65d06d3a4a4a8b5dfac7ca7` |
| controller-gen 0.23.0 | [download](https://github.com/kubernetes-sigs/controller-tools/releases/download/v0.23.0/controller-gen-linux-amd64) | `849fc06f331c18ea4dcffd3f9c7e0d8d4a51013b57bbe60bc726fc125f9784a3` | `849fc06f331c18ea4dcffd3f9c7e0d8d4a51013b57bbe60bc726fc125f9784a3` |
| setup-envtest 0.25.2 | [download](https://github.com/kubernetes-sigs/controller-runtime/releases/download/v0.25.2/setup-envtest-linux-amd64) | `94534f83896f3b09934d9570b213fbda04aa5c17457942270928cdca0317bf9b` | `94534f83896f3b09934d9570b213fbda04aa5c17457942270928cdca0317bf9b` |
| golangci-lint 2.15.0 | [download](https://github.com/golangci/golangci-lint/releases/download/v2.15.0/golangci-lint-2.15.0-linux-amd64.tar.gz) | `9b7fe6a6bf6334b98decf8d86b11415ea7889afdabdd1959fdce23af2a9ebcea` | `d9af4564c05beb2f5e130119aec45e5e89d28e5017d558d3ca382659f2427894` |
| cosign 3.1.4 | [download](https://github.com/sigstore/cosign/releases/download/v3.1.4/cosign-linux-amd64) | `424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa` | `424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa` |
| crane 0.22.1 | [download](https://github.com/google/go-containerregistry/releases/download/v0.22.1/go-containerregistry_Linux_x86_64.tar.gz) | `0ab7a1d6932a213aed964ce97666c3077fe691c8606413674a8b3e0b9ec4cda0` | `8e75c326adb43b053cfd78b9b987663f8f4fe4557f4d3915905643f25c730992` |
| trivy 0.76.2 | [download](https://github.com/aquasecurity/trivy/releases/download/v0.76.2/trivy_0.76.2_Linux-64bit.tar.gz) | `bc0fc726e017b8927a62b2d3531d7a84ee01769daf5c99ed866dced54089fdbf` | `6a972c69606c7b3ea4c6bdcc6fc9332ea9ad38381624310c1e85cc77345909f3` |
| yq 4.54.3 | [download](https://github.com/mikefarah/yq/releases/download/v4.54.3/yq_linux_amd64) | `129534601871538efe0ba4c5e62a34fb1d5f469bcb975c4fddeb467d82974973` | `129534601871538efe0ba4c5e62a34fb1d5f469bcb975c4fddeb467d82974973` |
| kustomize 5.8.3 | [download](https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v5.8.3/kustomize_v5.8.3_linux_amd64.tar.gz) | `cb9e31198d3f63b44848bd0afc4c8efc56e6cfef9c93a4a39a211940e6decd61` | `a5e53d28755098b003ae2b6bff7b1650a411a366a0c800c1ea1b677e0cfff747` |

Go 1.27.4 was downloaded from the [Linux x86_64 archive](https://go.dev/dl/go1.27.4.linux-amd64.tar.gz).
Its locally calculated SHA-256, `7226736c2339719cda28fbf3a54d71aa63bcefe376e98cef00034268dab24840`,
matched Go's published checksum. The installer and repeat installation succeeded
in a temporary path containing spaces, including with the download cache removed.
The installed `gofmt` formatted a Go program and `go run` built and ran it. The
installed toolchain defaults to `GOTOOLCHAIN=local` to prevent automatic toolchain
downloads; an explicit environment or user configuration can override that default.
