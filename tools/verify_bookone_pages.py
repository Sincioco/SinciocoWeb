"""Read-only HTTPS verification of the public Book One copy; never deploys or runs Git.

Reads only --expected (the public repository's docs folder). Writes only its JSON
report. No browser execution: worker registration, playback and iframe checks
are limited to source/HTTP evidence and are explicitly not interactive tests.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import ssl
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote, unquote, urljoin, urlsplit
from urllib.request import Request, build_opener, HTTPSHandler, HTTPRedirectHandler
import xml.etree.ElementTree as ET

DEFAULT_EXPECTED = Path(r'D:\My Documents - 2026\SinStar_Audio_BookOne\docs')
DEFAULT_URL = 'https://sincioco.github.io/SinStar_Audio_BookOne/'
PARENTS = ('https://sincioco.com', 'https://www.sincioco.com')
HEADERS = ('content-type', 'content-length', 'content-encoding', 'content-range',
           'accept-ranges', 'cache-control', 'etag', 'last-modified', 'age',
           'x-frame-options', 'content-security-policy', 'service-worker-allowed')


def sha(data):
    return hashlib.sha256(data).hexdigest()


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.cues, self.refs, self.canonicals, self.policies = set(), set(), [], [], []
        self.follow = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if a.get('id'):
            self.ids.add(a['id'])
        if a.get('data-cue-id'):
            self.cues.add(a['data-cue-id'])
        if a.get('id') == 'follow':
            self.follow = 'checked' in a and a.get('autocomplete') == 'off'
        if tag == 'link' and 'canonical' in a.get('rel', '').lower().split():
            self.canonicals.append(a.get('href'))
        if tag == 'meta' and a.get('http-equiv', '').lower() == 'content-security-policy':
            self.policies.append(a.get('content', ''))
        for key in ('href', 'src'):
            if a.get(key):
                self.refs.append(a[key])


def bounded_files(root):
    if not root.is_dir():
        raise ValueError(f'Expected public docs directory is missing: {root}')
    # Resolve only after rejecting links on the supplied root and its ancestors.
    for part in (root, *root.parents):
        if part.is_symlink() or part.is_junction():
            raise ValueError(f'Refusing linked public-copy path: {part}')
    resolved = root.resolve()
    result, stamps = {}, {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink() or path.is_junction():
            raise ValueError(f'Refusing linked publication entry: {path}')
        if not path.is_file():
            continue
        if not path.resolve().is_relative_to(resolved):
            raise ValueError(f'Publication entry escapes expected root: {path}')
        name = path.relative_to(root).as_posix()
        before = path.stat()
        data = path.read_bytes()
        after = path.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            raise ValueError(f'Public copy changed while being read: {name}')
        result[name] = data
        stamps[name] = (after.st_size, after.st_mtime_ns)
    return result, stamps


def local_checks(payload, base):
    errors = []
    page = Page()
    page.feed(payload['index.html'].decode('utf-8'))
    book = json.loads(payload['book.json'])
    manifest = json.loads(payload['manifest.webmanifest'])
    chapters = book['chapters']
    if len(payload) != 66:
        errors.append(f'Expected 66 public files, found {len(payload)}')
    if len(chapters) != 43:
        errors.append(f'Expected 43 audio entries, found {len(chapters)}')
    if page.canonicals != [base]:
        errors.append(f'Canonical must be exactly {base}: {page.canonicals}')
    if not page.follow:
        errors.append('Follow checkbox must be checked with autocomplete=off')
    audio_names, total, cues = [], 0, 0
    for chapter in chapters:
        name = chapter['audio']
        audio_names.append(name)
        data = payload.get(name)
        if data is None:
            errors.append(f'Manifest audio absent: {name}')
            continue
        total += len(data)
        if len(data) != chapter['bytes'] or sha(data) != chapter['sha256']:
            errors.append(f'Manifest audio hash/size mismatch: {name}')
        if chapter['id'] not in page.ids:
            errors.append(f'Missing chapter anchor: {chapter["id"]}')
        for cue in chapter.get('cues', []):
            cues += 1
            target = cue.get('id') or cue.get('target')
            if target not in page.cues and target not in page.ids:
                errors.append(f'Missing cue target: {target}')
            if not (0 <= cue['start'] <= cue['end']):
                errors.append(f'Invalid cue interval: {target}')
    if len(set(audio_names)) != 43:
        errors.append('The 43 audio entries must use distinct files')
    if set(audio_names) != {n for n in payload if n.endswith('.mp3')}:
        errors.append('MP3 file set differs from book manifest')
    if total != book['totalBytes']:
        errors.append('Manifest totalBytes differs from audio sum')
    for name in json.loads(payload['storyboards.json'])['images']:
        if name not in payload:
            errors.append(f'Missing illustration: {name}')
    for ref in page.refs:
        u = urlsplit(ref)
        if not u.scheme and not u.netloc and not u.path and u.fragment:
            if unquote(u.fragment) not in page.ids:
                errors.append(f'Missing fragment anchor: {ref}')
            continue
        absolute = urljoin(base, ref)
        if absolute.startswith(base):
            name = unquote(urlsplit(absolute).path[len(urlsplit(base).path):])
            if name and name not in payload:
                errors.append(f'Missing project-relative HTML asset: {ref}')
        elif not u.scheme and not u.netloc:
            errors.append(f'HTML local reference escapes project path: {ref}')
    for key in ('start_url', 'scope'):
        if urljoin(base, manifest[key]) != base:
            errors.append(f'Web manifest {key} does not resolve to project root')
    for icon in manifest.get('icons', []):
        if unquote(urlsplit(urljoin(base, icon['src'])).path[len(urlsplit(base).path):]) not in payload:
            errors.append(f'Missing manifest icon: {icon["src"]}')
    sitemap = ET.fromstring(payload['sitemap.xml'])
    locations = [el.text for el in sitemap.iter() if el.tag.endswith('}loc') or el.tag == 'loc']
    if locations != [base]:
        errors.append(f'Sitemap canonical mismatch: {locations}')
    scripts = '\n'.join(v.decode('utf-8') for n, v in payload.items() if n.endswith('.js') and n != 'sw.js')
    registration = re.search(r"serviceWorker\.register\(\s*(['\"])\./sw\.js\1\s*,\s*\{\s*scope\s*:\s*(['\"])\./\2\s*\}\s*\)", scripts)
    if not registration:
        errors.append('Expected project-relative ./sw.js registration with ./ scope was not found')
    worker = payload['sw.js'].decode('utf-8')
    version = re.search(r"const\s+SHELL_VERSION\s*=\s*['\"]([^'\"]+)['\"]", worker)
    if not re.search(r"new\s+URL\(\s*['\"]\./['\"]\s*,\s*self\.location\.href\s*\)", worker):
        errors.append('Worker ROOT is not based on its own project directory')
    return {'ok': not errors, 'errors': errors, 'files': len(payload),
            'bytes': sum(map(len, payload.values())), 'audio_files': len(audio_names),
            'audio_bytes': total, 'cues': cues, 'canonical': page.canonicals,
            'shell_version': version.group(1) if version else None,
            'worker_script_url': urljoin(base, './sw.js'), 'worker_requested_scope': base,
            'worker_scope_check': 'static registration/default-scope evidence; not browser execution',
            'meta_csp': page.policies}


class SameOriginRedirects(HTTPRedirectHandler):
    def __init__(self, base):
        self.base = urlsplit(base)

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        dest = urlsplit(newurl)
        if dest.scheme != 'https' or dest.netloc != self.base.netloc or not dest.path.startswith(self.base.path):
            raise HTTPError(newurl, code, 'Redirect leaves the expected HTTPS project', headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url, base, timeout, limit, extra=None):
    ctx = ssl.create_default_context()
    opener = build_opener(HTTPSHandler(context=ctx), SameOriginRedirects(base))
    headers = {'User-Agent': 'BookOne-Publication-Verifier/1.0',
               'Accept-Encoding': 'identity', 'Cache-Control': 'no-cache'}
    headers.update(extra or {})
    try:
        response = opener.open(Request(url, headers=headers), timeout=timeout)
    except HTTPError as exc:
        response = exc
    except (URLError, TimeoutError, OSError) as exc:
        return {'url': url, 'ok': False, 'error': f'{type(exc).__name__}: {exc}'}, b''
    with response:
        data = response.read(limit + 1)
        info = {'url': url, 'final_url': response.geturl(), 'status': response.code,
                'headers': {h: response.headers[h] for h in HEADERS if response.headers.get(h) is not None},
                'all_csp_headers': response.headers.get_all('content-security-policy', []),
                'received_bytes': len(data), 'sha256': sha(data),
                'https_certificate_verified': urlsplit(response.geturl()).scheme == 'https',
                'read_limit_exceeded': len(data) > limit}
    return info, data


def framing_check(headers, base, policies=None):
    errors = []
    xfo = headers.get('x-frame-options', '')
    if xfo:
        errors.append(f'X-Frame-Options present; cross-origin embedding requires review: {xfo}')
    policies = policies if policies is not None else [headers.get('content-security-policy', '')]
    for policy in policies:
        for segment in policy.split(';'):
            values = segment.strip().split()
            if not values or values[0].lower() != 'frame-ancestors':
                continue
            allowed = values[1:]
            for parent in PARENTS:
                host = urlsplit(parent).hostname
                accepted = '*' in allowed or 'https:' in allowed or parent in allowed
                accepted |= "'self'" in allowed and urlsplit(parent).netloc == urlsplit(base).netloc
                accepted |= any(token.startswith('https://*.') and host.endswith('.' + token[len('https://*.'):]) for token in allowed)
                if not accepted or "'none'" in allowed:
                    errors.append(f'CSP frame-ancestors does not allow {parent}: {allowed}')
    return {'ok': not errors, 'errors': errors, 'parents_checked': list(PARENTS),
            'scope': 'HTTP embedding headers only; parent wrapper CSP/browser behavior not tested'}


def verify_one(name, expected, base, timeout):
    result, data = fetch(urljoin(base, quote(name, safe='/')), base, timeout, len(expected) + 65536)
    result['path'] = name
    result['expected_bytes'] = len(expected)
    result['expected_sha256'] = sha(expected)
    errors = []
    if result.get('status') != 200:
        errors.append(f'Expected HTTP 200, received {result.get("status", result.get("error"))}')
    if data != expected:
        errors.append('Served bytes differ from public docs copy')
    mime = result.get('headers', {}).get('content-type', '').split(';', 1)[0].strip().lower()
    suffix = Path(name).suffix
    allowed = {'.html': {'text/html'}, '.js': {'text/javascript', 'application/javascript'},
               '.mp3': {'audio/mpeg', 'audio/mp3'}, '.css': {'text/css'}}.get(suffix)
    if allowed and mime not in allowed:
        errors.append(f'Unexpected MIME: {mime!r}; expected one of {sorted(allowed)}')
    if suffix == '.html':
        result['framing'] = framing_check(result.get('headers', {}), base, result.get('all_csp_headers'))
        errors.extend(result['framing']['errors'])
    result['errors'], result['ok'] = errors, not errors
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--expected', type=Path, default=DEFAULT_EXPECTED)
    ap.add_argument('--url', default=DEFAULT_URL)
    ap.add_argument('--report', type=Path)
    ap.add_argument('--timeout', type=int, default=30)
    ap.add_argument('--workers', type=int, default=4)
    args = ap.parse_args()
    if urlsplit(args.url).scheme != 'https' or not args.url.endswith('/'):
        ap.error('--url must be an HTTPS project directory ending in /')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    report_path = args.report or Path(__file__).resolve().parent / 'verification' / f'bookone-pages-{stamp}.json'
    if report_path.resolve().is_relative_to(args.expected.resolve().parent):
        ap.error('Report must be outside the read-only public repository')
    payload, stamps = bounded_files(args.expected)
    report = {'started_utc': stamp, 'base_url': args.url, 'expected_root': str(args.expected),
              'read_only_network_methods': ['GET'], 'local': local_checks(payload, args.url),
              'files': [], 'ranges': [], 'limitations': [
                  'No browser execution, service-worker installation or physical iPhone test.',
                  'No claim that iframe/offline storage persists across browsers or origins.',
                  'Checks one current set of network responses; no repeated polling.']}
    if report['local']['ok']:
        root, root_data = fetch(args.url, args.url, args.timeout, len(payload['index.html']) + 65536)
        root['matches_index_html'] = root_data == payload['index.html']
        root['framing'] = framing_check(root.get('headers', {}), args.url, root.get('all_csp_headers'))
        root['html_mime_ok'] = root.get('headers', {}).get('content-type', '').split(';', 1)[0].strip().lower() == 'text/html'
        root['ok'] = root.get('status') == 200 and root['matches_index_html'] and root['html_mime_ok'] and root['framing']['ok']
        report['root'] = root
        if root.get('status') == 200:
            with ThreadPoolExecutor(max_workers=max(1, min(args.workers, 8))) as pool:
                futures = [pool.submit(verify_one, n, b, args.url, args.timeout) for n, b in payload.items()]
                for count, future in enumerate(as_completed(futures), 1):
                    result = future.result()
                    report['files'].append(result)
                    if not result['ok'] or count % 10 == 0 or count == len(payload):
                        print(json.dumps({'progress': f'{count}/{len(payload)}', 'path': result['path'],
                                          'ok': result['ok'], 'errors': result['errors']}), flush=True)
            report['files'].sort(key=lambda row: row['path'])
            book = json.loads(payload['book.json'])
            sample = next(ch['audio'] for ch in book['chapters'] if len(payload[ch['audio']]) >= 101024)
            for start, end in ((0, 1023), (100000, 101023)):
                row, data = fetch(urljoin(args.url, quote(sample, safe='/')), args.url, args.timeout,
                                  len(payload[sample]) + 65536, {'Range': f'bytes={start}-{end}'})
                expected_range = payload[sample][start:end + 1]
                content_range = f'bytes {start}-{end}/{len(payload[sample])}'
                row.update({'path': sample, 'requested_range': f'bytes={start}-{end}',
                            'expected_content_range': content_range, 'expected_sha256': sha(expected_range),
                            'bytes_match': data == expected_range})
                row['ok'] = (row.get('status') == 206 and row['bytes_match']
                             and row.get('headers', {}).get('content-range') == content_range
                             and row.get('headers', {}).get('content-length') == str(len(expected_range)))
                report['ranges'].append(row)
            sw = next(row for row in report['files'] if row['path'] == 'sw.js')
            allowed = sw.get('headers', {}).get('service-worker-allowed')
            maximum = urljoin(urljoin(args.url, 'sw.js'), allowed) if allowed else args.url
            report['worker_scope_headers'] = {'requested_scope': args.url, 'maximum_scope': maximum,
                                               'ok': args.url.startswith(maximum)}
    unchanged = []
    final_names = set()
    for path in args.expected.rglob('*'):
        name = path.relative_to(args.expected).as_posix()
        if path.is_symlink() or path.is_junction():
            unchanged.append(f'Linked entry appeared: {name}')
        elif path.is_file():
            final_names.add(name)
    unchanged.extend(f'File set changed: {name}' for name in sorted(final_names.symmetric_difference(stamps)))
    for name, before in stamps.items():
        path = args.expected / name
        try:
            stat = path.stat()
            if (stat.st_size, stat.st_mtime_ns) != before:
                unchanged.append(name)
        except OSError:
            unchanged.append(name)
    report['expected_files_changed_during_run'] = unchanged
    report['passed_files'] = sum(row['ok'] for row in report['files'])
    report['failed_files'] = [row['path'] for row in report['files'] if not row['ok']]
    report['ok'] = bool(report['local']['ok'] and report.get('root', {}).get('ok')
                        and len(report['files']) == len(payload) and not report['failed_files']
                        and len(report['ranges']) == 2 and all(row['ok'] for row in report['ranges'])
                        and report.get('worker_scope_headers', {}).get('ok') and not unchanged)
    report['finished_utc'] = datetime.now(timezone.utc).isoformat()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({'ok': report['ok'], 'local': report['local'], 'passed_files': report['passed_files'],
                      'failed_files': report['failed_files'], 'ranges_ok': [r['ok'] for r in report['ranges']],
                      'root_status': report.get('root', {}).get('status'),
                      'root_error': report.get('root', {}).get('error'), 'report': str(report_path)}, indent=2), flush=True)
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
