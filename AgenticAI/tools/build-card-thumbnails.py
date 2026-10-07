"""Optionally regenerate reviewed derivatives. CI does not run this Pillow tool."""
from pathlib import Path
from io import BytesIO
import argparse
import copy
import importlib.util
import json

spec = importlib.util.spec_from_file_location('card_thumbnails', Path(__file__).with_name('check-card-thumbnails.py'))
cards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cards)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--site-root', type=Path, default=Path(__file__).resolve().parents[2])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true', help='Reproduce all 12 PNGs in memory and compare; no writes')
    mode.add_argument('--output-root', type=Path, help='Write only the derivatives/metadata to a new review directory')
    args = parser.parse_args()
    # Pillow is optional, and imported only for this explicit regeneration command.
    import PIL
    from PIL import Image
    manifest, _ = cards.load_assets(args.site_root)
    cards.require(PIL.__version__ == manifest['resampling']['pillowVersion'],
                  'Use the recorded Pillow version for deterministic regeneration; CI never installs Pillow')
    output = args.output_root.resolve() if args.output_root else None
    if output is not None:
        cards.require(not output.exists(), 'Output directory must be new; existing source files are never overwritten')
        cards.require(not output.is_relative_to(args.site_root.resolve()), 'Output directory must be outside the source site')
    rebuilt = copy.deepcopy(manifest)
    pending = []
    for slug, record in manifest['images'].items():
        original_path = cards.safe_file(args.site_root, 'AgenticAI/' + record['source'])
        original_bytes = original_path.read_bytes()
        with Image.open(BytesIO(original_bytes)) as original:
            if 'A' in original.getbands():
                cards.require(original.getchannel('A').getextrema() == (255, 255), 'Do not discard meaningful transparency')
            image = original.convert('RGB')
        width, height = image.size
        crop_width = min(width, height * 16 / 9)
        crop_height = crop_width * 9 / 16
        box = ((width-crop_width)/2, (height-crop_height)/2,
               (width+crop_width)/2, (height+crop_height)/2)
        for index, variant in enumerate(record['variants']):
            target_width = variant['width']; target_height = variant['height']
            cards.require(target_width <= crop_width and target_height <= crop_height, 'Upscaling is forbidden')
            resized = image.resize((target_width, target_height), Image.Resampling.LANCZOS,
                                   box=box, reducing_gap=None)
            buffer = BytesIO()
            resized.save(buffer, format='PNG', optimize=True, compress_level=9)
            data = buffer.getvalue()
            cards.require(cards.digest(data) == variant['sha256'] and len(data) == variant['bytes'],
                          'Regenerated PNG differs from reviewed bytes: ' + variant['path'])
            pending.append(('AgenticAI/' + variant['path'], data))
            rebuilt['images'][slug]['variants'][index]['sha256'] = cards.digest(data)
        cards.require(original_path.read_bytes() == original_bytes, 'Original artwork changed during regeneration')
    if output is not None:
        # Everything is generated and hash-checked before any output write.
        for relative, data in pending:
            target = output / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        target = output / cards.MANIFEST
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(rebuilt, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'files':len(pending), 'bytes':sum(len(data) for _, data in pending),
                      'originals_unchanged':True, 'reviewed_hashes_reproduced':True,
                      'output':str(output) if output else None}, indent=2))


if __name__ == '__main__':
    main()
