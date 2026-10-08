"""Bounded local publication copy. This module never invokes Git or a network API."""
from pathlib import Path, PurePosixPath
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote
import argparse, datetime, hashlib, json, os, re, sys, msvcrt

HERE = Path(__file__).resolve().parent
SOURCE = Path(r'D:\SMILE 2.0 - Sin Star I\Book and Novel Materials\Sin Star I - Novel\web')
REPOSITORY = Path(r'D:\My Documents - 2026\SinStar_Audio_BookOne')
STATE = Path(r'D:\My Documents - 2026\Sincioco.com\Deployment\book-publication')
CANONICAL = 'https://sincioco.github.io/SinStar_Audio_BookOne/'
OLD_CANONICAL = 'https://sinstar.sincioco.com/BookOne/'

def digest(data):
    return hashlib.sha256(data).hexdigest()

def guard_root(root):
    root=root.absolute()
    for item in [root,*root.parents]:
        if item.is_symlink() or (hasattr(item,'is_junction') and item.is_junction()):
            raise ValueError('Publication root/ancestor is a link: '+str(item))
    return root.resolve()

def safe_file(root, name):
    rel = PurePosixPath(name)
    if rel.is_absolute() or '..' in rel.parts or '\\' in name or ':' in name:
        raise ValueError('Unsafe publication path: ' + name)
    root = guard_root(root); target = root.joinpath(*rel.parts)
    if not target.resolve().is_relative_to(root):
        raise ValueError('Path escapes publication root: ' + name)
    for item in [target, *target.parents]:
        if item.is_symlink() or (hasattr(item, 'is_junction') and item.is_junction()):
            raise ValueError('Links/junctions are not publication inputs: ' + str(item))
        if item == root: break
    return target

class ReaderHTML(HTMLParser):
    def __init__(self):
        super().__init__(); self.ids=set(); self.cues=set(); self.refs=[]; self.follow=False
    def handle_starttag(self, tag, attrs):
        a=dict(attrs)
        if a.get('id'): self.ids.add(a['id'])
        if a.get('data-cue-id'): self.cues.add(a['data-cue-id'])
        if a.get('id')=='follow': self.follow='checked' in a and a.get('autocomplete')=='off'
        for key in ('src','href'):
            if a.get(key): self.refs.append(a[key])

def validate(payload):
    approved=set(json.loads((HERE/'bookone-public-files.json').read_text(encoding='utf-8')))|{'.nojekyll','sitemap.xml'}
    if set(payload)!=approved: raise ValueError('Public files differ from the explicit allowlist.')
    book=json.loads(payload['book.json']); page=ReaderHTML(); page.feed(payload['index.html'].decode('utf-8'))
    if len(book['chapters']) != 43 or not page.follow:
        raise ValueError('Chapter count or default Follow behavior changed; review before publication.')
    total=0; cue_count=0
    for chapter in book['chapters']:
        name=chapter['audio']; audio=payload[name]
        if len(audio)!=chapter['bytes'] or digest(audio)!=chapter['sha256']:
            raise ValueError('Audio bytes/hash mismatch: '+name)
        if chapter['id'] not in page.ids: raise ValueError('Missing chapter anchor: '+chapter['id'])
        for cue in chapter['cues']:
            cue_id=cue.get('id') or cue.get('target')
            if cue_id not in page.cues and cue_id not in page.ids:
                raise ValueError('Missing cue target: '+str(cue_id))
            cue_count+=1
        total+=len(audio)
    if total!=book['totalBytes']: raise ValueError('Book total audio size mismatch.')
    for ref in page.refs:
        url=urlsplit(ref)
        if url.scheme or url.netloc: continue
        name=unquote(url.path).removeprefix('./')
        if name and name not in payload: raise ValueError('Missing HTML asset: '+name)
        if not name and url.fragment and unquote(url.fragment) not in page.ids:
            raise ValueError('Missing anchor: '+url.fragment)
    for name in json.loads(payload['storyboards.json'])['images']:
        if name not in payload: raise ValueError('Missing illustration: '+name)
    music=json.loads(payload['music.json'])['tracks']
    if [track['file'] for track in music] != ['music/starforge-horizon.mp3','music/starforge-march.mp3','music/bloom.mp3']:
        raise ValueError('Unexpected background music playlist order.')
    for track in music:
        data=payload[track['file']]
        if len(data)!=track['bytes'] or digest(data)!=track['sha256']:
            raise ValueError('Music bytes/hash mismatch: '+track['file'])
    if sum(map(len,payload.values()))>=1_000_000_000 or any(len(v)>=100*1024*1024 for v in payload.values()):
        raise ValueError('GitHub Pages/file size budget exceeded.')
    for name,data in payload.items():
        if PurePosixPath(name).suffix not in ('.html','.css','.js','.json','.webmanifest','.svg','.webp','.mp3','.xml',''):
            raise ValueError('Unapproved public file type: '+name)
    return {'files':len(payload),'bytes':sum(map(len,payload.values())),'audio_bytes':total,'chapters':43,'cues':cue_count}

