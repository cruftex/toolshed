# Toolshed

Toolshed installs verified, pinned development tools. Installers do not use
sudo or edit shell profiles. Add `~/.local/bin` (or `TOOLSHED_BIN_DIR` from
`env`) to your `PATH` to use installed commands.

Requirements: Bash, coreutils, curl, tar, jq and Python 3 (for discovery and
`shed` reporting).

## Offline-first installs

Normal installs and `shed update` use verified cached downloads without
contacting external servers when all required files are cached. This reduces
CI failures during outages and supports air-gapped installs and a reusable
local tool repository. `shed discover` contacts publishers to find and cache new
releases.

## Available tools

The table shows the latest version recorded in this checkout, which may differ
from the default pin and from the latest upstream release. Regenerate it after
metadata changes with `./update-readme.sh`.

<!-- tools-table:start -->
| Tool | Latest recorded version | Install strategy |
| --- | --- | --- |
| [bun](tools/bun.sh) | 1.4.5 | Verified executable in bin |
| [claude](tools/claude.sh) | 2.1.332 | Verified executable in bin; checksums from the signed manifest |
| [cloud-provider-kind](tools/cloud-provider-kind.sh) | 0.12.0 | Verified executable in bin |
| [clusterctl](tools/clusterctl.sh) | 1.14.4 | Verified executable in bin |
| [codex](tools/codex.sh) | 0.172.0 | Verified executables in bin |
| [controller-gen](tools/controller-gen.sh) | 0.23.0 | Verified executable in bin |
| [cosign](tools/cosign.sh) | 3.1.6 | Verified executable in bin |
| [crane](tools/crane.sh) | 0.22.1 | Verified executable in bin |
| [gh](tools/gh.sh) | 2.106.0 | Verified executable in bin |
| [go](tools/go.sh) | 1.27.4 | Verified package in opt; entry points in bin |
| [golangci-lint](tools/golangci-lint.sh) | 2.15.0 | Verified executable in bin |
| [h2load](tools/h2load.sh) | 1.71.0 | Verified source built into opt |
| [helm](tools/helm.sh) | 4.3.2 | Verified executable in bin |
| [java25](tools/java25.sh) | 25.0.5.1 | Eclipse Temurin; verified package in opt; entry points in bin; source [`profile.d/java25.sh`](profile.d/java25.sh) |
| [java8](tools/java8.sh) | 8.0.514 | Eclipse Temurin; verified package in opt; activate with profile; source [`profile.d/java8.sh`](profile.d/java8.sh) |
| [kind](tools/kind.sh) | 0.33.0 | Verified executable in bin |
| [kubebuilder](tools/kubebuilder.sh) | 4.16.0 | Verified executable in bin |
| [kubectl](tools/kubectl.sh) | 1.37.3 | Verified executable in bin |
| [kustomize](tools/kustomize.sh) | 5.8.3 | Verified executable in bin |
| [maven310](tools/maven310.sh) | 3.10.2 | Verified package in opt; entry points in bin |
| [maven39](tools/maven39.sh) | 3.9.16 | Verified package in opt; entry points in bin |
| [mvnd](tools/mvnd.sh) | 1.0.6 | Verified package in opt; entry points in bin |
| [node24](tools/node24.sh) | 24.22.3 | Verified archive in NVM directory; source [`profile.d/node24.sh`](profile.d/node24.sh) |
| [nvm](tools/nvm.sh) | 0.41.0 | Verified Git archive in NVM directory |
| [oracle-java25](tools/oracle-java25.sh) | 25.0.5 | Oracle JDK; verified package in opt; activate with profile; source [`profile.d/oracle-java25.sh`](profile.d/oracle-java25.sh) |
| [setup-envtest](tools/setup-envtest.sh) | 0.25.3 | Verified executable in bin |
| [shb](tools/shb.sh) | 0.6.0 | Verified executable in bin |
| [trivy](tools/trivy.sh) | 0.76.2 | Verified executable in bin |
| [vegeta](tools/vegeta.sh) | 12.13.0 | Verified executable in bin |
| [yq](tools/yq.sh) | 4.54.3 | Verified executable in bin |
<!-- tools-table:end -->

Run `./bin/shed install toolshed` to link `shed` into `TOOLSHED_BIN_DIR`,
then run `shed available` to see each tool's default pin, installed version, and recorded version count.
The link points into this checkout, which must remain in place.
Install tools with `shed install`; for example:

```bash
shed install bun kubectl
TOOLSHED_OVERRIDE_TOOL_VERSION=3.9.16 shed install maven39
```

Each tool is described by a single file, `tools/<tool>.sh`: a few `key=value`
settings (where it goes — `bin`, `opt` or `scripted` — download URL, archive
member, version check, license) and, where needed, small hook functions. The
generic install and discovery logic lives in `lib/`.

Java, Maven, Maven Daemon, Bun, Codex, Node, NVM, Go, kubectl, Helm, kind, clusterctl, and the controller and release tools currently support Linux
x86_64 with glibc. Claude also supports Linux arm64 with glibc; Vegeta supports
Linux and macOS on x86_64 and arm64. Installers reject unsupported platforms.
Set `TOOLSHED_OVERRIDE_TOOL_VERSION` for a single installer invocation to select
a recorded version without changing the default pin; availability depends on
the platform.

