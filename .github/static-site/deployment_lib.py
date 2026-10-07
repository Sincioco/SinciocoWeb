"""Local-only deployment paths and publication boundaries."""
from pathlib import Path, PurePosixPath
import hashlib, json

ROOT = Path(__file__).resolve().parent
WEBSITE = ROOT / 'website'
PRIVATE_PARTS = {'deployment', 'tools', 'azure-tooling', 'node_modules', 'diagnostics',
                 'backups', 'production', '__pycache__', '.git', '.azure', '.aws', '.swa', '.codex'}
PRIVATE_NAMES = {'readme.md', 'web.config', 'deploy-free-site.ps1', 'prepare-site.py',
                 'verify-stage.py', 'verify-live.ps1', 'deployment.json', 'sources.json',
                 'publish-files.json', 'payload-manifest.json', 'deployment.lock',
                 'pages-migration-contract.json', 'verification-http.ps1', 'verify-seo-live.ps1'}
PRIVATE_SUFFIXES = {'.pfx', '.p12', '.pem', '.key', '.kdbx', '.log', '.bak', '.user'}

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def public_relative(value):
    path = PurePosixPath(value)
    if not value or '\\' in value or ':' in value or path.is_absolute() or '..' in path.parts:
        raise ValueError('Publication path must be relative and contained: ' + value)
    parts = [part.casefold() for part in path.parts]
    if any(part in PRIVATE_PARTS or (part.startswith('.') and part != '.well-known') for part in parts):
        raise ValueError('Private directory/file cannot be published: ' + value)
    if path.name.casefold() in PRIVATE_NAMES or path.suffix.casefold() in PRIVATE_SUFFIXES:
        raise ValueError('Private file cannot be published: ' + value)
    if any(word in path.name.casefold() for word in ('credential', 'token-cache', 'deployment-result')):
        raise ValueError('Credential/diagnostic file cannot be published: ' + value)
    return Path(*path.parts)

def reject_links(path, boundary):
    boundary = boundary.absolute()
    path = path.absolute()
    if not path.is_relative_to(boundary):
        raise ValueError('Path leaves its approved directory: ' + str(path))
    for current in (path, *path.parents):
        if current.is_symlink() or current.is_junction():
            raise ValueError('Symbolic links/junctions are not accepted: ' + str(current))
        if current == boundary:
            return

def source_path(record):
    sources = read_json(ROOT / 'sources.json')
    if record['source'] not in ('main', 'novel'):
        raise ValueError('Unknown source kind')
    root = (ROOT / sources[record['source']]).absolute()
    candidate = root / public_relative(record['path'])
    reject_links(candidate, root)
    if not candidate.is_file():
        raise ValueError('Approved source file is missing: ' + str(candidate))
    return candidate

def records_for_payload(directory):
    import os
    records = []
    reject_links(directory, ROOT)
    for folder, dirs, files in os.walk(directory, followlinks=False):
        for name in dirs + files:
            path = Path(folder) / name
            reject_links(path, directory)
            relative = path.relative_to(directory).as_posix()
            public_relative(relative)
            if path.is_file():
                records.append({'path': relative, 'bytes': path.stat().st_size, 'sha256': sha(path)})
    return sorted(records, key=lambda item: item['path'])
