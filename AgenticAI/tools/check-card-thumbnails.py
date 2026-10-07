"""Validate and render the two reviewed responsive card thumbnails (stdlib only)."""
from pathlib import Path, PurePosixPath
from html import escape
from html.parser import HTMLParser
import argparse
import binascii
import hashlib
import json
import math
import re
import struct

WIDTHS = (320, 368, 480, 640, 736, 960)
SIZES = ('(max-width: 520px) calc(100vw - 42px), '
         '(max-width: 700px) calc(50vw - 34px), '
         '(max-width: 1000px) calc(50vw - 46px), '
         '(max-width: 1184px) calc((100vw - 118px) / 3), 355.333333px')
SOURCES = {
    'sinaiprompt': ('images/sinaiprompt/sin-ai-prompt-thumbnail.png',
                   'images/sinaiprompt/sin-ai-prompt-card-', 'Sin AI Prompt project preview'),
    'pmt': ('images/pmt/pmt-1-thumbnail-draft-1c.png',
            'images/pmt/pmt-1-draft-1c-card-', 'PMT project preview'),
}
MANIFEST = 'AgenticAI/content/card-thumbnails.json'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key: ' + key)
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'), object_pairs_hook=unique_object)


def safe_file(root, relative):
    """No URL interpretation, traversal, aliases, or symlink/junction traversal."""
    require(isinstance(relative, str), 'Asset path must be a string')
    part = PurePosixPath(relative)
    require(relative and part.as_posix() == relative and not part.is_absolute()
            and not any(p in ('.', '..') for p in part.parts)
            and not re.search(r'[\\:%?#\x00-\x20]', relative), 'Invalid asset path: ' + relative)
    root = Path(root).absolute()
    path = root.joinpath(*part.parts)
    require(path.is_relative_to(root), 'Asset leaves its source root')
    for item in (path, *path.parents):
        require(not item.is_symlink() and not getattr(item, 'is_junction', lambda: False)(),
                'Linked paths are not allowed: ' + relative)
        if item == root:
            break
    require(path.is_file(), 'Missing thumbnail input: ' + relative)
    return path


def digest(data):
    return hashlib.sha256(data).hexdigest()


def png_info(data):
    require(len(data) >= 33 and data[:8] == b'\x89PNG\r\n\x1a\n'
            and data[8:16] == b'\x00\x00\x00\rIHDR', 'Invalid PNG header')
    require(binascii.crc32(data[12:29]) & 0xffffffff == struct.unpack('>I', data[29:33])[0],
            'Invalid PNG header checksum')
    width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', data[16:29])
    require(width > 0 and height > 0 and depth == 8 and color in (2, 6)
            and (compression, filtering, interlace) == (0, 0, 0), 'Unsupported reviewed PNG encoding')
    return width, height, color


def verified_png(site_root, relative, expected_hash):
    require(isinstance(expected_hash, str) and re.fullmatch('[0-9a-f]{64}', expected_hash),
            'Invalid SHA256 for ' + relative)
    data = safe_file(site_root, 'AgenticAI/' + relative).read_bytes()
    require(digest(data) == expected_hash, 'PNG hash mismatch: ' + relative)
    return data, png_info(data)


def image_attributes(manifest, slug):
    image = manifest['images'][slug]
    fallback = next(v for v in image['variants'] if v['width'] == 368)
    def url(variant):
        return variant['path'] + '?v=' + variant['sha256'][:16]
    return {
        'src': url(fallback),
        'srcset': ', '.join(url(v) + ' ' + str(v['width']) + 'w' for v in image['variants']),
        'sizes': manifest['sizes'], 'width': '368', 'height': '207',
        'alt': SOURCES[slug][2], 'loading': 'lazy', 'decoding': 'async',
    }


def render_image(manifest, slug):
    return '<img ' + ' '.join(key + '="' + escape(value, quote=True) + '"'
                            for key, value in image_attributes(manifest, slug).items()) + '>'


