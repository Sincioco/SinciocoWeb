"""Build the video-free public storyboard copy; original authoring files are read-only."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote, quote
import argparse, hashlib, html, json, re, sys
from update_bookone import guard_root, safe_file, inventory, replace_docs, acquire_lock, msvcrt

HERE=Path(__file__).resolve().parent
SOURCE=Path(r'D:\SMILE 2.0 - Sin Star I\Visual Script and Storyboard')
REPOSITORY=Path(r'D:\My Documents - 2026\SinStar_Storyboard')
STATE=Path(r'D:\My Documents - 2026\Sincioco.com\Deployment\storyboard-publication')
BASE='https://sincioco.github.io/SinStar_Storyboard/'
GENERATED={'.nojekyll','sitemap.xml','review.html','asset/public-pages.css','asset/public-clips.js'}
def approved():return set(json.loads((HERE/'storyboard-public-inputs.json').read_text(encoding='utf-8')))|GENERATED

class Scan(HTMLParser):
    def __init__(self):super().__init__();self.refs=[];self.ids=set();self.cues=set()
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if a.get('id'):self.ids.add(a['id'])
        for key in ('href','src','poster'):
            if a.get(key):self.refs.append((tag,key,a[key]))

def validate(payload):
    if set(payload)!=approved():raise ValueError('Files differ from the storyboard public allowlist.')
    scans={}
    for name,data in payload.items():
        if name.endswith(('.mp4','.mov','.webm','.avi','.mkv')) or 'production/' in name or name.startswith('.') and name!='.nojekyll':
            raise ValueError('Private/video file in public payload: '+name)
        if len(data)>=100*1024*1024:raise ValueError('GitHub file size exceeded: '+name)
        if name.endswith('.html'):
            s=Scan();s.feed(data.decode('utf-8'));scans[name]=s
    for name,s in scans.items():
        for tag,key,ref in s.refs:
            url=urlsplit(ref)
            if url.scheme or url.netloc:continue
            target=unquote(url.path) or name
            if target not in payload:raise ValueError('Missing public dependency '+name+' -> '+target)
            if url.fragment and target in scans and unquote(url.fragment) not in scans[target].ids:
                raise ValueError('Missing public anchor '+name+' -> '+target+'#'+url.fragment)
    total=sum(map(len,payload.values()))
    if total>=1_000_000_000:raise ValueError('Pages size limit exceeded.')
    return {'files':len(payload),'bytes':total,'html_pages':len(scans),'video_binaries':0}

def metadata(page,name):
    canonical=BASE+('' if name=='index.html' else quote(name))
    page=re.sub(r'<link\b[^>]*rel=["\']canonical["\'][^>]*>','',page,flags=re.I)
    extra=f'<link rel="canonical" href="{canonical}"><meta name="referrer" content="strict-origin-when-cross-origin"><link rel="stylesheet" href="asset/public-pages.css">'
    return page.replace('</head>',extra+'</head>',1)

def public_films(page,records):
    by_file={r['file']:r for r in records if r.get('status')=='uploaded' and re.fullmatch(r'[\w-]{11}',r.get('youtube_id',''))}
    def video(match):
        text=match.group(); found=re.search(r'<source[^>]+src="([^"]+)"',text)
        filename=unquote(urlsplit(html.unescape(found[1])).path) if found else ''
        if filename not in by_file:raise ValueError('Film has no verified YouTube mapping: '+filename)
        record=by_file[filename]; label=re.search(r'aria-label="([^"]+)"',text)
        title=label[1] if label else html.escape(record['title'],quote=True);yt=record['youtube_id']
        return f'<iframe src="https://www.youtube-nocookie.com/embed/{yt}?playsinline=1&amp;rel=0" title="{title}" loading="lazy" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe><p class="movie-links"><a href="https://youtu.be/{yt}" target="_blank" rel="noopener">Watch on YouTube</a></p>'
    page,count=re.subn(r'<video\b.*?</video>',video,page,flags=re.S)
    if count!=5:raise ValueError('Review changed film structure before publishing.')
    page=re.sub(r'<a\b[^>]*href="(?:asset/videos/|production/)[^"]*"[^>]*>.*?</a>','',page,flags=re.S)
    return page.replace('Play Live Sequence','Browse Video Clips')

def clip_page(movie_source,records):
    head=movie_source.split('<body',1)[0]
    head=re.sub(r'<title>.*?</title>','<title>Sin Star I - Video Clips</title>',head,flags=re.S)
    head=re.sub(r'<meta name="description"[^>]+>','<meta name="description" content="Watch the published Sin Star I storyboard clips and explore the illustrated story.">',head)
    header=re.search(r'<header\b.*?</header>',movie_source,re.S)[0]
    header=header.replace('data-view="clips" href="review.html"','data-view="clips" aria-current="page" href="review.html"')
    clips=[r for r in records if '/hover/' in r.get('file','')]
    rows=[]
    for record in clips:
        title=record['title'].replace('Sin Star I - Prologue - Room for One - ','').replace('Sin Star I - ','')
        text=html.escape(title);ident=html.escape(record['id'],quote=True);yt=record.get('youtube_id','')
        if record.get('status')=='uploaded' and re.fullmatch(r'[\w-]{11}',yt):
            rows.append(f'<li><button type="button" id="{ident}" data-youtube="{yt}" data-title="{html.escape(title,quote=True)}" aria-current="false">{text}</button></li>')
        else:rows.append(f'<li><button type="button" disabled>{text}<small>Not published yet</small></button></li>')
    body='<body data-view="clips"><a class="skip" href="#clip-browser">Skip to video clips</a>'+header
    body+='<main id="clip-browser" class="clip-browser"><section class="clip-player" aria-label="Selected clip"><div id="clip-screen"><img src="asset/images/sin-star-poster.png" alt="Sin Star I poster"></div><h1 id="clip-title">Video Clips</h1><p>Choose a clip to watch. If playback does not start automatically, press Play in the video.</p><p class="clip-links"><a id="clip-direct" target="_blank" rel="noopener" hidden>Watch on YouTube</a><a href="movies.html">Watch the complete films</a></p><p>Created by Louiery R. Sincioco (Sin).</p></section><section class="clip-picker" aria-label="Choose a storyboard clip"><label for="clip-search">Find a clip</label><input type="search" id="clip-search" placeholder="Scene, character or title"><p id="clip-count" aria-live="polite">'+str(len(clips))+' clips; unpublished takes are marked below.</p><ul class="clip-list">'+''.join(rows)+'</ul></section></main><script src="asset/site-shell.js"></script><script src="asset/public-clips.js"></script></body></html>'
    return head+body

def prepare():
    names=json.loads((HERE/'storyboard-public-inputs.json').read_text(encoding='utf-8'))
    if len(names)!=len(set(n.casefold() for n in names)):raise ValueError('Duplicate source path.')
    payload={n:safe_file(SOURCE,n).read_bytes() for n in names}
    records=json.loads(safe_file(SOURCE,'production/youtube-uploads.json').read_text(encoding='utf-8'))
    mapped={r['id']:r['youtube_id'] for r in records if r.get('status')=='uploaded' and re.fullmatch(r'[\w-]{11}',r.get('youtube_id',''))}
    # Only verified publication fields leave the private registry.
    payload['asset/youtube-uploads.js']=('/* Verified public video IDs. */\nwindow.SinStarUploads = Object.freeze('+json.dumps(mapped,indent=2)+');\n').encode()
    player=payload['asset/animated-pictures.js'].decode('utf-8')
    old="async function start(item, explicit = false, provider = 'local')"
    if player.count(old)!=1:raise ValueError('Review changed preview owner before publication.')
    payload['asset/animated-pictures.js']=player.replace(old,old.replace("'local'","'youtube'")).encode()
    movie_source=payload['movies.html'].decode('utf-8')
    payload['movies.html']=public_films(movie_source,records).encode()
    payload['review.html']=clip_page(movie_source,records).encode()
    index=payload['index.html'].decode('utf-8')
    index=re.sub(r'<li><a href="Storyboard-Draft-1/[^\n]+?</li>','',index)
    payload['index.html']=index.encode()
    for name in ('index.html','Sin-Star-I-Game-Script-v0.2.html'):
        page=payload[name].decode('utf-8')
        def pending(match):
            text=match.group();ident=re.search(r'data-clip="([^"]+)"',text)[1]
            return text if ident in mapped else text.replace('<button','<button disabled',1).replace('</button>',' (not published yet)</button>')
        page=re.sub(r'<button\b[^>]*data-clip="[^"]+"[^>]*>.*?</button>',pending,page,flags=re.S)
        payload[name]=page.encode()
    payload['asset/public-pages.css']=(HERE/'storyboard-pages.css').read_bytes()
    payload['asset/public-clips.js']=(HERE/'storyboard-clips.js').read_bytes()
    for name in list(payload):
        if name.endswith('.html'):
            page=metadata(payload[name].decode('utf-8'),name)
            def version(match):
                path=match[1]
                return path+'?v='+hashlib.sha256(payload[path]).hexdigest()[:10]
            page=re.sub(r'(asset/[\w.-]+\.(?:js|css))(?:\?v=[a-f0-9]+)?',version,page)
            payload[name]=page.encode()
    payload['.nojekyll']=b''
    payload['sitemap.xml']=('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+''.join('<url><loc>'+BASE+('' if n=='index.html' else n)+'</loc></url>' for n in payload if n.endswith('.html'))+'</urlset>\n').encode()
    summary=validate(payload);summary.update({'verified_youtube_mappings':len(mapped),'pending_video_ids':[r['id'] for r in records if r['id'] not in mapped]})
    return payload,summary

def main():
    parser=argparse.ArgumentParser(description=__doc__);mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--dry-run',action='store_true');mode.add_argument('--check',action='store_true');mode.add_argument('--restore')
    args=parser.parse_args();lock=None
    try:
        for root in (SOURCE,REPOSITORY,STATE):guard_root(root)
        if not args.dry_run and not args.check:lock=acquire_lock(STATE)
        if args.restore:
            if not re.fullmatch(r'\d{8}T\d{12}Z',args.restore):raise ValueError('Use the exact recovery ID.')
            old=STATE/args.restore/'previous';payload={n:safe_file(old,n).read_bytes() for n in inventory(old)};summary=validate(payload)
        else:
            if not args.dry_run and not args.check and not (REPOSITORY/'docs').exists():
                previous=sorted(p.parent.name for p in STATE.glob('*/previous') if p.is_dir())
                if previous:raise ValueError('Interrupted copy; recover with -Restore '+previous[-1])
            payload,summary=prepare()
        have=inventory(REPOSITORY/'docs');want={n:hashlib.sha256(v).hexdigest() for n,v in payload.items()}
        summary.update({'canonical':BASE,'repository':str(REPOSITORY),'changes':{'add':sorted(want.keys()-have.keys()),'change':[n for n in want if n in have and want[n]!=have[n]],'remove':sorted(have.keys()-want.keys())}})
        if args.check:
            if have!=want:raise ValueError('Public docs differ from source; run -DryRun then update.')
        elif not args.dry_run:summary['recovery']=replace_docs(payload,REPOSITORY,STATE,SOURCE)
        print(json.dumps(summary,indent=2))
    finally:
        if lock:lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1);lock.close()

if __name__=='__main__':
    try:main()
    except Exception as error:print('Storyboard publication stopped: '+str(error),file=sys.stderr);sys.exit(1)
