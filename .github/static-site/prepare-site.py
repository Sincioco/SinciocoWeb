"""Rebuild only the explicitly approved public files; never crawl the source tree."""
from datetime import datetime, timezone
from pathlib import Path
import argparse, json, os, shutil, tempfile
from deployment_lib import ROOT, WEBSITE, read_json, public_relative, source_path, records_for_payload, sha, reject_links

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true', help='Check source-to-payload equality without rebuilding')
args = parser.parse_args()
entries = read_json(ROOT / 'publish-files.json')
outputs = [entry['deployed'] for entry in entries]
if len(set(value.casefold() for value in outputs)) != len(outputs):
    raise ValueError('Duplicate publication output')
if 'staticwebapp.config.json' in outputs:
    raise ValueError('Routing configuration is supplied separately')
sources = [(source_path(entry), public_relative(entry['deployed'])) for entry in entries]
config = ROOT / 'site-config' / 'staticwebapp.config.json'
read_json(config)
sources.append((config, Path('staticwebapp.config.json')))

if args.check:
    mismatches = [str(relative) for source, relative in sources
                  if not (WEBSITE / relative).is_file() or sha(source) != sha(WEBSITE / relative)]
    print(json.dumps({'approved_files':len(sources), 'source_mismatches':mismatches}, indent=2))
    raise SystemExit(bool(mismatches))

lock = ROOT / 'deployment.lock'
with lock.open('x', encoding='utf-8') as stream:
    stream.write(json.dumps({'pid':os.getpid(), 'operation':'prepare'}))
try:
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    draft = Path(tempfile.mkdtemp(prefix='.preparing-', dir=ROOT))
    for source, relative in sources:
        target = draft / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    manifest = records_for_payload(draft)
    if len(manifest) > 15000 or sum(item['bytes'] for item in manifest) > 250 * 1024 * 1024:
        raise ValueError('Prepared website exceeds the configured Azure Free deployment limit')
    backup = ROOT / 'backups' / ('website-' + stamp)
    backup.parent.mkdir(exist_ok=True)
    reject_links(backup, ROOT)
    old_manifest = ROOT / 'payload-manifest.json'
    saved_manifest = backup.parent / (backup.name + '-manifest.json')
    temporary = ROOT / ('.payload-manifest-' + stamp + '.json')
    temporary.write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    if old_manifest.exists():
        shutil.copy2(old_manifest, saved_manifest)
    previous_exists = WEBSITE.exists()
    installed_new = False
    if previous_exists:
        reject_links(WEBSITE, ROOT)
    try:
        if previous_exists:
            WEBSITE.rename(backup)
        draft.rename(WEBSITE)
        installed_new = True
        temporary.replace(old_manifest)
    except Exception:
        # Keep the failed new build for inspection, and restore the old pair.
        if installed_new:
            WEBSITE.rename(ROOT / ('.failed-website-' + stamp))
        if backup.exists():
            backup.rename(WEBSITE)
        if saved_manifest.exists():
            shutil.copy2(saved_manifest, old_manifest)
        raise
    print(json.dumps({'website':str(WEBSITE),'files':len(manifest),'previous_payload_backup':str(backup)},indent=2))
finally:
    lock.unlink()
