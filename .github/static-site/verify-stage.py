"""Verify the complete Azure wrapper package against its approved sources.

External redirects are checked as URLs, never interpreted as local paths. The
private migration contract preserves the complete historical reader URL set.
"""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote
import json
import subprocess
import sys
import posixpath
import xml.etree.ElementTree as ET

from deployment_lib import ROOT, WEBSITE, read_json, public_relative, source_path, records_for_payload, sha

root = WEBSITE
config = read_json(root / 'staticwebapp.config.json')
manifest = read_json(ROOT / 'payload-manifest.json')
entries = read_json(ROOT / 'publish-files.json')
contract = read_json(ROOT / 'pages-migration-contract.json')
failures = []

def fail(error, **details):
    failures.append({'error': error, **details})

def normalized_route(route):
    path = route.rstrip('/')
    if path.endswith('/index.html'):
        path = path[:-len('/index.html')]
    return path or '/'

rules = {}
normalized = {}
for rule in config['routes']:
    path = rule['route']
    key = normalized_route(path)
    if path in rules:
        fail('duplicate route', route=path)
    if key in normalized:
        fail('normalized route duplicate', route=path, other=normalized[key])
    rules[path] = rule
    normalized[key] = path
    target = rule.get('redirect', rule.get('rewrite'))
    directory_slash_redirect = (rule.get('statusCode') == 301 and
        rule.get('redirect') == path + '/' and not path.endswith('/') and
        (root / path.lstrip('/') / 'index.html').is_file())
    if target and target.startswith('/') and normalized_route(target) == key and not directory_slash_redirect:
        fail('normalized redirect loop', route=path)
    if target and urlsplit(target).scheme:
        parsed = urlsplit(target)
        if parsed.scheme != 'https' or parsed.username or parsed.password:
            fail('external route must use HTTPS without user information', route=path)

if (root / 'staticwebapp.config.json').stat().st_size > 20 * 1024:
    fail('configuration exceeds Azure 20 KB limit')
if 'navigationFallback' in config or any('*' in path for path in rules):
    fail('The reviewed static site must not add catch-all or wildcard routing')
actual = records_for_payload(root)
if actual != manifest:
    fail('Payload file inventory/hashes differ from the approved manifest')
expected_paths = {entry['deployed'] for entry in entries} | {'staticwebapp.config.json'}
if {item['path'] for item in actual} != expected_paths:
    fail('Payload differs from the explicit public-file allowlist')
if len({entry['deployed'].casefold() for entry in entries}) != len(entries):
    fail('Duplicate publication outputs')
if any(entry['source'] != 'main' for entry in entries):
    fail('Migrated Azure payload must use only approved main-site sources')
for entry in entries:
    relative = public_relative(entry['deployed'])
    source = source_path(entry)
    if not (root / relative).is_file() or sha(source) != sha(root / relative):
        fail('Prepared file differs from its approved source', file=entry['deployed'])
if sha(ROOT / 'site-config/staticwebapp.config.json') != sha(root / 'staticwebapp.config.json'):
    fail('Routing configuration differs from the approved copy')

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.anchors = []
        self.iframes = []
        self.canonicals = []
        self.robots = []
        self.scripts = []
        self.html = {}

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if tag == 'html':
            self.html = attrs
        if tag == 'script':
            self.scripts.append(attrs)
        for key in ('href', 'src', 'poster'):
            if attrs.get(key):
                self.links.append(attrs[key])
        if tag == 'a':
            self.anchors.append(attrs)
        if tag == 'iframe':
            self.iframes.append(attrs)
        if tag == 'link' and 'canonical' in attrs.get('rel', '').split():
            self.canonicals.append(attrs.get('href'))
        if tag == 'meta' and attrs.get('name', '').lower() == 'robots':
            self.robots.append(attrs.get('content', '').lower())

