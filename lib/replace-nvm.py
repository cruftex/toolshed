#!/usr/bin/env python3
"""Replace NVM's runtime files with rollback; retain a backup of prior files."""
import os
from pathlib import Path
import shutil
import signal
import sys
import tempfile

source, destination, git_cache = map(Path, sys.argv[1:])
names = ('nvm-exec', 'bash_completion', 'nvm.sh')
for name in names:
    if not (source / name).is_file():
        sys.exit(f'Missing NVM release file: {name}')
    target = destination / name
    if target.is_symlink() or (target.exists() and not target.is_file()):
        sys.exit(f'Unsupported existing NVM file: {target}')
backup = Path(tempfile.mkdtemp(prefix='.toolshed-nvm-backup-', dir=destination))
staging = Path(tempfile.mkdtemp(prefix='.toolshed-nvm-stage-', dir=destination))
replaced = []
git_backup = None

def interrupt(signum, frame):
    raise InterruptedError(f'interrupted by signal {signum}')

for sig in (signal.SIGINT, signal.SIGTERM):
    signal.signal(sig, interrupt)
try:
    for name in names:
        target = destination / name
        if target.exists():
            shutil.copy2(target, backup / name)
        shutil.copy2(source / name, staging / name)
    for name in names:
        os.replace(staging / name, destination / name)
        replaced.append(name)
    git_metadata = destination / '.git'
    if git_metadata.exists() or git_metadata.is_symlink():
        if not git_cache.is_dir():
            raise RuntimeError('NVM Git cache missing; run ./prepare-nvm-git.sh first')
        legacy = git_cache / 'legacy-checkouts'
        legacy.mkdir(exist_ok=True)
        git_backup = Path(tempfile.mkdtemp(prefix='nvm-', dir=legacy))
        os.replace(git_metadata, git_backup / '.git')
except BaseException:
    if git_backup is not None:
        if (git_backup / '.git').exists():
            os.replace(git_backup / '.git', destination / '.git')
        git_backup.rmdir()
    for name in reversed(replaced):
        old = backup / name
        if old.exists():
            os.replace(old, destination / name)
        else:
            (destination / name).unlink(missing_ok=True)
    shutil.rmtree(backup)
    raise
finally:
    shutil.rmtree(staging, ignore_errors=True)
print(f'Previous NVM files backed up in {backup}')
if git_backup is not None:
    print(f'Previous Git metadata saved in {git_backup / ".git"}')