def load_assets(site_root):
    manifest = read_json(safe_file(site_root, MANIFEST))
    require(type(manifest.get('version')) is int and manifest['version'] == 1, 'Unsupported thumbnail manifest version')
    require(manifest.get('sizes') == SIZES, 'Thumbnail sizes do not match the reviewed CSS layout')
    require(isinstance(manifest.get('images'), dict) and set(manifest['images']) == set(SOURCES),
            'Exactly Sin AI Prompt and PMT must have responsive thumbnails')
    for slug, (source, prefix, _) in SOURCES.items():
        image = manifest['images'][slug]
        require(image.get('source') == source, 'Unexpected original thumbnail source: ' + slug)
        _, (sw, sh, _) = verified_png(site_root, source, image.get('sourceSha256'))
        require((image.get('sourceWidth'), image.get('sourceHeight')) == (sw, sh), 'Source dimensions differ: ' + slug)
        crop = image.get('cropBox')
        require(isinstance(crop, list) and len(crop) == 4
                and all(type(v) in (float, int) and math.isfinite(v) for v in crop), 'Invalid center crop: ' + slug)
        cw = min(sw, sh * 16 / 9); ch = cw * 9 / 16
        expected_crop = [(sw-cw)/2, (sh-ch)/2, (sw+cw)/2, (sh+ch)/2]
        require(all(abs(a-b) < 1e-6 for a, b in zip(crop, expected_crop)), 'Crop must retain the reviewed centered artwork')
        variants = image.get('variants')
        require(isinstance(variants, list) and len(variants) == len(WIDTHS), 'Expected six thumbnail widths: ' + slug)
        require([v.get('width') for v in variants] == list(WIDTHS), 'Unexpected or duplicate thumbnail widths: ' + slug)
        for variant in variants:
            width = variant['width']; height = width * 9 // 16
            expected_path = prefix + str(width) + '.png'
            require(type(width) is int and variant.get('path') == expected_path, 'Unexpected thumbnail path: ' + slug)
            require(type(variant.get('height')) is int and variant['height'] == height, 'Thumbnail must be exactly 16:9')
            require(width <= cw and height <= ch, 'Thumbnail would upscale the original')
            data, dimensions = verified_png(site_root, expected_path, variant.get('sha256'))
            require(dimensions == (width, height, 2), 'Derivative PNG must have reviewed RGB dimensions: ' + expected_path)
            require(type(variant.get('bytes')) is int and len(data) == variant['bytes'], 'Derivative byte size differs: ' + expected_path)
    return manifest, {slug: render_image(manifest, slug) for slug in SOURCES}


class CardImages(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []
        self.cards = []
        self.current = None

    def handle_starttag(self, tag, attrs):
        if tag == 'img' and self.current is not None:
            require(len({name for name, _ in attrs}) == len(attrs), 'Duplicate image attributes are not allowed')
        attrs = dict(attrs)
        classes = attrs.get('class', '').split()
        if tag in ('a', 'article') and 'project-card' in classes:
            require(self.current is None, 'Nested project card')
            self.current = {'depth': len(self.stack), 'tag': tag, 'images': []}
            self.cards.append(self.current)
        if tag == 'img' and self.current is not None:
            self.current['images'].append(attrs)
        if tag not in ('area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'):
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if self.current is not None and tag == self.current['tag'] and len(self.stack)-1 == self.current['depth']:
            self.current = None
        if self.stack and self.stack[-1] == tag:
            self.stack.pop()


def check_html(site_root, manifest, page_path='AgenticAI/Index.html'):
    page = CardImages()
    page.feed(safe_file(site_root, page_path).read_text(encoding='utf-8-sig'))
    require(len(page.cards) == 6 and all(len(c['images']) == 1 for c in page.cards), 'Expected one image in each of six project cards')
    all_images = [c['images'][0] for c in page.cards]
    for slug in SOURCES:
        expected = image_attributes(manifest, slug)
        matches = [attrs for attrs in all_images if attrs.get('alt') == expected['alt']]
        require(matches == [expected], 'Responsive thumbnail markup/cache key differs: ' + slug)
    other_images = [attrs for attrs in all_images if attrs.get('alt') not in {value[2] for value in SOURCES.values()}]
    require(all('srcset' not in attrs and 'sizes' not in attrs for attrs in other_images), 'Responsive changes must remain limited to the two approved cards')


def check_allowlist(path, manifest):
    entries = read_json(path)
    for image in manifest['images'].values():
        for variant in image['variants']:
            relative = 'AgenticAI/' + variant['path']
            expected = {'source': 'main', 'path': relative, 'deployed': relative}
            require([e for e in entries if e.get('path') == relative or e.get('deployed') == relative] == [expected],
                    'Derivative must have exactly its approved publication entry: ' + relative)
    require(all(e.get('path') != MANIFEST and e.get('deployed') != MANIFEST for e in entries),
            'Authoring thumbnail metadata must not be published')


def validate(site_root, payload_root=None, require_private=False):
    site_root = Path(site_root)
    manifest, _ = load_assets(site_root)
    check_html(site_root, manifest)
    ci = safe_file(site_root, '.github/static-site/publish-files.json')
    check_allowlist(ci, manifest)
    checked = [ci.as_posix()]
    private = site_root/'Deployment/publish-files.json'
    if require_private or private.exists():
        private = safe_file(site_root, 'Deployment/publish-files.json')
        check_allowlist(private, manifest)
        checked.append(private.as_posix())
    if payload_root is not None:
        check_html(payload_root, manifest, 'AgenticAI/index.html')
        for image in manifest['images'].values():
            for variant in image['variants']:
                verified_png(payload_root, variant['path'], variant['sha256'])
    return {'cards': 2, 'variants': 12, 'bytes': sum(v['bytes'] for i in manifest['images'].values() for v in i['variants']),
            'publication_manifests_checked': len(checked), 'payload_checked': payload_root is not None,
            'sizes': SIZES, 'passed': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--site-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--payload-root', type=Path)
    parser.add_argument('--require-private', action='store_true')
    parser.add_argument('--render-json', action='store_true', help='Verify source images and emit generator markup; do not inspect stale HTML')
    args = parser.parse_args()
    try:
        result = load_assets(args.site_root)[1] if args.render_json else validate(args.site_root, args.payload_root, args.require_private)
        print(json.dumps(result, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(1, 'Thumbnail validation failed: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
