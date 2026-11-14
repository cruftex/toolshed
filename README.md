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

Run `./install/install-toolshed.sh` to link `shed` into `TOOLSHED_BIN_DIR`,
then run `shed available` to see tools, their default pins, and recorded versions.
The link points into this checkout, which must remain in place. You can also
run `./bin/shed available` directly.
Install a tool with its `install/install-<tool>.sh` script; for example:

```bash
./install/install-bun.sh
TOOLSHED_OVERRIDE_TOOL_VERSION=3.9.16 ./install/install-maven39.sh
```

Java, Maven, Maven Daemon, Bun, Codex, Node and NVM currently support Linux
x86_64 with glibc. Claude also supports Linux arm64 with glibc; Vegeta supports
Linux and macOS on x86_64 and arm64. Installers reject unsupported platforms.
Set `TOOLSHED_OVERRIDE_TOOL_VERSION` for a single installer invocation to select
a recorded version without changing the default pin; availability depends on
the platform. Claude accepts versions verified by its signed manifest.

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
- `shed discover` checks the internet for releases, verifies and caches them,
  and records their metadata. It does not install them or change pins; tools
  without an updater are reported and skipped.

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
