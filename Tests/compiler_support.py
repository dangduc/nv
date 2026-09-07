"""Header paths for the standalone Cocoa test harnesses."""
from pathlib import Path


def include_flags(repo):
    repo = Path(repo)
    directories = [repo, repo / 'Config']
    directories.extend(sorted(path for path in (repo / 'Sources').iterdir() if path.is_dir()))
    directories.extend(repo / 'ThirdParty' / path for path in (
        'Crypto', 'JSON', 'MAAttachedWindow', 'ODBEditor', 'PTHotKeys',
        'RBSplitView', 'OpenSSL/include',
    ))
    return [flag for directory in directories for flag in ('-I', str(directory))]