kubectl provides the Kubernetes CLI (including Kustomize); Helm manages Kubernetes packages.
kind runs local Kubernetes clusters using containers; clusterctl manages Cluster API providers.
Choose a kubectl version compatible with your cluster. The standalone `kustomize`
can be installed separately. Go installs both `go` and `gofmt` and defaults to `GOTOOLCHAIN=local` to avoid automatic toolchain downloads.

Toolshed also provides cloud-provider-kind, kubebuilder, controller-gen,
setup-envtest, golangci-lint, cosign, crane, trivy, the GitHub CLI (`gh`), and Mike Farah’s yq.
setup-envtest downloads Kubernetes test assets separately when requested.

## Version schemes

Versions appear in pins, `TOOLSHED_OVERRIDE_TOOL_VERSION`, the artifact tables in `metadata/artifacts/`,
discovery and every `shed` report. Toolshed has to validate them, read them from a tool's own output, and order
them to decide whether an update exists. Products number their releases differently, so each descriptor declares
its scheme with `version_scheme` (default `semver2`). Versions are recorded the way the product itself numbers them,
never in a form that loses information.

| Scheme | Accepts | Recorded as | Standard |
| --- | --- | --- | --- |
| `semver2` | `MAJOR.MINOR.PATCH`, e.g. `1.27.4`; the version core only, without pre-release (`-rc1`) or build (`+4`) parts, because toolshed records releases | as given | [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) |
| `jdk-jep322` | `FEATURE.INTERIM.UPDATE[.PATCH[.EXTRA]]`, three to five numbers, e.g. `25.0.5.1` | at least three parts: GA `25` is `25.0.0`; installed JDKs are compared in the printed form without trailing zeros (`25`) | [JEP 322: Time-Based Release Versioning](https://openjdk.org/jeps/322) |

All schemes are dotted numbers compared part by part, with missing parts counting as zero
(`25.0.5` < `25.0.5.1` < `25.0.6`).

SemVer has exactly three numbers and cannot express a fourth one. A pre-release suffix sorts *before* the release,
and build metadata is ignored when comparing. Temurin 25.0.5.1+2, a JDK patch release, shows the problem:
Adoptium's API reports it as `25.0.5+100000002` in its `semver` field, which by SemVer's rules compares equal to
25.0.5. Java 25 therefore uses `jdk-jep322` and records `25.0.5.1`. Java 8 predates JEP 322 and uses `semver2` with
Adoptium's `8.0.<update>` form.

## Licenses

Each tool version's license text is stored once in `metadata/license/<sha256>.txt`, with its short name in `<sha256>.name.txt`; the tool's
`metadata/artifacts/<tool>.psv` lists it as a `/license` row with that SHA-256. For example,
`awk -F'|' '$2 ~ /license/' metadata/artifacts/oracle-java25.psv` gives the hash, and
`cat metadata/license/<hash>.name.txt` the name (Oracle JDK uses the Oracle No-Fee Terms and Conditions,
`oracle-nftc`; Eclipse Temurin uses GPLv2 with the Classpath Exception, `gpl-2.0-classpath`).
Licenses were backfilled for all current tools from the project's `LICENSE` file at the release tag
(Claude Code: its `LICENSE.md`, `proprietary`; Bun and Node.js include bundled third-party licenses, `mit+third-party`).
Discovery records the license automatically for every tool with discovery; mvnd, Node.js and NVM have none yet.

## Activation

Most commands are available in `TOOLSHED_BIN_DIR` after installation. Source
`profile.d/node24.sh` to activate Node, or `profile.d/java25.sh` to set
`JAVA_HOME` and activate Eclipse Temurin Java. Oracle JDK is installed by
`shed install oracle-java25` into opt only (no `bin` links); source
`profile.d/oracle-java25.sh` to use it. Source `belts/n24j25.sh` to activate Node 24 and Java 25 in the
current shell. These scripts do not install missing tools.
The profiles select the pinned versions, including after an installation with
an override.

Eclipse Temurin Java 8 (`shed install java8`) is a full JDK (compiler and runtime) installed into
`$TOOLSHED_OPT_DIR/java8/<version>` only; it adds no `bin` links, so `java` and `javac` in
`TOOLSHED_BIN_DIR` stay with Java 25. Opt in per shell by sourcing `profile.d/java8.sh`, which sets
`JAVA_HOME` and puts Java 8 first on `PATH`. Maven 3.9 runs on Java 8 and uses `JAVA_HOME`:

```bash
shed install maven39 java8
source /path/to/toolshed/profile.d/java8.sh
mvn39 -v        # Java version: 1.8.0_514, vendor: Temurin
mvn39 package
```

Java 8 versions are recorded in Adoptium's `8.0.<update>` form (`8.0.514` is `8u514`); the download URL,
which also carries the build number, is recorded in `metadata/artifacts/java8.psv`. Java 25 versions may have
four parts, e.g. `TOOLSHED_OVERRIDE_TOOL_VERSION=25.0.5.1 shed install java25`; see
[Version schemes](#version-schemes).

Maven installs provide `mvn39` and `mvn310` independently. The most recently
run Maven installer also selects the `mvn` command. Maven Daemon's `mvnd`
uses its own bundled Maven and does not enable the Maven Build Cache Extension.

nghttp2 publishes h2load only as source. `shed install h2load` verifies the pinned
source archive and builds only h2load into `$TOOLSHED_OPT_DIR/h2load/<version>/`,
without HTTP/3 or other optional features. The build needs a C++23 compiler with
`<print>` (GCC 14: `g++-14`; `CXX` selects another) and
`libev-dev libc-ares-dev libssl-dev zlib1g-dev pkg-config`. The built executable
depends on the local toolchain, so only the source archive's digest is pinned.

shb is an io_uring HTTP/1.1, HTTP/2 and HTTP/3 load generator; it needs Linux 6.0 or newer.
Upstream publishes statically linked (musl) executables for x86_64 and aarch64. shb has no
version flag, so `shed` identifies the installed version by the executable's recorded digest.

## Managing installed tools

- `shed installed` shows installed versions and whether a newer release is
  recorded for the current platform. It checks configured locations offline.
- `shed update` updates installed tools to the newest compatible version recorded
  at least eight days ago, then moves each pin after installation succeeds. Use
  `shed update --delay-days 0` for immediate uptake or specify another number
  of days. The current pin remains eligible, including for repairs.
- `shed discover` first pulls the checkout's upstream changes using a fast-forward
  only pull, then checks the internet for releases, verifies and caches them,
  and records their metadata. It does not install them or change pins; tools
  without an updater are reported and skipped. Discovery stops if the pull fails.

Successful discovery records the first verification time, checksum source URL,
effective URL, and connected peer IP in `metadata/provenance/`, per version and
platform. The IP is the network peer reported by curl; when a proxy is used it
may identify the proxy rather than the publisher. Missing values are recorded as
null. Update eligibility reads discovery times from `metadata/artifacts/` rather
than provenance. Existing entries without a recorded time are
not eligible for delayed updates until rediscovered; `--delay-days 0` permits
them immediately. Tools without discovery retain their existing pins.
When a verified rediscovery fills a missing peer address or effective URL, its
observation time is recorded separately; it does not change an existing discovery time.
Backfilled entries marked `timestamp_source: cache_mtime` use the verified local
cache file's modification time as an approximation of discovery time; their
checksum-source URL and peer remain unknown until observed during rediscovery.

Only tools found in Toolshed’s configured directories are considered. Node
status lists installed Node 24 versions and compares the newest one. NVM updates
preserve Node versions and settings, and back up replaced files and any existing
Git metadata. Run `./prepare-nvm-git.sh` first to prepare the pinned NVM archive
from the Git mirror; installers use that verified archive offline.
Update commands can change the selected `mvn` link.

## Configuration and updates

Edit `env` to configure the download cache (default
`~/.cache/toolshed/downloads`), executable directory (`~/.local/bin`), package
directory (`~/opt`), NVM directory, NVM Git cache, and Claude settings file. Values in `env`
are assigned directly and do not inherit exported overrides.

Release metadata in `metadata/artifacts/` uses pipe-separated
`version|artifact|sha256|discovered_at` rows. Artifact IDs contain the optional
component name, target platform, and source type, such as `/linux-x64/binary`
or `host/linux-x64/archive/tar.gz`. Tables may add a fifth `url` column with the
artifact's download URL, recorded by discovery when it cannot be derived from the version (the Temurin JDKs,
whose URLs carry a build number); installs then download from that URL, and the download cache path follows
from it. Like the digest, a recorded URL never changes. Claude's SHA-256 values come from its versioned
manifest, which discovery authenticates with Anthropic's signing key before it
downloads and checks each executable. Archive-backed single-executable
installs verify the archive and compare its extracted bytes on repeat installs.

Downloads are cached under `TOOLSHED_DOWNLOAD_DIR/<platform>/`. Existing
unpartitioned downloads are verified and copied into the platform cache on use;
the originals are left in place. NVM's prepared Git archive follows the same
layout. Normal installs remain offline when the required verified cache exists.

`shed discover [TOOL...]` discovers and caches verified releases without installing
them. Normal installs use the repository’s pins unless a version is selected.
Claude’s built-in updater is disabled; use `shed discover` and `shed update`. Downloads, including cached files, are
verified before use. See [release verification records](docs/release-verification.md)
for archive checksums, sources, and smoke tests.

The GitHub Actions discovery workflow runs daily and can also be started manually.
It runs discovery on Linux x86_64 for every tool with discovery, scanning every tool and commits each tool's verified metadata separately to `main`.
If a discovery fails, the workflow continues scanning other tools and reports a
failure after pushing successful commits. Repository settings must permit the
workflow token to push to `main`, including any applicable branch protection rules.
