# Reproducible development environment

Every installer must reproduce a specific tool version. Pin the version, use a
version-specific download URL, and embed the expected SHA-256 in the installer.
Do not discover `latest` at runtime, accept version overrides, run unpinned remote
installation scripts, or upgrade tools automatically.

## Downloads and verification

- When adding or updating an installer, actually download each supported archive
  and calculate its SHA-256 locally. Compare it with the publisher's checksum when
  available. Record the version, URL, digest, and smoke-test result in the change.
- Verify SHA-256 before extraction or execution, including cached downloads.
  Reject mismatches; never replace the expected digest with an unchecked value
  obtained at installation time.
- For single-executable downloads, also pin the extracted executable's SHA-256,
  calculated from the verified test archive. Verify it before execution or
  installation. Check the installed executable's bytes and executable permission
  first; skip downloading, extracting, and replacing it when its digest matches.
  A version string alone is insufficient. Still repair missing entry-point links.
- Store archive and executable digests in Bash associative arrays named
  `archive_sha256` and `binary_sha256`, keyed by `<version>/<platform>` (for example,
  `1.4.4/linux-x64`). Select both using the pinned version and detected platform.
  Reject missing entries before downloading or installing; never fall back to
  another version or platform. Add tested entries to support additional pairs
  while retaining the explicit default version pin.
- Keep caches version-specific. Download through temporary files and only promote
  verified files. Fail without replacing installed executables on download,
  checksum, extraction, or version-check errors.

## Installer conventions

- Put executable Bash installers in `install/`, named `install-<tool>.sh`, with
  `set -euo pipefail`. Always use the `.sh` extension for installer scripts.
- Keep installers roughly 15–20 readable lines. Put reusable mechanics in
  `lib/install.sh`; keep tool-specific pins and installation steps in the installer.
- Source the library relative to the installer, not the current working directory.
  The library loads `env`, owns temporary-file cleanup and signal traps, and
  provides platform, download, extraction, version, and installation helpers.
- Build GitHub asset names using `platform_string` (or run `lib/platform.sh`),
  which maps the host to Bun-style suffixes such as `linux-x64` and
  `darwin-aarch64`. Linux requires glibc. Other projects may use different naming
  conventions. Reject platforms without pinned, test-downloaded checksums; mapping
  a platform name does not imply that an installer supports it.
- Call staging helpers directly, not in command substitutions or subshells, so
  cleanup can track their temporary directories. Do not replace the library traps.
- Use the directories in `env`. Do not invoke sudo or edit shell profiles.
  Users must put `DEST_BIN_DIR` on their `PATH` themselves.
- Install self-contained, single-file executables directly into `DEST_BIN_DIR`.
  Install packages with multiple runtime files into
  `$DEST_OPT_DIR/<tool>/<version>/`, preserving their layout, and link their
  executable entry points into `DEST_BIN_DIR`.
- `DEST_OPT_DIR` defaults to `~/opt`; it may be configured as `/opt` for a
  system-wide installation with appropriate existing write permissions.
- Check prerequisites as needed, stage changes before replacing executables, and
  clean up temporary files on success, failure, or interruption.

## Pinned tools

| Tool | Version | Platform | Installer |
| --- | --- | --- | --- |
| Bun | 1.4.4 | Linux x86_64, glibc | `install/install-bun.sh` |

Bun's `bunx` entry point is a relative symlink to the `bun` executable.

## Validation

Run `bash -n lib/install.sh lib/platform.sh install/install-bun.sh` and
`python3 -m unittest discover -s tests -v`. Test downloads, cache reuse, corruption,
interruption cleanup, paths containing spaces, execution from another directory,
and preservation of existing executables on failure. Smoke-test real downloads
in temporary configured directories, including the pinned version and basic use.
Set `BUN_TEST_ARCHIVE` to the downloaded Bun ZIP when running the tests to include
the real Bun/Bunx installation and repeat-install smoke test; it is otherwise skipped.
Also test platform mapping, binary checksum failures, and skipping a matching
installation without a download cache. Confirm modified binaries are reinstalled
even when they still report the pinned version.