def expected():
    names=json.loads((HERE/'bookone-public-files.json').read_text(encoding='utf-8'))
    if len(names)!=len(set(n.casefold() for n in names)): raise ValueError('Duplicate allowlist path.')
    payload={name:safe_file(SOURCE,name).read_bytes() for name in names}
    # Only host-specific discovery metadata changes; narrative, runtime and audio are copied verbatim.
    payload['index.html']=payload['index.html'].replace(OLD_CANONICAL.encode(),CANONICAL.encode())
    sw=payload['sw.js'].decode('utf-8')
    base,count=re.subn(r"const SHELL_VERSION\s*=\s*'[^']+';", "const SHELL_VERSION='__PUBLICATION__';",sw)
    if count!=1: raise ValueError('Unknown service worker version format.')
    revision=digest(base.encode()+b''.join(payload[n] for n in sorted(payload) if n!='sw.js' and not n.endswith('.mp3')))[:16]
    payload['sw.js']=base.replace('__PUBLICATION__',revision).encode()
    payload['.nojekyll']=b''
    payload['sitemap.xml']=('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>'+CANONICAL+'</loc></url></urlset>\n').encode()
    return payload,validate(payload)

def inventory(root):
    guard_root(root)
    if not root.exists(): return {}
    if root.is_symlink() or (hasattr(root,'is_junction') and root.is_junction()): raise ValueError('Destination is a link.')
    return {p.relative_to(root).as_posix():digest(safe_file(root,p.relative_to(root).as_posix()).read_bytes())
            for p in root.rglob('*') if p.is_file()}

def write_tree(root,payload):
    root.mkdir(parents=True,exist_ok=False)
    for name,data in payload.items():
        target=safe_file(root,name); target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(data)

def replace_docs(payload, repository=None, state_root=None, source_root=None):
    # Only the exact docs directory is moved; repository metadata and other root files are untouched.
    repo=guard_root(repository or REPOSITORY); state=guard_root(state_root or STATE); docs=repo/'docs'
    source=guard_root(source_root or SOURCE)
    repo.mkdir(parents=True,exist_ok=True); state.mkdir(parents=True,exist_ok=True)
    if repo.is_relative_to(source) or source.is_relative_to(repo): raise ValueError('Source/destination overlap.')
    if repo.is_symlink() or (hasattr(repo,'is_junction') and repo.is_junction()): raise ValueError('Repository is a link.')
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    run=state/stamp; run.mkdir(); draft=run/'prepared'; old=run/'previous'
    write_tree(draft,payload)
    if inventory(draft)!={n:digest(v) for n,v in payload.items()}: raise ValueError('Prepared copy verification failed.')
    receipt={'utc':stamp,'repository':str(repo),'files':{n:digest(v) for n,v in payload.items()},'previous':docs.exists(),'status':'prepared'}
    (run/'receipt.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
    if docs.exists(): docs.rename(old)
    try:
        draft.rename(docs)
        receipt['status']='completed'
        (run/'receipt.new.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
        os.replace(run/'receipt.new.json',run/'receipt.json')
    except BaseException:
        if docs.exists() and not draft.exists(): docs.rename(draft)
        if old.exists() and not docs.exists(): old.rename(docs)
        raise
    return str(run)

def acquire_lock(state_root=None):
    state=guard_root(state_root or STATE); state.mkdir(parents=True,exist_ok=True)
    stream=open(safe_file(state,'update.lock'),'a+b')
    if stream.tell()==0: stream.write(b'0'); stream.flush()
    stream.seek(0)
    try: msvcrt.locking(stream.fileno(),msvcrt.LK_NBLCK,1)
    except OSError:
        stream.close(); raise ValueError('Another publication update is running.')
    return stream

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group(); mode.add_argument('--dry-run',action='store_true'); mode.add_argument('--check',action='store_true'); mode.add_argument('--restore',metavar='BACKUP_ID')
    args=parser.parse_args()
    lock=None
    try:
        guard_root(SOURCE); guard_root(REPOSITORY); guard_root(STATE)
        if not args.dry_run and not args.check:
            lock=acquire_lock()
            if not args.restore and not (REPOSITORY/'docs').exists():
                interrupted=sorted(p.parent.name for p in STATE.glob('*/previous') if p.is_dir())
                if interrupted: raise ValueError('A prior swap was interrupted. Recover with -Restore '+interrupted[-1])
        if args.restore:
            if not re.fullmatch(r'\d{8}T\d{12}Z',args.restore): raise ValueError('Use the exact backup ID from an update receipt.')
            prior=STATE/args.restore/'previous'
            if not prior.is_dir(): raise ValueError('Recovery copy does not exist.')
            payload={name:safe_file(prior,name).read_bytes() for name in inventory(prior)}
            summary=validate(payload)
        else: payload,summary=expected()
        have=inventory(REPOSITORY/'docs'); want={n:digest(v) for n,v in payload.items()}
        changes={'add':[n for n in want if n not in have],'change':[n for n in want if n in have and have[n]!=want[n]],'remove':[n for n in have if n not in want]}
        summary.update({'canonical':CANONICAL,'repository':str(REPOSITORY),'changes':changes})
        if args.check:
            if have!=want: raise ValueError('Publication docs differ from current source. Run -DryRun, then update.')
            summary['mode']='check'
        elif args.dry_run: summary['mode']='dry-run'
        else:
            summary['recovery']=replace_docs(payload); summary['mode']='restored' if args.restore else 'updated'
        print(json.dumps(summary,indent=2))
    finally:
        if lock:
            lock.seek(0); msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1); lock.close()

if __name__=='__main__':
    try: main()
    except Exception as error: print('Publication stopped: '+str(error),file=sys.stderr); sys.exit(1)