def resolve_local_link(path):
    """Return ('file', Path), ('external', URL), or ('error', explanation)."""
    visited = set()
    for _ in range(16):
        if path in visited:
            return 'error', 'Route loop at ' + path
        visited.add(path)
        rule = rules.get(path)
        if rule is None:
            index_route = path.rstrip('/') + '/index.html'
            rule = rules.get(index_route)
        target = rule.get('redirect', rule.get('rewrite')) if rule else None
        if target:
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc:
                if parsed.scheme == 'https' and parsed.hostname and not parsed.username and not parsed.password:
                    return 'external', target
                return 'error', 'Unsafe external target: ' + target
            path = posixpath.normpath(unquote(parsed.path))
            if not path.startswith('/'):
                path = '/' + path
            if parsed.path.endswith('/') and path != '/':
                path += '/'
            continue
        candidate = root / path.lstrip('/')
        if candidate.is_dir():
            candidate = candidate / 'index.html'
        elif not path.endswith('/') and not candidate.is_file() and not candidate.suffix:
            candidate = candidate.with_suffix('.html')
        return 'file', candidate
    return 'error', 'Route depth exceeded'

checked = 0
external_resolutions = 0
for page in root.rglob('*.html'):
    parser = Page()
    parser.feed(page.read_text(encoding='utf-8-sig'))
    for link in parser.links:
        url = urlsplit(link)
        if url.scheme or url.netloc or not url.path:
            continue
        raw = unquote(url.path)
        base = '/' + page.relative_to(root).parent.as_posix().rstrip('.') + '/'
        path = posixpath.normpath(raw if raw.startswith('/') else base + raw)
        path = '/' + path.lstrip('/')
        if raw.endswith('/') and path != '/':
            path += '/'
        checked += 1
        kind, resolved = resolve_local_link(path)
        if kind == 'external':
            external_resolutions += 1
        elif kind == 'error' or not resolved.is_file():
            fail('Broken local link/route', file=page.relative_to(root).as_posix(), link=link, resolved=str(resolved))

book_pages = contract['book_pages_url']
storyboard_pages = contract['storyboard_pages_url']
if book_pages != 'https://sincioco.github.io/SinStar_Audio_BookOne/' or storyboard_pages != 'https://sincioco.github.io/SinStar_Storyboard/':
    fail('Unexpected Pages deployment destinations in migration contract')
book_wrapper_url = 'https://sincioco.com/SinStar/BookOne/'
if contract.get('book_wrapper_url') != book_wrapper_url:
    fail('Book wrapper must use its exact main-host nested URL')
if contract.get('azure_origins') != ['https://sincioco.com', 'https://www.sincioco.com']:
    fail('Azure origin contract must contain only the apex and www hosts')
expected_wrappers = [
    {'path': 'SinStar/BookOne/index.html', 'source': 'BookOne/index.html', 'canonical': book_pages},
    {'path': 'BookOne/index.html', 'canonical': book_pages},
    {'path': 'SinStar_Storyboard/index.html', 'canonical': storyboard_pages},
]
if sorted(contract['wrappers'], key=lambda item: item['path']) != sorted(expected_wrappers, key=lambda item: item['path']):
    fail('Wrapper contract must retain one book source, its exact alias, and the storyboard')
book_alias_rule = {'route': '/SinStar/BookOne/index.html', 'rewrite': '/BookOne/index.html'}
if rules.get(book_alias_rule['route']) != book_alias_rule:
    fail('Nested book URL must use only its exact reviewed index rewrite')
for wrapper_path in ('BookOne/index.html', 'SinStar_Storyboard/index.html'):
    if normalized_route('/' + wrapper_path) in normalized:
        fail('Wrapper URLs must remain direct files with native auto normalization', file=wrapper_path)
landing_rule = rules.get('/sinstar/novel/index.html', {})
if landing_rule.get('statusCode') != 301 or landing_rule.get('redirect') != book_wrapper_url or 'rewrite' in landing_rule:
    fail('Legacy novel landing must permanently redirect to the main-host book wrapper')
historical_assets = contract['retired_reader_assets']
if len(historical_assets) != 62 or len(set(historical_assets)) != 62 or sum(path.startswith('audio/') for path in historical_assets) != 43:
    fail('Historical reader asset contract must retain 62 paths including 43 audio files')
expected_asset_routes = set()
for asset in historical_assets:
    public_relative(asset)
    for prefix in ('/BookOne/', '/sinstar/novel/'):
        route = prefix + asset
        expected_asset_routes.add(route)
        rule = rules.get(route, {})
        if rule.get('statusCode') != 301 or rule.get('redirect') != book_pages + asset or 'rewrite' in rule:
            fail('Missing or changed historical reader asset redirect', route=route)
actual_asset_routes = {path for path, rule in rules.items() if
                       (path.startswith('/BookOne/') or path.startswith('/sinstar/novel/'))
                       and rule.get('redirect', '').startswith(book_pages)}
