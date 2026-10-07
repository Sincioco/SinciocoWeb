# Responsive project-card images

Only the Sin AI Prompt and PMT cards use responsive derivatives. Their originals
are retained unchanged. `../content/card-thumbnails.json` records the reviewed
original SHA256 hashes, center crops, dimensions, Pillow version and every output
hash. This authoring metadata and all tools stay outside the public allowlist.

`Build-Projects.ps1` calls `check-card-thumbnails.py --render-json` with Python 3
before rendering cards. This verifies original/derivative hashes, PNG headers,
sizes and bounded paths, then emits the exact two image tags. The fallback is
368 by 207; width candidates are 320, 368, 480, 640, 736 and 960. The `sizes`
attribute accounts for the existing container, grid gaps and card borders.
The other four cards retain their original markup and CSS behavior.

The general `tools/Update-AssetVersions.ps1` intentionally remains `src`/`href`
only. Each responsive URL is emitted with `?v=` plus its SHA256's first 16 hex
characters. The dedicated checker validates every `srcset` URL, descriptor,
cache key, fallback and `sizes` value against the immutable reviewed files.
Do not hand-edit these attributes or reuse a cache key for different bytes.

Run from any working directory, replacing `<site>` with the repository root:

```text
python -B <site>/AgenticAI/tools/check-card-thumbnails.py --site-root <site>
python -B <site>/AgenticAI/tools/test-card-thumbnails.py
```

CI's `verify-stage.py` calls that same checker with its prepared payload. It
checks the tracked `.github/static-site/publish-files.json` and all 12 deployed
files. The manual `Deployment/verify-stage.py` additionally requires the private
`Deployment/publish-files.json`; both manifests must contain the same explicit
12 derivative entries. A clone without the ignored private Deployment directory
validates its tracked manifest only. Metadata and helper scripts are not deployed.
Validation and CI use only Python's standard library, with no image dependency
installation or image regeneration during deployment.
The focused synthetic-image regression suite is included automatically by
`.github/static-site/test-ci.py`; it checks malformed metadata/files, unsafe paths,
publication omissions, stale hashes and source/payload markup before upload.

## Reproducing the reviewed images

The optional `build-card-thumbnails.py` tool needs the recorded Pillow version
(currently 12.0.0). It does not install dependencies. It uses the existing source
images, converts their opaque pixels to RGB, applies the recorded floating-point
center crop, and resizes once with `Image.Resampling.LANCZOS`, `reducing_gap=None`.
It adds no sharpening and never upscales. PNG output is lossless RGB with
`optimize=True` and `compress_level=9`.

```text
python -B <site>/AgenticAI/tools/build-card-thumbnails.py --site-root <site> --check
python -B <site>/AgenticAI/tools/build-card-thumbnails.py --site-root <site> --output-root <new-review-directory>
```

`--check` regenerates in memory and requires all 12 reviewed byte hashes to match.
`--output-root` requires a new directory outside the source site, and writes only
those verified derivatives plus metadata. Originals are never overwritten. A new
artwork choice, derivative width, output encoding or image-library version needs
a reviewed metadata/tooling update, new hashes, regenerated card markup, and
explicit publication entries before deployment.
