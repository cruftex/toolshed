# Reproducible development environment

Every installer must reproduce a specific tool version. Pin the version, use a version-specific download URL, and embed the
expected SHA-256 in `metadata/artifacts/<tool>.psv`.
Do not discover `latest` at installer runtime, run unpinned remote installation
scripts, or upgrade tools automatically. Explicit `TOOLSHED_OVERRIDE_TOOL_VERSION` selections must
use repository-recorded verification metadata, or Claude's signed manifest.

## Downloads and verification

- Normal installs and updates must not contact external servers when all
  required downloads and verification materials are cached. This supports
  reliable CI, air-gapped installs, and reusable local tool repositories.
  Discovery may contact publishers to find and cache new releases.

- Claude Code uses a pinned version and is exempt from embedded SHA-256 pins:
  authenticate the versioned manifest with
  Anthropic's GPG key fingerprint `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`, and
  verify the executable against that signed manifest before execution or install.
  Check that the manifest version matches the pinned release. Cache downloads
  under `~/.cache/toolshed/downloads` (configured by `TOOLSHED_DOWNLOAD_DIR`), by tool and version;
  reverify cached signatures and executable checksums before reuse. Keep Claude's
  built-in updater disabled so upgrades happen through the verified installer.

- When adding or updating a tool, actually download each supported archive
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

## Licenses

- Record each tool's license text as a `/license` artifact (`<component>/license` for extra components) in
  `metadata/artifacts/<tool>.psv`; discovery does this with `record_license` in `lib/update.sh`. The text is stored
  once as `metadata/license/<sha256>.txt`, with its short name (lowercase SPDX-style, for example `apache-2.0`,
  `gpl-2.0-classpath`, `oracle-nftc`) in `<sha256>.name.txt`. A changed license text for a recorded version fails discovery.

## Tool descriptors

- Each tool is described by one file, `tools/<tool>.sh`; there are no per-tool install or
  discover scripts. Install with `shed install <tool>` (or `lib/install-tool.sh <tool>`),
  discover with `shed discover <tool>` (or `lib/discover-tool.sh <tool>`).
- Descriptors hold top-level, single-line `key=value` settings (one shell word, quoted as
  needed) that both Bash and `lib/tools.py` read, plus optional hook functions. `kind` says
  where the tool goes: `bin` (one executable into `TOOLSHED_BIN_DIR`), `opt` (multi-file
  package in `$TOOLSHED_OPT_DIR/<tool>/<version>/` with linked entry points), or `scripted`
  (`tool_install`/`tool_discover` hooks do the work). Other keys: `repo`, `tag`, `url`,
  `asset`, `member`, `archive`, `root`, `home`, `links`, `executable`, `version_args`,
  `version_env`, `version_match`, `checksum`, `license`, `license_file`, `table`,
  `components`, `platforms`, `platform_names`, `version_prefix`, `detect`, `discover`,
  `strategy`. Hooks: `tool_validate`, `tool_prepare`, `tool_vars`, `tool_before_install`,
  `tool_latest`, `tool_license`, `tool_after_discovery`, `tool_install`, `tool_discover`.
- Keep descriptors small and declarative; put reusable mechanics in `lib/install.sh`
  (primitives), `lib/tool.sh` (descriptor loading and the generic `bin`/`opt` flows) and
  `lib/update.sh` (discovery). Prefer a new descriptor setting over a hook when several
  tools need the same behaviour.
- Prefer Bash with standard utilities over inline Python: use `jq` for JSON, `awk` for PSV lookups,
  and `grep`/`sed`/`sort` for simple text or XML extraction, then validate results with Bash regexes.
  Keep Python for real logic (`lib/shed.py`, `lib/tools.py`, provenance, PSV validation and writing)
  and for parsing that Bash cannot do well, such as HTML to text (the Oracle license in
  `tools/oracle-java25.sh`). `jq` is a prerequisite; check it with `_installer_require jq`.
- The library loads `env`, owns temporary-file cleanup and signal traps, and
  provides platform, download, extraction, version, and installation helpers.
- Build GitHub asset names using `platform_string` (or run `lib/platform.sh`),
  which maps the host to Bun-style suffixes such as `linux-x64` and
  `darwin-aarch64`. Linux requires glibc. Other projects may use different naming
  conventions. Reject platforms without pinned, test-downloaded checksums; mapping
  a platform name does not imply that an installer supports it.
- Call staging helpers directly, not in command substitutions or subshells, so
  cleanup can track their temporary directories. Do not replace the library traps.
- Use the directories in `env`. Do not invoke sudo or edit shell profiles.
  Users must put `TOOLSHED_BIN_DIR` on their `PATH` themselves.
- Install self-contained, single-file executables directly into `TOOLSHED_BIN_DIR`.
  Install packages with multiple runtime files into
  `$TOOLSHED_OPT_DIR/<tool>/<version>/`, preserving their layout, and link their
  executable entry points into `TOOLSHED_BIN_DIR`.
- `TOOLSHED_OPT_DIR` defaults to `~/opt`; it may be configured as `/opt` for a
  system-wide installation with appropriate existing write permissions.
- Check prerequisites as needed, stage changes before replacing executables, and
  clean up temporary files on success, failure, or interruption.

## Pinned tools

| Tool | Version | Platform | Descriptor |
| --- | --- | --- | --- |
| Bun | 1.4.4 | Linux x86_64, glibc | `tools/bun.sh` |
| Eclipse Temurin Java | 25.0.5+8 | Linux x86_64, glibc | `tools/java25.sh` |
| Oracle Java | 25.0.5 | Linux x86_64, glibc | `tools/oracle-java25.sh` |

Bun's `bunx` entry point is a relative symlink to the `bun` executable.

## Validation

Run `bash -n lib/*.sh tools/*.sh bin/shed` and
`python3 -m unittest discover -s tests -v`. Test downloads, cache reuse, corruption,
interruption cleanup, paths containing spaces, execution from another directory,
and preservation of existing executables on failure. Smoke-test real downloads
in temporary configured directories, verifying installed files and checksums; running
each tool is not required.
Set `BUN_TEST_ARCHIVE` to the downloaded Bun ZIP when running the tests to include
the real Bun/Bunx installation and repeat-install smoke test; it is otherwise skipped.
Also test platform mapping, binary checksum failures, and skipping a matching
installation without a download cache. Confirm modified binaries are reinstalled
even when they still report the pinned version.