if actual_asset_routes != expected_asset_routes:
    fail('Reader asset redirect inventory differs from the historical contract')
if contract['retirement_worker_paths'] != ['/BookOne/sw.js', '/sinstar/novel/sw.js']:
    fail('Historical retirement worker URLs must remain unchanged')
for worker_path in contract['retirement_worker_paths']:
    rule = rules.get(worker_path, {})
    if not (root / worker_path.lstrip('/')).is_file() or 'redirect' in rule or 'rewrite' in rule:
        fail('Retirement worker must remain a direct same-origin file', route=worker_path)
    if rule.get('headers', {}).get('Cache-Control') != 'no-cache, no-store, must-revalidate':
        fail('Retirement worker must revalidate', route=worker_path)
if (root / 'BookOne/sw.js').is_file() and (root / 'sinstar/novel/sw.js').is_file():
    if sha(root / 'BookOne/sw.js') != sha(root / 'sinstar/novel/sw.js'):
        fail('Two retirement worker copies differ')
expected_book_files = {'BookOne/index.html', 'BookOne/sw.js', 'BookOne/retire-legacy-workers.js'}
actual_book_files = {item['path'] for item in actual if item['path'].startswith('BookOne/')}
if actual_book_files != expected_book_files:
    fail('Azure BookOne contains files other than the three approved wrapper/retirement files')
if any(item['path'].startswith('SinStar/') or item['path'].casefold().startswith('sinstar/bookone/') for item in actual):
    fail('Nested book URL must remain virtual without a physical SinStar payload tree')
book_source = 'BookOne/index.html'
book_outputs = {book_source, 'SinStar/BookOne/index.html'}
book_entries = [entry for entry in entries if entry['deployed'] in book_outputs or entry['path'] in book_outputs]
if book_entries != [{'source': 'main', 'path': book_source, 'deployed': book_source}]:
    fail('Book wrapper must retain its single original publication entry')
if any(item['path'].startswith('sinstar/novel/') and item['path'] != 'sinstar/novel/sw.js' for item in actual):
    fail('Legacy novel payload contains content other than its retirement worker')

for wrapper in contract['wrappers']:
    path = root / public_relative(wrapper.get('source', wrapper['path']))
    if not path.is_file():
        fail('Missing wrapper', file=wrapper['path'])
        continue
    page = Page()
    page.feed(path.read_text(encoding='utf-8-sig'))
    if page.canonicals != [wrapper['canonical']]:
        fail('Wrapper canonical differs from Pages', file=wrapper['path'])
    if len(page.iframes) != 1 or page.iframes[0].get('src') != wrapper['canonical'] or not page.iframes[0].get('title'):
        fail('Wrapper must embed the exact Pages URL with a frame title', file=wrapper['path'])
    frame = page.iframes[0] if len(page.iframes) == 1 else {}
    if frame.get('referrerpolicy') != 'strict-origin-when-cross-origin':
        fail('Wrapper iframe must declare the approved referrer policy', file=wrapper['path'])
    if frame.get('id') != 'hosted-content' or 'sandbox' in frame:
        fail('Wrapper iframe identity or sandbox differs from the approved contract', file=wrapper['path'])
    kind = 'book' if wrapper['canonical'] == book_pages else 'storyboard'
    if page.html.get('data-hosted-page') != kind or not any(script.get('src') == '/wrapper-nav.js' and 'defer' in script for script in page.scripts):
        fail('Wrapper must include its fixed-target bookmark navigation', file=wrapper['path'])
    if kind == 'storyboard' and 'encrypted-media' not in [item.strip().split(' ')[0] for item in frame.get('allow', '').split(';')]:
        fail('Storyboard iframe must delegate encrypted-media', file=wrapper['path'])
    if not any(anchor.get('href') == wrapper['canonical'] and anchor.get('id') == 'open-hosted-content' for anchor in page.anchors):
        fail('Wrapper lacks a direct full-page link', file=wrapper['path'])
    if len(page.robots) != 1 or 'noindex' not in page.robots[0] or 'nofollow' in page.robots[0]:
        fail('Wrapper must be noindex while permitting followed links', file=wrapper['path'])

sitemap_route = rules.get('/sitemap-sinstar.xml', {})
if sitemap_route.get('statusCode') != 301 or sitemap_route.get('redirect') != book_pages + 'sitemap.xml':
    fail('Old reader sitemap URL must permanently redirect to Pages sitemap')
