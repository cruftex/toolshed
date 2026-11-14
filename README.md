# Toolshed

Toolshed installs verified, pinned development tools. Installers do not use
sudo or edit shell profiles. Add `~/.local/bin` (or `TOOLSHED_BIN_DIR` from
`env`) to your `PATH` to use installed commands.

## Offline-first installs

Normal installs and `shed update` use verified cached downloads without
contacting external servers when all required files are cached. This reduces
CI failures during outages and supports air-gapped installs and a reusable
local tool repository. For Claude Code, the cache must also contain its signed
manifest, signature, and signing key. `shed discover` contacts publishers to
find and cache new releases.

## Available tools

The table shows the latest version recorded in this checkout, which may differ
from the default pin and from the latest upstream release. Regenerate it after
metadata changes with `./update-readme.py`.

<!-- tools-table:start -->
| Tool | Latest recorded version | Install strategy |
| --- | --- | --- |
| [bun](install/install-bun.sh) | 1.4.4 | Verified executable in bin |
| [claude](install/install-claude.sh) | 2.1.325 | Signed manifest; executable in bin |
| [cloud-provider-kind](install/install-cloud-provider-kind.sh) | 0.12.0 | Verified executable in bin |
| [clusterctl](install/install-clusterctl.sh) | 1.14.4 | Verified executable in bin |
| [codex](install/install-codex.sh) | 0.169.0 | Verified executables in bin |
| [controller-gen](install/install-controller-gen.sh) | 0.23.0 | Verified executable in bin |
| [cosign](install/install-cosign.sh) | 3.1.4 | Verified executable in bin |
| [crane](install/install-crane.sh) | 0.22.1 | Verified executable in bin |
| [go](install/install-go.sh) | 1.27.4 | Verified package in opt; entry points in bin |
| [golangci-lint](install/install-golangci-lint.sh) | 2.15.0 | Verified executable in bin |
| [helm](install/install-helm.sh) | 3.19.0 | Verified executable in bin |
| [java25](install/install-java25.sh) | 25.0.5 | Verified package in opt; entry points in bin; source [`profile.d/java25.sh`](profile.d/java25.sh) |
| [kind](install/install-kind.sh) | 0.30.0 | Verified executable in bin |
| [kubebuilder](install/install-kubebuilder.sh) | 4.16.0 | Verified executable in bin |
| [kubectl](install/install-kubectl.sh) | 1.34.1 | Verified executable in bin |
| [kustomize](install/install-kustomize.sh) | 5.8.3 | Verified executable in bin |
| [maven310](install/install-maven310.sh) | 3.10.0 | Verified package in opt; entry points in bin |
| [maven39](install/install-maven39.sh) | 3.9.16 | Verified package in opt; entry points in bin |
| [mvnd](install/install-mvnd.sh) | 1.0.6 | Verified package in opt; entry points in bin |
| [node24](install/install-node24.sh) | 24.22.3 | Verified archive in NVM directory; source [`profile.d/node24.sh`](profile.d/node24.sh) |
| [nvm](install/install-nvm.sh) | 0.41.0 | Verified Git archive in NVM directory |
| [setup-envtest](install/install-setup-envtest.sh) | 0.25.2 | Verified executable in bin |
| [trivy](install/install-trivy.sh) | 0.76.2 | Verified executable in bin |
| [vegeta](install/install-vegeta.sh) | 12.13.0 | Verified executable in bin |
| [yq](install/install-yq.sh) | 4.54.3 | Verified executable in bin |
<!-- tools-table:end -->

Run `./install/install-toolshed.sh` to link `shed` into `TOOLSHED_BIN_DIR`,
then run `shed available` to see tools, their default pins, and recorded versions.
The link points into this checkout, which must remain in place. You can also
run `./bin/shed available` directly.
Install a tool with its `install/install-<tool>.sh` script; for example:

```bash
./install/install-bun.sh
TOOLSHED_OVERRIDE_TOOL_VERSION=3.9.16 ./install/install-maven39.sh
```

Java, Maven, Maven Daemon, Bun, Codex, Node, NVM, Go, kubectl, Helm, kind, clusterctl, and the controller and release tools currently support Linux
x86_64 with glibc. Claude also supports Linux arm64 with glibc; Vegeta supports
Linux and macOS on x86_64 and arm64. Installers reject unsupported platforms.
Set `TOOLSHED_OVERRIDE_TOOL_VERSION` for a single installer invocation to select
a recorded version without changing the default pin; availability depends on
the platform. Claude accepts versions verified by its signed manifest.

kubectl provides the Kubernetes CLI (including Kustomize); Helm manages Kubernetes packages.
kind runs local Kubernetes clusters using containers; clusterctl manages Cluster API providers.
Choose a kubectl version compatible with your cluster. The standalone `kustomize`
can be installed separately. Go installs both `go` and `gofmt` and defaults to `GOTOOLCHAIN=local` to avoid automatic toolchain downloads. The `gh`
command is available from its upstream APT repository.

Toolshed also provides cloud-provider-kind, kubebuilder, controller-gen,
setup-envtest, golangci-lint, cosign, crane, trivy, and Mike Farah’s yq.
setup-envtest downloads Kubernetes test assets separately when requested.

## Activation

Most commands are available in `TOOLSHED_BIN_DIR` after installation. Source
`profile.d/node24.sh` to activate Node, or `profile.d/java25.sh` to set
`JAVA_HOME` and activate Java. Source `belts/n24j25.sh` to activate both in the
current shell. These scripts do not install missing tools.
The profiles select the pinned versions, including after an installation with
an override.

Maven installs provide `mvn39` and `mvn310` independently. The most recently
run Maven installer also selects the `mvn` command. Maven Daemon's `mvnd`
uses its own bundled Maven and does not enable the Maven Build Cache Extension.

## Managing installed tools

- `shed installed` shows installed versions and whether a newer release is
  recorded for the current platform. It checks configured locations offline.
- `shed update` updates installed tools to the newest compatible version already
  recorded in this checkout, then moves each pin after installation succeeds.
- `shed discover` first pulls the checkout's upstream changes using a fast-forward
  only pull, then checks the internet for releases, verifies and caches them,
  and records their metadata. It does not install them or change pins; tools
  without an updater are reported and skipped. Discovery stops if the pull fails.

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

Scripts in `discover/` discover and cache verified releases without installing
them. Normal installers use the repository’s pins unless a version is selected.
Claude’s built-in updater is disabled; use `shed discover` and `shed update`. Downloads, including cached files, are
verified before use. See [release verification records](docs/release-verification.md)
for archive checksums, sources, and smoke tests.

The GitHub Actions discovery workflow runs daily and can also be started manually.
It checks discovery scripts on Linux x86_64 until one produces new metadata, then
scans every tool and commits each tool's verified metadata separately to `main`.
If a discovery fails, the workflow continues scanning other tools and reports a
failure after pushing successful commits. Repository settings must permit the
workflow token to push to `main`, including any applicable branch protection rules.