if 'sitemap-sinstar.xml' in expected_paths:
    fail('Retired Azure reader sitemap is still in the publication allowlist')
locations = [node.text or '' for node in ET.parse(root / 'sitemap.xml').findall('.//{*}loc')]
# Native auto supplies folder slashes and extensionless final HTML URLs.
if config.get('trailingSlash') != 'auto':
    fail('Azure native trailingSlash:auto is required for final canonical URLs')
for folder in ('/AgenticAI', '/Military', '/Resume', '/smile2'):
    if folder in rules:
        fail('Bare-folder routes must use native auto normalization', route=folder)
if len(locations) != 21 or len(set(locations)) != 21:
    fail('Main sitemap must contain 21 unique canonical pages')
canonical_files_checked = 0
canonical_file_paths = set()
for location in locations:
    parsed = urlsplit(location)
    if parsed.scheme != 'https' or parsed.netloc != 'sincioco.com' or parsed.query or parsed.fragment:
        fail('Main canonical URL must use the exact HTTPS main origin', url=location)
        continue
    path = unquote(parsed.path)
    if not path.endswith('/') and Path(path).suffix:
        fail('Main canonical page URLs must be extensionless', url=location)
        continue
    kind, resolved = resolve_local_link(path)
    if kind != 'file' or resolved.suffix != '.html' or not resolved.is_file():
        fail('Main canonical URL has no prepared HTML file', url=location)
        continue
    if not path.endswith('/') and (root / path.lstrip('/')).is_dir():
        fail('Main canonical folders must include a trailing slash', url=location)
        continue
    if resolved in canonical_file_paths:
        fail('Main canonical URLs must resolve to distinct HTML files', url=location)
    canonical_file_paths.add(resolved)
    page = Page()
    page.feed(resolved.read_text(encoding='utf-8-sig'))
    if page.canonicals != [location]:
        fail('Main page canonical does not match its native final URL', url=location)
    canonical_files_checked += 1
if any(not url.startswith('https://sincioco.com/') for url in locations):
    fail('Main sitemap must retain its original main-host canonical URLs')
if any('/BookOne' in url or '/SinStar_Storyboard' in url for url in locations):
    fail('Noindex wrappers must not enter the main canonical sitemap')
robots = (root / 'robots.txt').read_text(encoding='utf-8-sig')
robot_maps = [line.split(':', 1)[1].strip() for line in robots.splitlines() if line.lower().startswith('sitemap:')]
if robot_maps != ['https://sincioco.com/sitemap.xml']:
    fail('Azure robots must declare only the main canonical sitemap')

# Dedicated responsive-image validation covers every srcset URL and immutable PNG.
main_source_root = (ROOT / read_json(ROOT / 'sources.json')['main']).resolve()
thumbnail_command = [sys.executable, '-B', str(main_source_root / 'AgenticAI/tools/check-card-thumbnails.py'),
                     '--site-root', str(main_source_root), '--payload-root', str(root)]
if ROOT.name.casefold() == 'deployment':
    thumbnail_command.append('--require-private')
thumbnail_result = subprocess.run(thumbnail_command, capture_output=True, text=True, encoding='utf-8', timeout=60)
thumbnail_summary = None
if thumbnail_result.returncode:
    fail('Responsive card thumbnail validation failed', details=thumbnail_result.stderr.strip())
else:
    thumbnail_summary = json.loads(thumbnail_result.stdout)

summary = {'files':len(actual), 'bytes':sum(item['bytes'] for item in actual),
           'copied_files_hash_verified':len(manifest), 'html_links_checked':checked,
           'external_redirect_links_resolved':external_resolutions,
           'routes':len(rules), 'reader_asset_redirects':len(expected_asset_routes),
           'main_canonical_pages':len(locations), 'canonical_html_files_checked':canonical_files_checked, 'wrappers':len(contract['wrappers']),
           'responsive_card_thumbnails':thumbnail_summary, 'novel_source_entries':sum(entry['source']=='novel' for entry in entries), 'failures':failures}
if len(actual) > 15000 or summary['bytes'] > 250 * 1024 * 1024:
    fail('deployment exceeds Azure Free quota')
diagnostics = ROOT / 'diagnostics'
diagnostics.mkdir(exist_ok=True)
(diagnostics / 'staging-validation.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
print(json.dumps(summary, indent=2))
raise SystemExit(bool(failures))
